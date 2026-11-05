// Browser-safe performance probe over generated, non-private 20 KB sources.
// Native: dart test test/stream_benchmark_test.dart
// JS: dart test test/stream_benchmark_test.dart --platform chrome --compiler dart2js
// Wasm: dart test test/stream_benchmark_test.dart --platform chrome --compiler dart2wasm
// Optional compile-time controlled-device budget: STREAM_MAX_WORST_US=1000
import 'dart:convert';

import 'package:highlight_fork/highlight.dart' as hi;
import 'package:test/test.dart';

import '../tool/eval_support.dart';

void main() {
  hi.ensureInitialized();
  for (final entry in publicCorpus.entries) {
    test('20KB streaming ${entry.key}', () {
      final metrics = streamBenchmark(entry.key, sizedSource(entry.value));
      print(jsonEncode(metrics));
      expect(metrics['sourcePreserved'], isTrue);
      // YAML's block-scalar lookahead cannot be reproduced by immutable
      // completed lines. Keep that known limitation visible in the regression
      // fixture instead of promising arbitrary chunk/full scope equivalence.
      expect(metrics['scopeDifferenceUnits'], entry.key == 'yaml' ? 325 : 0);
      const budget = int.fromEnvironment('STREAM_MAX_WORST_US');
      if (budget > 0) {
        expect(metrics['incrementalWorstUs'] as int, lessThanOrEqualTo(budget));
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
