// A first set must permit every position where its regex matches.
import 'dart:typed_data';

import 'package:highlight_fork/src/first_set.dart';
import 'package:test/test.dart';

List<int> buckets(
  String source, {
  bool caseSensitive = true,
  bool unicode = false,
}) {
  final set = FirstSet.of(
    source,
    caseSensitive: caseSensitive,
    unicode: unicode,
  );
  return [
    for (var b = 0; b < FirstSet.bucketCount; b++)
      if (set.buckets[b] != 0) b,
  ];
}

List<int> second(String source) {
  final set = FirstSet.of(source, caseSensitive: true, unicode: false);
  return [
    for (var b = 0; b < FirstSet.bucketCount; b++)
      if (set.second[b] != 0) b,
  ];
}

int requires(String source) =>
    FirstSet.of(source, caseSensitive: true, unicode: false).requires;

void main() {
  final all = [for (var u = 0; u < FirstSet.bucketCount; u++) u];
  List<int> units(String chars) => chars.codeUnits.toList()..sort();

  test('literals, classes and escapes', () {
    expect(buckets('abc'), units('a'));
    expect(buckets('[a-c]x'), units('abc'));
    expect(buckets(r'\d+'), units('0123456789'));
    expect(buckets(r'\.'), units('.'));
    expect(buckets(r'[\]\-x]'), units(']-x'));
    expect(buckets(r'\x41|\u0042|\t'), units('\tAB'));
    expect(buckets('é'), [FirstSet.nonAscii]);
    expect(
      buckets('[^a]'),
      [...all]..removeWhere((b) => b == 0x61 || b == 129),
    );
  });

  test('a part that can be empty passes to the next part', () {
    expect(buckets('a*b'), units('ab'));
    expect(buckets('a?b+c'), units('ab'));
    expect(buckets('(?:a|b{0,2})c'), units('abc'));
    expect(buckets('a{2}b'), units('a'));
    expect(buckets('a*'), all);
    expect(buckets(r'\B|\b'), all);
  });

  test('groups and alternatives', () {
    expect(buckets('(a|b)|(?<n>c)|(?:d)'), units('abcd'));
    expect(buckets('ab|cd'), units('ac'));
  });

  test('assertions', () {
    expect(buckets('(?=a|b)'), units('ab'));
    expect(buckets(r'(?=[ab])\w+'), units('ab'));
    expect(buckets(r'(?!a)[a-c]'), units('abc'));
    expect(buckets(r'(?<=x)a'), units('a'));
    // With no `a`, the position needs both `b` and `c`.
    expect(buckets(r'a*(?=b)c'), units('a'));
    expect(buckets(r'a*(?=b)[bc]'), units('ab'));
    expect(buckets(r'$'), [0x0a, 0x0d, FirstSet.nonAscii, FirstSet.end]);
    expect(requires(r'\bfoo'), FirstSet.wordBoundary);
    expect(requires(r'^\s*#'), FirstSet.lineStart);
    expect(requires(r'(?=\bfoo)f'), FirstSet.wordBoundary);
    expect(requires(r'\bfoo|bar'), 0);
    expect(requires(r'(?:\bfoo)?bar'), 0);
    expect(requires(r'a\b'), 0);
  });

  test('the second unit', () {
    expect(second('abc'), units('b'));
    expect(second('.?css`'), units('cs'));
    expect(second('a?b?cd'), units('bcd'));
    expect(second('a+b'), units('ab'));
    expect(second('(?:ab)+c'), units('b'));
    expect(second(r'\bfo|x(?=y)z'), units('oz'));
    expect(second('[ab][cd]|ef'), units('cdf'));
    // A match of one unit or of no unit does not limit the next unit.
    expect(second('a'), all);
    expect(second('ab?'), all);
    expect(second('a*'), all);
    expect(second(r'(.)\1x'), [...all]..remove(FirstSet.end));
  });

  test('a run', () {
    FirstSet of(String source) =>
        FirstSet.of(source, caseSensitive: true, unicode: false);
    List<int> ascii(Uint8List? set) => [
      for (var u = 0; u < 128; u++)
        if (set![u] != 0) u,
    ];
    final name = of(r'[a-c]\d*(?=:)');
    expect(ascii(name.runStart), units('abc'));
    expect(ascii(name.run), units('0123456789'));
    final word = of('[ab]+:');
    expect(ascii(word.runStart), units('ab'));
    expect(ascii(word.run), units('ab'));
    for (final source in [
      r'\b[a-c]\d*:', // An assertion first: the start is not the run.
      r'([a-c])\d*:', // A group can be the target of a backreference.
      r'[a-c]\d*:|x',
      r'[a-c]?\d*:',
      r'[a-c]\d?:',
      r'[a-c]:',
    ]) {
      expect(of(source).runStart, isNull, reason: source);
    }
  });

  test('a regex that needs no regex call', () {
    FirstSet of(String source, {bool caseSensitive = true}) =>
        FirstSet.of(source, caseSensitive: caseSensitive, unicode: false);
    expect(of('"""').literal, '"""');
    expect(of(r'\$\{').literal, r'${');
    expect(of('=>').literal, '=>');
    for (final source in ['a+', 'a|b', r'\d', r'\n', '(a)', 'é', '[a]', '.']) {
      expect(of(source).literal, isNull, reason: source);
    }
    expect(of('ab', caseSensitive: false).literal, isNull);

    expect(of('[{}]').single, isTrue);
    expect(of(r'\d').single, isTrue);
    expect(of('[a]', caseSensitive: false).single, isTrue);
    for (final source in ['[ab]+', '[ab]c', '([ab])', '[ab]|c', r'\b']) {
      expect(of(source).single, isFalse, reason: source);
    }
  });

  test('case', () {
    expect(buckets('a', caseSensitive: false), units('Aa'));
    // With `iu`, `k` also matches the Kelvin sign.
    expect(buckets('k', caseSensitive: false, unicode: true), [
      ...units('Kk'),
      FirstSet.nonAscii,
    ]);
    expect(
      buckets('[^a]', caseSensitive: false),
      [...all]..removeWhere((b) => b == 0x41 || b == 0x61 || b == 129),
    );
  });

  test('the complement of a class that has too many units is every unit', () {
    final units = [...all]..remove(FirstSet.end);
    // With `iu`, a letter outside ASCII can match an ASCII letter, and the
    // set does not know which.
    expect(buckets('[^é]', caseSensitive: false, unicode: true), units);
    expect(buckets('[^é=]', caseSensitive: false), [...units]..remove(0x3d));
  });

  test('backreferences and unknown syntax permit every position', () {
    expect(buckets(r'(a)|\1'), all);
    expect(buckets('(?i:a)'), all);
    expect(buckets('a)'), all);
  });
}
