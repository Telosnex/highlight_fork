// Reproduce the private evaluation without embedding or copying its inputs.
// From highlight/: dart run tool/evaluate.dart --bundle /path/to/hleval \
//   --output /tmp/highlight-evaluation [--skip-stream] [--emit-browser-test]
//   [--emit-browser-stream-test]
// --emit-browser-stream-test creates bundled_stream_test.dart and a copy of
// the public shared helper in the output directory. Run that test with the
// same browser/compiler arguments below; its generated contents are private.
// To check all fixture token runs against native in a browser, emit into the
// ignored build/evaluation directory then run:
// dart test build/evaluation/fixture_parity_test.dart --platform chrome \
//   --compiler dart2js  # repeat with dart2wasm
// Output is intentionally external; do not check private source runs into git.
import 'dart:convert';
import 'dart:io';

import 'package:highlight_fork/highlight.dart' as hi;

import 'eval_support.dart';

void main(List<String> args) {
  String? option(String name) {
    final index = args.indexOf(name);
    if (index < 0 || index + 1 == args.length) return null;
    return args[index + 1];
  }

  final bundle = option('--bundle');
  final output = option('--output');
  if (bundle == null || output == null) {
    stderr.writeln(
      'Usage: dart run tool/evaluate.dart --bundle DIR --output DIR '
      '[--skip-stream] [--emit-browser-test] [--emit-browser-stream-test]',
    );
    exitCode = 64;
    return;
  }
  hi.ensureInitialized();
  final destination = Directory(output)..createSync(recursive: true);
  File out(String name) => File('${destination.path}/$name');
  final inputs =
      (jsonDecode(File('$bundle/inputs.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
  final aliases = File('$bundle/aliases.txt')
      .readAsLinesSync()
      .expand((line) => line.split(RegExp(r'[,\s]+')))
      .where((alias) => alias.isNotEmpty);
  final aliasStatus = {
    for (final alias in aliases) alias: hi.hljs.hasLanguage(alias),
  };
  final results = <Map<String, Object?>>[];
  final detection = <String>[];
  final detectionMismatches = <Map<String, String>>[];
  var allRegistryCorrect = 0;
  var subsetCorrect = 0;
  var errors = 0;
  var sourceFailures = 0;
  for (final input in inputs) {
    final alias = input['alias'] as String;
    final name = input['name'] as String;
    final source = input['text'] as String;
    final watch = Stopwatch()..start();
    var runs = <List<String>>[];
    String? error;
    try {
      final result = hi.hljs.highlight(source, language: alias);
      runs = flatten(result);
      if (result.errorRaised != null) error = '${result.errorRaised}';
      if (runText(runs) != source) {
        sourceFailures++;
        error = '${error == null ? '' : '$error; '}source changed';
      }
    } catch (exception) {
      error = '$exception';
    }
    watch.stop();
    if (error != null) errors++;
    results.add({
      'alias': alias,
      'name': name,
      'runs': runs,
      'err': error,
      'us': watch.elapsedMicroseconds,
    });
    if ((name.startsWith('detect/') || name == 'vue/detect.txt')) {
      try {
        final all = hi.hljs.highlightAuto(source);
        final subset = hi.hljs.highlightAuto(
          source,
          languageSubset: inputs
              .map((item) => item['alias'] as String)
              .toSet()
              .toList(),
        );
        detection.add('$alias\t${all.language}\t${subset.language}\t$name');
        results.last['detectedAll'] = all.language;
        results.last['detectedSubset'] = subset.language;
        final expectedMode = hi.hljs.getLanguage(alias);
        final allCorrect = identical(
          expectedMode,
          hi.hljs.getLanguage(all.language),
        );
        final localCorrect = identical(
          expectedMode,
          hi.hljs.getLanguage(subset.language),
        );
        if (allCorrect) allRegistryCorrect++;
        if (localCorrect) subsetCorrect++;
        if (!allCorrect || !localCorrect) {
          detectionMismatches.add({
            'expected': alias,
            'name': name,
            'allRegistry': all.language,
            'subset': subset.language,
          });
        }
      } catch (exception) {
        detection.add('$alias\tERROR\t$exception\t$name');
      }
    }
  }
  out(
    'runs.json',
  ).writeAsStringSync(jsonEncode({'aliases': aliasStatus, 'results': results}));
  out('detect.tsv').writeAsStringSync('${detection.join('\n')}\n');
  if (args.contains('--emit-browser-test')) {
    out(
      'fixture_parity_test.dart',
    ).writeAsStringSync(browserParityTest(inputs, results));
  }
  if (args.contains('--emit-browser-stream-test')) {
    final documents = bundleDocuments(bundle);
    final sources = {
      for (final document in documents)
        document.uri.pathSegments.last.replaceFirst('.txt', ''): document
            .readAsStringSync(),
    };
    out(
      'bundled_stream_test.dart',
    ).writeAsStringSync(browserStreamTest(sources));
    // Copy the checked-in helper verbatim, rather than generating a second
    // benchmark implementation whose behavior could drift from native runs.
    final helper = File.fromUri(Platform.script.resolve('eval_support.dart'));
    if (helper.absolute.path != out('eval_support.dart').absolute.path) {
      helper.copySync(out('eval_support.dart').path);
    }
  }
  final comparisons = <String, Object?>{};
  for (final baseline in ['old', 'new']) {
    final file = File('$bundle/$baseline.json');
    if (!file.existsSync()) continue;
    comparisons[baseline] = compareRuns(
      ((jsonDecode(file.readAsStringSync()) as Map)['results'] as List),
      results,
    );
  }
  final streams = <Map<String, Object?>>[];
  if (!args.contains('--skip-stream')) {
    final documents = bundleDocuments(bundle);
    for (final document in documents) {
      final language = document.uri.pathSegments.last.replaceFirst('.txt', '');
      stdout.writeln('Streaming $language...');
      streams.add(streamBenchmark(language, document.readAsStringSync()));
    }
    out(
      'stream.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(streams));
    out('stream.tsv').writeAsStringSync(
      [
        'language\tmode\ttotal_us\tworst_us\tscope_difference_units',
        for (final row in streams) ...[
          '${row['language']}\tfull\t${row['fullTotalUs']}\t${row['fullWorstUs']}\t0',
          '${row['language']}\tincremental\t${row['incrementalTotalUs']}\t${row['incrementalWorstUs']}\t${row['scopeDifferenceUnits']}',
        ],
      ].join('\n'),
    );
  }
  final summary = {
    'fixtureCount': inputs.length,
    'errors': errors,
    'sourceFailures': sourceFailures,
    'missingAliases': aliasStatus.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toList(),
    'detection': {
      'fixtureCount': detection.length,
      'allRegistryCorrect': allRegistryCorrect,
      'subsetCorrect': subsetCorrect,
      'mismatches': detectionMismatches,
    },
    'comparisons': comparisons,
    'streams': streams,
  };
  final json = const JsonEncoder.withIndent('  ').convert(summary);
  out('summary.json').writeAsStringSync(json);
  stdout.writeln(json);
  if (errors > 0 || sourceFailures > 0 || aliasStatus.containsValue(false)) {
    exitCode = 1;
  }
}

Map<String, Object?> compareRuns(
  List<dynamic> baseline,
  List<Map<String, Object?>> actual,
) {
  final indexed = {
    for (final row in baseline) '${row['alias']}\u0000${row['name']}': row,
  };
  final stats = <String, Map<String, int>>{};
  final differences = <String, Map<String, int>>{};
  final textChanges = <String>[];
  for (final row in actual) {
    final key = '${row['alias']}\u0000${row['name']}';
    final previous = indexed[key];
    if (previous == null || row['err'] != null) continue;
    List<List<String>> typed(dynamic runs) =>
        (runs as List).map((run) => (run as List).cast<String>()).toList();
    final oldRuns = typed(previous['runs']);
    final newRuns = typed(row['runs']);
    final source = runText(oldRuns);
    if (source != runText(newRuns)) {
      textChanges.add('${row['alias']}/${row['name']}');
      continue;
    }
    final oldScopes = scopeUnits(oldRuns, normalize: true);
    final newScopes = scopeUnits(newRuns, normalize: true);
    final alias = row['alias'] as String;
    final counts = stats.putIfAbsent(
      alias,
      () => {'units': 0, 'same': 0, 'oldStyled': 0, 'newStyled': 0},
    );
    final changes = differences.putIfAbsent(alias, () => {});
    // UTF-16 units are intentional: Dart offsets and token spans use UTF-16.
    for (var i = 0; i < source.length; i++) {
      if (source[i].trim().isEmpty) continue;
      counts['units'] = counts['units']! + 1;
      if (oldScopes[i] == newScopes[i]) {
        counts['same'] = counts['same']! + 1;
      } else {
        final transition = '${oldScopes[i]} -> ${newScopes[i]}';
        changes[transition] = (changes[transition] ?? 0) + 1;
      }
      if (oldScopes[i].isNotEmpty) {
        counts['oldStyled'] = counts['oldStyled']! + 1;
      }
      if (newScopes[i].isNotEmpty) {
        counts['newStyled'] = counts['newStyled']! + 1;
      }
    }
  }
  final total = stats.values.fold(0, (sum, row) => sum + row['units']!);
  final same = stats.values.fold(0, (sum, row) => sum + row['same']!);
  return {
    'textChanges': textChanges,
    'nonWhitespaceUtf16Units': total,
    'sameScopeFraction': total == 0 ? 1 : same / total,
    'byAlias': {
      for (final entry in stats.entries)
        entry.key: {
          ...entry.value,
          'sameScopeFraction': entry.value['same']! / entry.value['units']!,
          'topDifferences':
              (differences[entry.key]!.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)))
                  .take(5)
                  .map((e) => {'transition': e.key, 'units': e.value})
                  .toList(),
        },
    },
  };
}

/// Emit only to a local ignored/external directory. This contains fixture text,
/// so it is deliberately generated rather than committed to the repository.
String browserParityTest(
  List<Map<String, dynamic>> inputs,
  List<Map<String, Object?>> results,
) {
  final encoded = base64Encode(
    utf8.encode(jsonEncode({'inputs': inputs, 'expected': results})),
  );
  return """
// GENERATED LOCAL EVALUATION FIXTURES. DO NOT COMMIT.
import 'dart:convert';
import 'package:highlight_fork/highlight.dart' as hi;
import 'package:test/test.dart';

List<List<String>> flatten(dynamic node, [String path = '']) {
  if (node is String) return node.isEmpty ? [] : [[node, path]];
  final scope = (node as hi.DataNode).scope;
  final next = scope == null || scope.isEmpty ? path :
      path.isEmpty ? scope : '\$path>\$scope';
  return [for (final child in node.children) ...flatten(child, next)];
}
List<List<String>> coalesce(List<List<String>> runs) {
  final result = <List<String>>[];
  for (final run in runs) {
    if (result.isNotEmpty && result.last[1] == run[1]) {
      result.last[0] += run[0];
    } else {
      result.add(run);
    }
  }
  return result;
}
void main() {
  hi.ensureInitialized();
  final data = jsonDecode(utf8.decode(base64Decode('$encoded'))) as Map;
  final inputs = data['inputs'] as List;
  final expected = data['expected'] as List;
  for (var index = 0; index < inputs.length; index++) {
    final input = inputs[index] as Map;
    final alias = input['alias'] as String;
    final name = input['name'] as String;
    final text = input['text'] as String;
    test('\$alias/\$name native parity', () {
      final result = hi.hljs.highlight(text, language: alias);
      expect(result.errorRaised, isNull);
      final runs = coalesce(flatten(result.emitter.root));
      expect(runs.map((run) => run[0]).join(), text);
      expect(runs, expected[index]['runs']);
      if ((name.startsWith('detect/') || name == 'vue/detect.txt')) {
        final detected = hi.hljs.highlightAuto(text).language;
        expect(detected, expected[index]['detectedAll']);
        final subset = hi.hljs.highlightAuto(text, languageSubset:
          inputs.map((item) => item['alias'] as String).toSet().toList()).language;
        expect(subset, expected[index]['detectedSubset']);
        print(jsonEncode({'alias': alias, 'name': name,
          'detected': detected, 'subset': subset}));
      }
    });
  }
}
""";
}

List<File> bundleDocuments(String bundle) =>
    Directory('$bundle/docs')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.txt'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Generated tests contain private bundled documents. Never check them in.
String browserStreamTest(Map<String, String> sources) {
  final encoded = base64Encode(utf8.encode(jsonEncode(sources)));
  return """
// GENERATED PRIVATE BUNDLED DOCUMENTS. DO NOT COMMIT.
import 'dart:convert';
import 'package:highlight_fork/highlight.dart' as hi;
import 'package:test/test.dart';
import 'eval_support.dart';

void main() {
  hi.ensureInitialized();
  final sources = (jsonDecode(utf8.decode(base64Decode('$encoded'))) as Map)
      .cast<String, String>();
  for (final entry in sources.entries) {
    test('bundled streaming \${entry.key}', () {
      final metrics = streamBenchmark(entry.key, entry.value);
      print(jsonEncode(metrics));
      expect(metrics['sourcePreserved'], isTrue);
      expect(metrics['scopeDifferenceUnits'], 0);
      // Timings are reported, not asserted: a noisy shared machine cannot
      // establish a universal hard real-time deadline.
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
""";
}
