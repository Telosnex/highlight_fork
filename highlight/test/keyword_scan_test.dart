// The keyword scan must find the matches of the keyword pattern.
import 'dart:io';

import 'package:highlight_fork/highlight_core.dart';
import 'package:highlight_fork/languages/_all.dart';
import 'package:highlight_fork/src/keyword_scan.dart';
import 'package:test/test.dart';

import 'integration/_vendor_fixtures.dart';

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

void main() {
  const text = 'if x_1 then Else9 é fooé bar ſ K \u212a  a-b ?? \$y __z__';

  test('a run of one set', () {
    final pattern = RegExp(r'\w+', multiLine: true);
    final scan = KeywordScan.of(pattern, ['if', 'then'], false)!;
    expect(scanned(scan, text), matched(pattern, text));
  });

  test('a start set and a run', () {
    final pattern = RegExp(r'[a-zA-Z_$][\w$]*', multiLine: true);
    final scan = KeywordScan.of(pattern, ['if'], false)!;
    expect(scanned(scan, text), matched(pattern, text));
  });

  test('the regex takes over at a unit outside ASCII', () {
    final pattern = RegExp(
      r'[a-zа-яé]+',
      multiLine: true,
      caseSensitive: false,
    );
    final scan = KeywordScan.of(pattern, ['if'], true)!;
    expect(scanned(scan, text), matched(pattern, text));
    expect(scanned(scan, 'если if'), matched(pattern, 'если if'));
  });

  test('a pattern that is not a run has no scan', () {
    for (final source in [r'\w+?', r'\b\w+', r'[a-z]\w+', r'\w+|#', r'\w+!?']) {
      expect(KeywordScan.of(RegExp(source), ['if'], false), isNull);
    }
  });

  test('only words that can be keywords', () {
    final pattern = RegExp(r'\w+', multiLine: true);
    final scan = KeywordScan.of(pattern, ['if', 'then', 'Else9'], false)!;
    List<String> words(String text) => [
      for (final (start, end) in scanned(scan, text, all: false))
        text.substring(start, end),
    ];
    // By length and first unit only: `in` is not a keyword, but it passes.
    expect(words('if a x_1 then Else9 thenthen in other'), [
      'if',
      'then',
      'Else9',
      'in',
    ]);
    final folded = KeywordScan.of(RegExp(r'\w+', caseSensitive: false), [
      'if',
    ], true)!;
    expect(scanned(folded, 'IF If x', all: false), [(0, 2), (3, 5)]);
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
      final source = '$own\n$text';
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
