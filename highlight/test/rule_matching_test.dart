// The matcher finds the next rule in two ways and picks one by how the mode
// scans. Both ways must give the same tokens.
import 'package:highlight_fork/highlight.dart' as hi;
import 'package:highlight_fork/src/mode_compiler.dart';
import 'package:test/test.dart';

import '../tool/eval_support.dart';
import 'perf/corpus.dart';

void main() {
  setUpAll(hi.ensureInitialized);
  tearDown(() => MultiRegex.debugRuleAtATime = null);

  List<List<String>> parse(String language, String source, bool ruleAtATime) {
    MultiRegex.debugRuleAtATime = ruleAtATime;
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
    test('joined regex and rule regexes agree: $name', () {
      final language = name.split(' ').first;
      expect(parse(language, source, true), parse(language, source, false));
    });
  }

  test('every default grammar agrees on sources of other languages', () {
    // Text that a grammar does not expect uses its illegal and fallback rules.
    final text = corpus.values.map((source) => sized(source, 1024)).join();
    for (final language in hi.hljs.listLanguages()) {
      expect(
        parse(language, text, true),
        parse(language, text, false),
        reason: language,
      );
    }
  });
}
