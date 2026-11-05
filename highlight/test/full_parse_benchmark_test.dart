// Opt in: dart test test/full_parse_benchmark_test.dart --run-skipped
// Add --platform chrome --compiler dart2js (or dart2wasm) for browser runs.
import 'dart:convert';

import 'package:highlight_fork/highlight.dart' as hi;
import 'package:test/test.dart';

import '../tool/eval_support.dart';
import '../tool/full_parse_support.dart';

void main() {
  test('full parse sizes (metrics only)', () {
    hi.ensureInitialized();
    for (final entry in publicCorpus.entries) {
      for (final metrics in fullParseSizes(
        entry.key,
        sizedSource(entry.value),
      )) {
        print(jsonEncode(metrics));
      }
    }
  }, skip: !const bool.fromEnvironment('FULL_PARSE_SIZES'));
}
