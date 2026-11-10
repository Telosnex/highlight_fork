// A first set must permit every position where its regex matches.
import 'dart:io';

import 'package:highlight_fork/highlight_core.dart';
import 'package:highlight_fork/languages/_all.dart';
import 'package:highlight_fork/src/first_set.dart';
import 'package:test/test.dart';

import 'integration/_vendor_fixtures.dart';

List<int> buckets(String source, {bool caseSensitive = true}) {
  final set = FirstSet.of(source, caseSensitive: caseSensitive, unicode: false);
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
String? refusal(FirstSet set, String text, int pos) {
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
  if (set.second[nextBucket] == 0) return 'second bucket $nextBucket';
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

  test('case', () {
    expect(buckets('a', caseSensitive: false), [
      ...units('Aa'),
      FirstSet.nonAscii,
    ]);
    expect(
      buckets('[^a]', caseSensitive: false),
      [...all]..removeWhere((b) => b == 0x41 || b == 0x61 || b == 129),
    );
  });

  test('the complement of a class that has too many units is every unit', () {
    final units = [...all]..remove(FirstSet.end);
    expect(buckets('[^\\u2401=]', caseSensitive: false), units);
    expect(buckets('[^é]', caseSensitive: false), units);
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
        'a_1 Z9\t"x" \'y\' `z` é\u2028ß {[(<>)]} #!/\$%^&*-+=|\\:;,.?~@ \r\n'
        '  - 0x1F 1.5e3\n';
    var regexes = 0;
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
        for (var pos = 0; pos <= text.length; pos++) {
          final refused = refusal(set, text, pos);
          if (refused != null && re.matchAsPrefix(text, pos) != null) {
            fail('$name: /${re.pattern}/ matches at $pos, set: $refused');
          }
        }
      }
    }
    expect(regexes, greaterThan(4000));
  });
}
