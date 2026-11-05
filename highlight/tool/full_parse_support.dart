// Browser-safe, opt-in single-full-parse benchmark. No timing assertions.
import 'dart:math' as math;

import 'package:highlight_fork/highlight.dart' as hi;

const fullParseSizesKb = [1, 2, 4, 8, 16, 20];

/// Cut at the last complete line at or below [units] UTF-16 code units.
String linePrefix(String source, int units) {
  final limit = math.min(units, source.length);
  final end = source.lastIndexOf('\n', limit - 1) + 1;
  if (end == 0) throw StateError('No complete line within $units units');
  return source.substring(0, end);
}

Map<String, Object> timingSummary(List<int> samples) {
  final sorted = [...samples]..sort();
  return {
    'iterations': sorted.length,
    'medianUs':
        (sorted[(sorted.length - 1) ~/ 2] + sorted[sorted.length ~/ 2]) / 2,
    // Nearest-rank p95: the 19th of 20 sorted observations.
    'p95Us': sorted[(sorted.length * .95).ceil() - 1],
    'maxUs': sorted.last,
  };
}

Iterable<Map<String, Object>> fullParseSizes(
  String language,
  String source, {
  String corpus = 'public-generated-v1',
}) sync* {
  for (final kb in fullParseSizesKb) {
    if (source.length < kb * 1024) continue;
    final text = linePrefix(source, kb * 1024);
    void parse() {
      final result = hi.hljs.highlight(text, language: language);
      if (result.errorRaised != null) throw result.errorRaised!;
    }

    for (var i = 0; i < 5; i++) {
      parse();
    }
    final samples = <int>[];
    for (var i = 0; i < 20; i++) {
      final watch = Stopwatch()..start();
      parse();
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
    }
    yield {
      'event': 'full-parse',
      'corpus': corpus,
      'language': language,
      'requestedKb': kb,
      'utf16Units': text.length,
      'warmups': 5,
      ...timingSummary(samples),
    };
  }
}
