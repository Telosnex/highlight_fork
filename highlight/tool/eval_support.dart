// Shared by the local-file evaluator and browser-safe benchmark.
import 'dart:math' as math;

import 'package:highlight_fork/highlight.dart' as hi;

/// Lossless [text, scope-path] runs, compatible with the evaluation bundle.
List<List<String>> flatten(hi.HighlightResult result) {
  final runs = <List<String>>[];
  void walk(dynamic node, List<String> path) {
    if (node is String) {
      if (node.isEmpty) return;
      final scope = path.join('>');
      if (runs.isNotEmpty && runs.last[1] == scope) {
        runs.last[0] += node;
      } else {
        runs.add([node, scope]);
      }
    } else if (node is hi.DataNode) {
      final next = node.scope == null || node.scope!.isEmpty
          ? path
          : [...path, node.scope!];
      for (final child in node.children) {
        walk(child, next);
      }
    } else {
      throw StateError('Unexpected token node: ${node.runtimeType}');
    }
  }

  walk(result.emitter.root, []);
  return runs;
}

String runText(List<List<String>> runs) => runs.map((run) => run[0]).join();

List<String> scopeUnits(List<List<String>> runs, {bool normalize = false}) {
  final scopes = <String>[];
  for (final run in runs) {
    var scope = run[1];
    if (normalize) {
      scope = scope.split('>').last;
      if (scope.startsWith('language:') || scope.startsWith('lang:')) {
        scope = '';
      }
      scope = scope.split('.').first.replaceAll('_', '');
    }
    scopes.addAll(List.filled(run[0].length, scope));
  }
  return scopes;
}

int scopeDifferences(List<List<String>> a, List<List<String>> b) {
  if (runText(a) != runText(b)) return -1;
  final x = scopeUnits(a);
  final y = scopeUnits(b);
  var count = 0;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) count++;
  }
  return count;
}

/// Public, generated data only. No evaluation-bundle documents are embedded.
final publicCorpus = <String, String>{
  'cpp':
      '#include <string>\n// streaming example\nclass Item {\npublic:\n  int value = 42;\n  std::string name = "hello";\n};\n',
  'dart':
      '/// Streaming example.\nclass Item {\n  final String name;\n  const Item(this.name);\n  String greet() => "hello \$name";\n}\n',
  'json':
      '{\n  "name": "example",\n  "active": true,\n  "values": [1, 2, 3],\n  "nested": {"count": 42}\n}\n',
  'markdown':
      '# Heading\n\nA **strong** word and [link](https://example.test).\n\n```dart\nprint("hello");\n```\n\n',
  'python':
      '# Streaming example\nclass Item:\n    def __init__(self, name):\n        self.name = name\n    def greet(self):\n        return f"hello {self.name}"\n\n',
  'typescript':
      '// Streaming example\ninterface Item {\n  name: string;\n  count: number;\n}\nconst greet = (item: Item): string => `hello \${item.name}`;\n',
  'yaml':
      '# Streaming example\nname: example\nactive: true\nitems:\n  - first\n  - second\nnested:\n  count: 42\n  text: |\n    hello\n    world\n',
};

String sizedSource(String seed, {int size = 20480}) {
  final out = StringBuffer();
  while (out.length < size) {
    out.write(seed);
  }
  return out.toString().substring(0, size);
}

/// Measures full reparse and the widget's completed-line/tail strategy.
///
/// State snapshots are reused when reparsing the speculative tail. Timing
/// excludes warm-up, source construction, and the final exact-scope check.
/// A mismatch is reported rather than hidden: grammars with future lookahead
/// cannot in general yield full-parse-identical immutable completed lines.
Map<String, Object?> streamBenchmark(
  String language,
  String source, {
  int chunkSize = 80,
}) {
  for (var i = 0; i < 2; i++) {
    hi.hljs.highlight(source, language: language);
  }
  final fullWatch = Stopwatch();
  var fullWorst = 0;
  var calls = 0;
  for (var end = chunkSize; ; end += chunkSize) {
    final stop = math.min(end, source.length);
    fullWatch.start();
    final watch = Stopwatch()..start();
    final result = hi.hljs.highlight(
      source.substring(0, stop),
      language: language,
    );
    watch.stop();
    fullWatch.stop();
    if (result.errorRaised != null) throw result.errorRaised!;
    fullWorst = math.max(fullWorst, watch.elapsedMicroseconds);
    calls++;
    if (stop == source.length) break;
  }

  hi.HighlightContinuation? continuation;
  var prefixLength = 0;
  var tailRuns = <List<String>>[];
  final committedRuns = <List<String>>[];
  final incrementalWatch = Stopwatch();
  var incrementalWorst = 0;
  final engine = hi.hljs;
  for (var end = chunkSize; ; end += chunkSize) {
    final stop = math.min(end, source.length);
    incrementalWatch.start();
    final watch = Stopwatch()..start();
    final completed = source.lastIndexOf('\n', stop - 1) + 1;
    if (completed > prefixLength) {
      final hi.HighlightResult result = engine.highlight(
        source.substring(prefixLength, completed),
        language: language,
        continuation: continuation,
      );
      if (result.errorRaised != null) throw result.errorRaised!;
      final runs = flatten(result);
      if (runText(runs) != source.substring(prefixLength, completed)) {
        throw StateError('$language continuation changed source');
      }
      committedRuns.addAll(runs);
      continuation = result.continuation;
      prefixLength = completed;
    }
    if (prefixLength < stop) {
      final hi.HighlightResult result = engine.highlight(
        source.substring(prefixLength, stop),
        language: language,
        continuation: continuation,
      );
      if (result.errorRaised != null) throw result.errorRaised!;
      tailRuns = flatten(result);
    } else {
      tailRuns = [];
    }
    watch.stop();
    incrementalWatch.stop();
    incrementalWorst = math.max(incrementalWorst, watch.elapsedMicroseconds);
    if (stop == source.length) break;
  }
  final actual = [...committedRuns, ...tailRuns];
  final expected = flatten(hi.hljs.highlight(source, language: language));
  return {
    'language': language,
    'utf16Units': source.length,
    'chunkSize': chunkSize,
    'appendCalls': calls,
    'fullTotalUs': fullWatch.elapsedMicroseconds,
    'fullWorstUs': fullWorst,
    'incrementalTotalUs': incrementalWatch.elapsedMicroseconds,
    'incrementalWorstUs': incrementalWorst,
    'speedup':
        fullWatch.elapsedMicroseconds /
        math.max(1, incrementalWatch.elapsedMicroseconds),
    'sourcePreserved': runText(actual) == source,
    'scopeDifferenceUnits': scopeDifferences(expected, actual),
  };
}
