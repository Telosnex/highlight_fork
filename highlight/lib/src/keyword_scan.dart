import 'dart:typed_data';

import 'first_set.dart';

/// Finds the words of a mode that can be keywords, without a regex call.
///
/// The keyword pattern of most modes is a run of units from one set, such as
/// `\w+`. A loop over the code units finds the same matches as the regex.
/// For most other patterns, such as `[a-z]\w+|__\w+__`, the automaton of
/// the pattern finds them. See [Prefix.matchEnd].
class KeywordScan {
  final RegExp _pattern;

  /// The units that can start a match.
  final Uint8List _start;

  /// For a pattern that is a run: the units of the run. Else null.
  final Uint8List? _run;

  /// For a pattern that is not a run.
  final Prefix? _automaton;

  /// The sets can match a unit outside ASCII. The loop does not know which,
  /// so the regex takes over at the first such unit.
  final bool _outsideAscii;

  // No keyword is shorter or longer, or starts with another ASCII unit.
  final int _minLength;
  final int _maxLength;
  final Uint8List _first;

  KeywordScan._(
    this._pattern,
    this._start,
    this._run,
    this._automaton,
    this._outsideAscii,
    this._minLength,
    this._maxLength,
    this._first,
  );

  /// Null when the loop cannot find the matches of [pattern].
  static KeywordScan? of(
    RegExp pattern,
    Iterable<String> keywords,
    bool caseInsensitive,
  ) {
    final set = FirstSet.of(
      pattern.pattern,
      caseSensitive: pattern.isCaseSensitive,
      unicode: pattern.isUnicode,
    );
    var start = set.runStart;
    var run = set.run;
    Prefix? automaton;
    if (!set.runOnly || start == null || run == null) {
      final prefix = set.prefix;
      if (prefix == null || !prefix.findsMatch) return null;
      automaton = prefix;
      start = set.buckets;
      run = null;
    }
    var minLength = 0x3fffffff;
    var maxLength = 0;
    final first = Uint8List(128);
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      if (keyword.length < minLength) minLength = keyword.length;
      if (keyword.length > maxLength) maxLength = keyword.length;
      final unit = keyword.codeUnitAt(0);
      if (unit >= 128) continue;
      first[unit] = 1;
      // The keys are in lower case; the text can have either case.
      if (caseInsensitive && unit >= 0x61 && unit <= 0x7a) {
        first[unit - 0x20] = 1;
      }
    }
    return KeywordScan._(
      pattern,
      start,
      run,
      automaton,
      start[FirstSet.nonAscii] != 0 ||
          run != null && run[FirstSet.nonAscii] != 0,
      minLength,
      maxLength,
      first,
    );
  }

  /// Calls [word] with the start and the end of each match of the pattern in
  /// [text], in order. With [onlyCandidates], it omits matches that cannot be
  /// a keyword.
  void forEachWord(
    String text,
    void Function(int start, int end) word, {
    bool onlyCandidates = true,
  }) {
    final start = _start;
    final run = _run;
    final automaton = _automaton;
    final length = text.length;
    var regexFrom = -1;
    var i = 0;
    scan:
    while (i < length) {
      final unit = text.codeUnitAt(i);
      if (unit >= 128) {
        if (_outsideAscii) {
          regexFrom = i;
          break;
        }
        i++;
        continue;
      }
      if (start[unit] == 0) {
        i++;
        continue;
      }
      var end = i + 1;
      if (run != null) {
        while (end < length) {
          final next = text.codeUnitAt(end);
          if (next >= 128) {
            if (_outsideAscii) {
              regexFrom = i;
              break scan;
            }
            break;
          }
          if (run[next] == 0) break;
          end++;
        }
      } else {
        end = automaton!.matchEnd(text, i);
        if (end == Prefix.unknown) {
          // The position is at an ASCII unit, so it is not in the middle
          // of a code point of a Unicode regex.
          end = _pattern.matchAsPrefix(text, i)?.end ?? -1;
        }
        if (end <= i) {
          i++;
          continue;
        }
      }
      final size = end - i;
      if (!onlyCandidates ||
          size >= _minLength && size <= _maxLength && _first[unit] != 0) {
        word(i, end);
      }
      i = end;
    }
    if (regexFrom < 0) return;
    for (final match in _pattern.allMatches(text, regexFrom)) {
      word(match.start, match.end);
    }
  }
}
