// A first set must permit every position where its regex matches.
import 'dart:io';
import 'dart:typed_data';

import 'package:highlight_fork/highlight_core.dart';
import 'package:highlight_fork/languages/_all.dart';
import 'package:highlight_fork/src/first_set.dart';
import 'package:test/test.dart';

import 'integration/_vendor_fixtures.dart';

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

/// Null when [set] permits a match at [pos], else the reason.
String? refusal(FirstSet set, String text, int pos, {bool unicode = false}) {
  final unit = pos < text.length ? text.codeUnitAt(pos) : -1;
  final bucket = unit < 0
      ? FirstSet.end
      : unit < 128
      ? unit
      : FirstSet.nonAscii;
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
}
