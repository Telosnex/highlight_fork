// The keyword scan must find the matches of the keyword pattern.
import 'dart:math';

import 'package:highlight_fork/src/keyword_scan.dart';
import 'package:test/test.dart';

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

  test('a pattern that the loop cannot follow has no scan', () {
    for (final source in [
      r'\w+?',
      r'\b\w+',
      r'\w*',
      r'(?=a)\w+',
      r'(\w)\1',
      r'x(|a)',
      r'\w{2,}',
      r'\w+(?!\()',
    ]) {
      expect(KeywordScan.of(RegExp(source), ['if'], false), isNull);
    }
  });

  test('a pattern that is not a run', () {
    const texts = [
      text,
      'if __init__ _x __a__b__ a ab abc abcc x? y?? a-b-c -a a- @x @@y #id',
      'xa xab ab.cd .ab a.b. __ ___ ____ _____ a__ __a',
      'é __é__ aé 😀ab ab😀 a😀b __a😀__ ſ \u212a aſ a\u212ab IF If',
    ];
    for (final source in [
      r'[A-Za-z]\w+|__\w+__',
      r'[A-Za-z][A-Za-z0-9_]*\??',
      r'[a-z]\w+',
      r'\w+|#',
      r'\w+!?',
      r'-?\w+',
      r'@?\w+',
      r'[a-z]+(-[a-z]+)*',
      r'\.?\w+',
      r'[a-z_][a-z0-9_.]*',
      r'(a|ab)c?',
      r'(ab|a)c?',
      r'a?ab',
      r'x(a|)',
      r'(a|b)+c|a+',
      r'if|then|[A-Z]\w*',
    ]) {
      for (final unicode in [false, true]) {
        for (final caseSensitive in [true, false]) {
          final pattern = RegExp(
            source,
            multiLine: true,
            unicode: unicode,
            caseSensitive: caseSensitive,
          );
          final scan = KeywordScan.of(pattern, ['if'], !caseSensitive);
          expect(scan, isNotNull, reason: source);
          for (final text in texts) {
            expect(
              scanned(scan!, text),
              matched(pattern, text),
              reason: '$source unicode=$unicode case=$caseSensitive "$text"',
            );
          }
        }
      }
    }
  });

  test('random patterns', () {
    final random = Random(20240607);
    const atoms = ['a', 'b', 'c', '_', '[ab]', '[^a]', r'\w', '.'];
    const quantifiers = ['', '', '', '?', '*', '+'];
    String pattern(int depth) {
      final alternatives = <String>[];
      for (var a = random.nextInt(3) + 1; a > 0; a--) {
        final terms = StringBuffer();
        for (var t = random.nextInt(3) + (depth == 0 ? 1 : 0); t > 0; t--) {
          final atom = depth < 2 && random.nextInt(4) == 0
              ? '(${pattern(depth + 1)})'
              : atoms[random.nextInt(atoms.length)];
          terms.write(atom);
          terms.write(quantifiers[random.nextInt(quantifiers.length)]);
        }
        alternatives.add(terms.toString());
      }
      return alternatives.join('|');
    }

    var scans = 0;
    for (var n = 0; n < 4000; n++) {
      final source = pattern(0);
      final re = RegExp(source, multiLine: true);
      final scan = KeywordScan.of(re, ['a'], false);
      if (scan == null) continue;
      scans++;
      for (var t = 0; t < 4; t++) {
        final text = String.fromCharCodes([
          for (var k = random.nextInt(14); k > 0; k--)
            'aabbc_ \n'.codeUnitAt(random.nextInt(8)),
        ]);
        expect(
          scanned(scan, text),
          matched(re, text),
          reason: '/$source/ on ${text.codeUnits}',
        );
      }
    }
    expect(scans, greaterThan(1000));
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
}
