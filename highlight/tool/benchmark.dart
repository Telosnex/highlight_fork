// Browser-safe (no dart:io). Run natively, compile js, or compile wasm.
// dart run tool/benchmark.dart
// dart compile js tool/benchmark.dart -O2 -o build/benchmark.js
// dart compile wasm tool/benchmark.dart -o build/benchmark.wasm
// Run generated artifacts in a browser and collect console JSON lines.
import 'dart:convert';

import 'package:highlight_fork/highlight.dart' as hi;

import 'eval_support.dart';
import 'full_parse_support.dart';

void main(List<String> args) {
  hi.ensureInitialized();
  if (args.contains('--full-parse-sizes') ||
      const bool.fromEnvironment('FULL_PARSE_SIZES')) {
    for (final entry in publicCorpus.entries) {
      for (final metrics in fullParseSizes(
        entry.key,
        sizedSource(entry.value),
      )) {
        print(jsonEncode(metrics));
      }
    }
    return;
  }
  print(
    jsonEncode({'event': 'benchmark-start', 'corpus': 'public-generated-v1'}),
  );
  for (final entry in publicCorpus.entries) {
    try {
      print(jsonEncode(streamBenchmark(entry.key, sizedSource(entry.value))));
    } catch (error, stack) {
      print(
        jsonEncode({
          'language': entry.key,
          'error': '$error',
          'stack': '$stack',
        }),
      );
      rethrow;
    }
  }
  print(jsonEncode({'event': 'benchmark-complete'}));
}
