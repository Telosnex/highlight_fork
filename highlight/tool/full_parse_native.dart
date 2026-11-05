// Native full-parse and isolate round-trip probe; optionally emit a private
// browser test ONLY into ignored build/. Never embeds private text in lib/test.
// dart run tool/full_parse_native.dart [--bundle /path/to/hleval] [--emit-test]
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:highlight_fork/highlight.dart' as hi;

import 'eval_support.dart';
import 'full_parse_support.dart';

Future<void> main(List<String> args) async {
  hi.ensureInitialized();
  final bundleIndex = args.indexOf('--bundle');
  final bundled = bundleIndex >= 0;
  final sources = bundled
      ? {
          for (final file
              in (Directory('${args[bundleIndex + 1]}/docs')
                  .listSync()
                  .whereType<File>()
                  .where((file) => file.path.endsWith('.txt'))
                  .toList()
                ..sort((a, b) => a.path.compareTo(b.path))))
            file.uri.pathSegments.last.replaceFirst('.txt', ''): file
                .readAsStringSync(),
        }
      : publicCorpus.map((key, value) => MapEntry(key, sizedSource(value)));
  final corpus = bundled ? 'private-bundled' : 'public-generated-v1';
  if (args.contains('--emit-test')) {
    final dir = Directory('build/full_parse')..createSync(recursive: true);
    for (final name in ['eval_support.dart', 'full_parse_support.dart']) {
      File('tool/$name').copySync('${dir.path}/$name');
    }
    final encoded = base64Encode(utf8.encode(jsonEncode(sources)));
    File('${dir.path}/bundled_full_parse_test.dart').writeAsStringSync('''
// GENERATED PRIVATE DOCUMENTS. DO NOT COMMIT.
import 'dart:convert';
import 'package:highlight_fork/highlight.dart' as hi;
import 'package:test/test.dart';
import 'full_parse_support.dart';
void main() {
  test('bundled full parse sizes (metrics only)', () {
    hi.ensureInitialized();
    final sources = (jsonDecode(utf8.decode(base64Decode('$encoded'))) as Map)
        .cast<String, String>();
    for (final entry in sources.entries) {
      for (final metrics in fullParseSizes(entry.key, entry.value,
          corpus: '$corpus')) {
        print(jsonEncode(metrics));
      }
    }
  });
}
''');
    return;
  }
  for (final entry in sources.entries) {
    for (final metrics in fullParseSizes(
      entry.key,
      entry.value,
      corpus: corpus,
    )) {
      print(jsonEncode(metrics));
    }
  }
  // Include worker initialization, parsing, flattening, transfer and teardown.
  for (final entry in sources.entries) {
    if (entry.value.length < 20480) continue;
    final language = entry.key;
    final source = linePrefix(entry.value, 20480);
    List<List<String>> parseRuns() {
      hi.ensureInitialized();
      return flatten(hi.hljs.highlight(source, language: language));
    }

    for (final isolate in [false, true]) {
      final samples = <int>[];
      for (var i = 0; i < 25; i++) {
        final watch = Stopwatch()..start();
        final runs = isolate ? await Isolate.run(parseRuns) : parseRuns();
        watch.stop();
        if (runText(runs) != source) throw StateError('Source changed');
        if (i >= 5) samples.add(watch.elapsedMicroseconds);
      }
      print(
        jsonEncode({
          'event': 'plain-runs-roundtrip',
          'corpus': corpus,
          'language': language,
          'utf16Units': source.length,
          'isolate': isolate,
          'warmups': 5,
          ...timingSummary(samples),
        }),
      );
    }
  }
}
