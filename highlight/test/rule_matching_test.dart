// The matcher finds the next rule in three ways. All must give the same
// tokens.
import 'dart:io';

import 'package:highlight_fork/highlight.dart' as hi;
import 'package:highlight_fork/languages/_all.dart';
import 'package:highlight_fork/src/mode_compiler.dart';
import 'package:test/test.dart';

import '../tool/eval_support.dart';
import 'integration/_vendor_fixtures.dart';
import 'perf/corpus.dart';

void main() {
  setUpAll(hi.ensureInitialized);
  tearDown(() => MultiRegex.debugStrategy = null);

  List<List<String>> parse(
    String language,
    String source,
    MatchStrategy strategy,
  ) {
    MultiRegex.debugStrategy = strategy;
    final result = hi.hljs.highlight(source, language: language);
    expect(result.errorRaised, isNull);
    return flatten(result);
  }

  final sources = {
    for (final entry in publicCorpus.entries)
      entry.key: sizedSource(entry.value, size: 2048),
    for (final entry in corpus.entries) '${entry.key} (perf)': entry.value,
    'json (long strings)': longStringJson(4096),
  };

  for (final MapEntry(key: name, value: source) in sources.entries) {
    test('all strategies agree: $name', () {
      final language = name.split(' ').first;
      final joined = parse(language, source, MatchStrategy.joined);
      expect(parse(language, source, MatchStrategy.ruleAtATime), joined);
      expect(parse(language, source, MatchStrategy.dispatch), joined);
    });
  }

  test('every default grammar agrees on sources of other languages', () {
    // Text that a grammar does not expect uses its illegal and fallback rules.
    final text = corpus.values.map((source) => sized(source, 1024)).join();
    for (final language in hi.hljs.listLanguages()) {
      final joined = parse(language, text, MatchStrategy.joined);
      for (final strategy in MatchStrategy.values) {
        expect(parse(language, text, strategy), joined, reason: language);
      }
    }
  });

  test('every grammar agrees on its sample and on other languages', () {
    final all = hi.Highlight();
    registerAllLanguages(all);
    // The last line has surrogate pairs and letters that fold to ASCII.
    final other =
        '${corpus.values.map((source) => sized(source, 512)).join()}\n'
        'x = "😀" + f\'😀{y}\' # 😀a 😀"b" é ſ \u212a\n';
    final samples = vendorFixtureDirectory('detect');
    for (final language in all.listLanguages()) {
      final sample = File('${samples.path}/$language/default.txt');
      final text = sample.existsSync()
          ? '${sample.readAsStringSync()}\n$other'
          : other;
      List<Object> run(MatchStrategy strategy) {
        MultiRegex.debugStrategy = strategy;
        return flatten(all.highlight(text, language: language));
      }

      final joined = run(MatchStrategy.joined);
      expect(run(MatchStrategy.dispatch), joined, reason: language);
    }
  });
}
