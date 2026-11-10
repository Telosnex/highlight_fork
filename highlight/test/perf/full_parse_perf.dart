// Compares the engine in lib/ with the 0.8.0 engine in test/perf/baseline/.
//
// JIT, for iteration:
//   dart run test/perf/full_parse_perf.dart
// AOT, for decisions:
//   dart run perf_tester:aot test/perf/full_parse_perf.dart
// CPU profile of each engine (JIT only), written to build/perf_profiles/:
//   dart run --enable-vm-service test/perf/full_parse_perf.dart --profile json
//
// Arguments:
//   <name>...        Run only the rows with these names (`typescript json`).
//   --stream         Add the line-by-line continuation workload.
//   --runs=N         Number of samples (default 40).
//   --file=PATH:LANG Add a local file as a row. Use `auto` for detection.
//
// Workloads:
//   full    One parse of a 4 KB and a 16 KB source in each language.
//   large   Inputs that made 0.8.0 quadratic: a 128 KB JSON document with
//           long strings, and 32 KB of prose in a grammar where almost
//           every character is illegal (http).
//   auto    Language detection on 4 KB sources, over the registered grammars.
//   stream  One parse for each line, from the checkpoint of the line before.
//
// Both engines must give the same token runs and relevance.
import 'dart:io';
import 'dart:math' as math;

import 'package:highlight_fork/highlight_core.dart' as cur;
import 'package:highlight_fork/languages/bash.dart' as cur_bash;
import 'package:highlight_fork/languages/cpp.dart' as cur_cpp;
import 'package:highlight_fork/languages/css.dart' as cur_css;
import 'package:highlight_fork/languages/dart.dart' as cur_dart;
import 'package:highlight_fork/languages/http.dart' as cur_http;
import 'package:highlight_fork/languages/javascript.dart' as cur_javascript;
import 'package:highlight_fork/languages/json.dart' as cur_json;
import 'package:highlight_fork/languages/markdown.dart' as cur_markdown;
import 'package:highlight_fork/languages/python.dart' as cur_python;
import 'package:highlight_fork/languages/typescript.dart' as cur_typescript;
import 'package:highlight_fork/languages/xml.dart' as cur_xml;
import 'package:highlight_fork/languages/yaml.dart' as cur_yaml;
import 'package:perf_tester/perf_tester.dart';

import 'baseline/highlight_core.dart' as old;
import 'baseline/languages/bash.dart' as old_bash;
import 'baseline/languages/cpp.dart' as old_cpp;
import 'baseline/languages/css.dart' as old_css;
import 'baseline/languages/dart.dart' as old_dart;
import 'baseline/languages/http.dart' as old_http;
import 'baseline/languages/javascript.dart' as old_javascript;
import 'baseline/languages/json.dart' as old_json;
import 'baseline/languages/markdown.dart' as old_markdown;
import 'baseline/languages/python.dart' as old_python;
import 'baseline/languages/typescript.dart' as old_typescript;
import 'baseline/languages/xml.dart' as old_xml;
import 'baseline/languages/yaml.dart' as old_yaml;
import 'corpus.dart';

final oldEngine = old.Highlight()
  ..registerLanguage('bash', old_bash.bash)
  ..registerLanguage('cpp', old_cpp.cpp)
  ..registerLanguage('css', old_css.css)
  ..registerLanguage('dart', old_dart.dart)
  ..registerLanguage('http', old_http.http)
  ..registerLanguage('javascript', old_javascript.javascript)
  ..registerLanguage('json', old_json.json)
  ..registerLanguage('markdown', old_markdown.markdown)
  ..registerLanguage('python', old_python.python)
  ..registerLanguage('typescript', old_typescript.typescript)
  ..registerLanguage('xml', old_xml.xml)
  ..registerLanguage('yaml', old_yaml.yaml);

