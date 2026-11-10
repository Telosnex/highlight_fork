// Checks of the matcher on every grammar, with the samples of highlight.js.
@TestOn('vm')
library;

import 'dart:io';

import 'package:highlight_fork/highlight_core.dart';
import 'package:highlight_fork/languages/_all.dart';
import 'package:highlight_fork/src/first_set.dart';
import 'package:highlight_fork/src/keyword_scan.dart';
import 'package:highlight_fork/src/mode_compiler.dart';
import 'package:test/test.dart';

import '../../tool/eval_support.dart';
import '../perf/corpus.dart';
import '_vendor_fixtures.dart';

/// Null when [set] permits a match at [pos], else the reason.
String? refusal(FirstSet set, String text, int pos, {bool unicode = false}) {
  final unit = pos < text.length ? text.codeUnitAt(pos) : -1;
  final bucket = unit < 0
      ? FirstSet.end
      : unit < 128
      ? unit
      : FirstSet.nonAscii;
  if (set.prefix?.rejects(text, pos) ?? false) return 'prefix';
  if (set.buckets[bucket] == 0) return 'bucket $bucket';
  final next = pos + 1 < text.length ? text.codeUnitAt(pos + 1) : -1;
  final nextBucket = next < 0
      ? FirstSet.end
      : next < 128
      ? next
      : FirstSet.nonAscii;
  final surrogate = unicode && unit & 0xf800 == 0xd800;
  if (set.second[nextBucket] == 0 && !surrogate) {
    return 'second bucket $nextBucket';
  }
  final before = pos > 0 ? text.codeUnitAt(pos - 1) : -1;
  bool word(int u) => u >= 0 && u < 128 && isWordUnit(u);
  if (set.requires & FirstSet.wordBoundary != 0 && word(before) == word(unit)) {
    return 'word boundary';
  }
  if (set.requires & FirstSet.lineStart != 0 &&
      !(before < 0 ||
          before == 0x0a ||
          before == 0x0d ||
          before == 0x2028 ||
          before == 0x2029)) {
    return 'line start';
  }
  return null;
}

List<(int, int)> scanned(KeywordScan scan, String text, {bool all = true}) {
  final words = <(int, int)>[];
  scan.forEachWord(
    text,
    (start, end) => words.add((start, end)),
    onlyCandidates: !all,
  );
  return words;
}

List<(int, int)> matched(RegExp pattern, String text) => [
  for (final match in pattern.allMatches(text)) (match.start, match.end),
];

const keywordText = 'if x_1 then Else9 é fooé bar ſ K \u212a  a-b ?? \$y __z__';

void main() {
  tearDown(() => MultiRegex.debugStrategy = null);

  test('every grammar agrees on its sample and on other languages', () {
    final all = Highlight();
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

  test('each rule of each grammar matches only where its set permits', () {
    final hljs = Highlight();
    registerAllLanguages(hljs);
    final samples = vendorFixtureDirectory('detect');
    const symbols =
        'a_1 Z9\t"x" \'y\' `z` é\u2028ß ſs \u212ak İiı 😀x😀"😀\' {[(<>)]} #!/\$%^&*-+=|\\:;,.?~@ \r\n'
        '  - 0x1F 1.5e3\n';
    var regexes = 0;
    var runs = 0;
    var known = 0;
    for (final name in hljs.listLanguages()) {
      final language = hljs.getLanguage(name)!;
      // The first parse compiles the grammar.
      hljs.highlight('x', language: name);
      final sample = File('${samples.path}/$name/default.txt');
      final own = sample.existsSync() ? sample.readAsStringSync() : '';
      final text =
          '${own.length > 300 ? own.substring(0, 300) : own}\n$symbols';
      final table = language.matcher!.table!;
      for (var id = 0; id < table.regexes.length; id++) {
        final re = table.regexes[id];
        final set = table.firstSet(id);
        regexes++;
        final runStart = set.runStart;
        if (runStart != null) {
          runs++;
          for (var pos = 0; pos < text.length; pos++) {
            final unit = text.codeUnitAt(pos);
            if (unit >= 128 || runStart[unit] == 0) continue;
            if (re.matchAsPrefix(text, pos) != null) continue;
            for (var next = pos + 1; next < text.length; next++) {
              final u = text.codeUnitAt(next);
              if (u >= 128 || set.run![u] == 0) break;
              if (re.matchAsPrefix(text, next) != null) {
                fail('$name: /${re.pattern}/ fails at $pos, matches at $next');
              }
            }
          }
        }
        final literal = set.literal;
        if (literal != null || set.single) {
          known++;
          for (var pos = 0; pos < text.length; pos++) {
            final unit = text.codeUnitAt(pos);
            if (literal == null && unit >= 128) continue;
            final expected = literal != null
                ? (text.startsWith(literal, pos) ? literal : null)
                : (set.buckets[unit] != 0 ? text[pos] : null);
            final match = re.matchAsPrefix(text, pos);
            if (match?.group(0) != expected || (match?.groupCount ?? 0) != 0) {
              fail('$name: /${re.pattern}/ at $pos is not "$expected"');
            }
          }
        }
        for (var pos = 0; pos <= text.length; pos++) {
          final refused = refusal(set, text, pos, unicode: re.isUnicode);
          if (refused != null && re.matchAsPrefix(text, pos) != null) {
            fail('$name: /${re.pattern}/ matches at $pos, set: $refused');
          }
        }
      }
    }
    expect(regexes, greaterThan(4000));
    expect(runs, greaterThan(100));
    expect(known, greaterThan(500));
  });

  test('each keyword pattern of each grammar', () {
    final hljs = Highlight();
    registerAllLanguages(hljs);
    final samples = vendorFixtureDirectory('detect');
    var scans = 0;
    for (final name in hljs.listLanguages()) {
      hljs.highlight('x', language: name);
      final sample = File('${samples.path}/$name/default.txt');
      final own = sample.existsSync() ? sample.readAsStringSync() : '';
      final source = '$own\n$keywordText';
      final seen = Set<Mode>.identity();
      void check(Mode mode) {
        if (!seen.add(mode)) return;
        final scan = mode.keywordScan;
        if (scan != null) {
          scans++;
          expect(
            scanned(scan, source),
            matched(mode.keywordPatternRe!, source),
            reason: '$name: ${mode.keywordPatternRe!.pattern}',
          );
        }
        for (final child in mode.contains ?? const <dynamic>[]) {
          if (child is Mode) check(child);
        }
        final starts = mode.starts;
        if (starts != null) check(starts);
      }

      check(hljs.getLanguage(name)!);
    }
    expect(scans, greaterThan(300));
  });
}
