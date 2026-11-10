import 'dart:typed_data';

import 'first_set.dart';

/// Finds the words of a mode that can be keywords, without a regex call.
///
/// The keyword pattern of most modes is a run of units from one set, such as
/// `\w+`. A loop over the code units finds the same matches as the regex.
class KeywordScan {
  final RegExp _pattern;
  final Uint8List _start;
  final Uint8List _run;

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
    this._outsideAscii,
    this._minLength,
    this._maxLength,
    this._first,
  );

  /// Null when [pattern] is not a run.
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
    final start = set.runStart;
    final run = set.run;
    if (!set.runOnly || start == null || run == null) return null;
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
      start[FirstSet.nonAscii] != 0 || run[FirstSet.nonAscii] != 0,
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