final curEngine = cur.Highlight()
  ..registerLanguage('bash', cur_bash.bash)
  ..registerLanguage('cpp', cur_cpp.cpp)
  ..registerLanguage('css', cur_css.css)
  ..registerLanguage('dart', cur_dart.dart)
  ..registerLanguage('http', cur_http.http)
  ..registerLanguage('javascript', cur_javascript.javascript)
  ..registerLanguage('json', cur_json.json)
  ..registerLanguage('markdown', cur_markdown.markdown)
  ..registerLanguage('python', cur_python.python)
  ..registerLanguage('typescript', cur_typescript.typescript)
  ..registerLanguage('xml', cur_xml.xml)
  ..registerLanguage('yaml', cur_yaml.yaml);

/// A null language means detection.
typedef Case = ({String? language, String source});
typedef Impl = List<Object> Function(Case);
typedef Scenario = ({
  String workload,
  String name,
  List<Case> cases,
  Impl old,
  Impl cur,
});

/// Lossless `[text, scope path]` runs, then the language and relevance. The
/// two engines have separate node classes, so the walk is dynamic.
List<Object> flatten(Iterable<dynamic> results) {
  final runs = <Object>[];
  String? lastScope;
  final text = StringBuffer();
  void flush() {
    if (lastScope != null) runs.add([text.toString(), lastScope]);
    text.clear();
  }

  void walk(dynamic node, String path) {
    if (node is String) {
      if (node.isEmpty) return;
      if (path != lastScope) {
        flush();
        lastScope = path;
      }
      text.write(node);
      return;
    }
    final scope = node.scope as String?;
    final next = scope == null || scope.isEmpty ? path : '$path>$scope';
    for (final child in node.children as List) {
      walk(child, next);
    }
  }

  for (final result in results) {
    if (result.errorRaised != null) throw result.errorRaised as Object;
    walk(result.emitter.root, '');
    flush();
    lastScope = null;
    runs.add(result.language as String);
    runs.add(result.relevance as num);
  }
  return runs;
}

/// One complete parse, as for a finished code block.
List<Object> fullOld(Case c) => flatten([
  c.language == null
      ? oldEngine.highlightAuto(c.source)
      : oldEngine.highlight(c.source, language: c.language!),
]);

List<Object> fullCur(Case c) => flatten([
  c.language == null
      ? curEngine.highlightAuto(c.source)
      : curEngine.highlight(c.source, language: c.language!),
]);

Iterable<String> _lines(String source) sync* {
  for (var start = 0; start < source.length;) {
    final end = source.indexOf('\n', start) + 1;
    yield source.substring(start, end == 0 ? source.length : end);
    if (end == 0) break;
    start = end;
  }
}

/// One parse per line, each from the checkpoint of the line before, as for a
/// code block that streams in.
List<Object> streamOld(Case c) {
  old.HighlightContinuation? state;
  final results = <old.HighlightResult>[];
  for (final line in _lines(c.source)) {
    final result = oldEngine.highlight(
      line,
      language: c.language!,
      continuation: state,
    );
    state = result.continuation;
    results.add(result);
  }
  return flatten(results);
}

List<Object> streamCur(Case c) {
  cur.HighlightContinuation? state;
  final results = <cur.HighlightResult>[];
  for (final line in _lines(c.source)) {
    final result = curEngine.highlight(
      line,
      language: c.language!,
      continuation: state,
    );
    state = result.continuation;
    results.add(result);
  }
  return flatten(results);
}

bool _sameRuns(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameRuns(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Future<void> main(List<String> args) async {
  final profile = args.contains('--profile');
  var runs = 40;
  final only = <String>{};
  final files = <Scenario>[];
  for (final arg in args) {
    if (arg.startsWith('--runs=')) {
      runs = int.parse(arg.substring('--runs='.length));
    } else if (arg.startsWith('--file=')) {
      final spec = arg.substring('--file='.length);
      final colon = spec.lastIndexOf(':');
      final language = spec.substring(colon + 1);
      files.add((
        workload: 'file',
        name: language,
        cases: [
          (
            language: language == 'auto' ? null : language,
            source: File(spec.substring(0, colon)).readAsStringSync(),
          ),
        ],
        old: fullOld,
        cur: fullCur,
      ));
    } else if (!arg.startsWith('--')) {
      only.add(arg);
    }
  }

  final scenarios = <Scenario>[
    for (final language in corpus.keys)
      (
        workload: 'full',
        name: language,
        cases: [
          for (final size in [4096, 16384])
            (language: language, source: sized(corpus[language]!, size)),
        ],
        old: fullOld,
        cur: fullCur,
      ),
    (
      workload: 'large',
      name: 'json-long',
      cases: [(language: 'json', source: longStringJson(128 * 1024))],
      old: fullOld,
      cur: fullCur,
    ),
    (
      workload: 'large',
      name: 'http-prose',
      cases: [(language: 'http', source: sized(corpus['markdown']!, 32768))],
      old: fullOld,
      cur: fullCur,
    ),
    for (final language in ['dart', 'json', 'markdown', 'typescript'])
      (
        workload: 'auto',
        name: 'auto-$language',
        cases: [(language: null, source: sized(corpus[language]!, 4096))],
        old: fullOld,
        cur: fullCur,
      ),
    if (args.contains('--stream'))
      for (final language in corpus.keys)
        (
          workload: 'stream',
          name: language,
          cases: [
            (language: language, source: sized(corpus[language]!, 16384)),
          ],
          old: streamOld,
          cur: streamCur,
        ),
    ...files,
  ];
  final unknown = only.difference({for (final s in scenarios) s.name});
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown rows: $unknown');
    exit(64);
  }

  final rows = <String>[];
  final speedups = <String, List<double>>{};
  final totals = <String, (double, double)>{};
  var failed = false;
  String? mode;
  for (final scenario in scenarios) {
    if (only.isNotEmpty && !only.contains(scenario.name)) continue;
    final result =
        await PerfTester<Case, List<Object>>.multi(
          testName: '${scenario.workload} ${scenario.name}',
          testCases: scenario.cases,
          implementations: [
            PerfImpl('0.8.0', scenario.old),
            PerfImpl('current', scenario.cur),
          ],
          equalityCheck: _sameRuns,
        ).run(
          warmupRuns: math.min(20, runs),
          benchmarkRuns: runs,
          profile: profile,
          profileRuns: 60,
          profileTopN: 25,
          profileSaveDir: profile ? 'build/perf_profiles' : null,
          reporter: profile ? null : const SilentReporter(),
        );
    mode = result.compilationMode.name;
    final [oldImpl, curImpl] = result.implementations;
    final comparison = result.comparisons.single;
    if (!result.verification.passed) failed = true;
    final (oldTotal, curTotal) = totals[scenario.workload] ?? (0.0, 0.0);
    totals[scenario.workload] = (
      oldTotal + oldImpl.median,
      curTotal + curImpl.median,
    );
    (speedups[scenario.workload] ??= []).add(comparison.speedup);
    rows.add(
      '${scenario.workload.padRight(7)}${scenario.name.padRight(16)}'
      '${_us(oldImpl.median)}${_us(curImpl.median)}'
      '${'${comparison.speedup.toStringAsFixed(2)}x'.padLeft(9)}  '
      '${comparison.verdict.name}'
      '${result.verification.passed ? '' : '  OUTPUT MISMATCH'}',
    );
  }
  for (final MapEntry(key: workload, value: (oldTotal, curTotal))
      in totals.entries) {
    final values = speedups[workload]!;
    final geomean = math.exp(
      values.map(math.log).reduce((a, b) => a + b) / values.length,
    );
    rows.add(
      '${workload.padRight(7)}${'ALL'.padRight(16)}'
      '${_us(oldTotal)}${_us(curTotal)}'
      '${'${geomean.toStringAsFixed(2)}x'.padLeft(9)}  geometric mean',
    );
  }

  print('');
  print('Median time for one pass over the cases of a row ($mode, $runs runs)');
  print(
    '${'work'.padRight(7)}${'row'.padRight(16)}'
    '${'0.8.0 µs'.padLeft(11)}${'current µs'.padLeft(11)}'
    '${'speedup'.padLeft(9)}',
  );
  rows.forEach(print);
  if (failed) {
    stderr.writeln('The engines gave different output.');
    exit(1);
  }
}

String _us(double ms) => (ms * 1000).toStringAsFixed(0).padLeft(11);
