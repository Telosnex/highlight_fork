import 'dart:typed_data';

/// Where a match of one regex can start.
///
/// A regex can match at a position only if the code unit at that position is
/// in [buckets], the next code unit is in [second], and the position meets
/// [requires]. The answer can be yes for a position where the regex does not
/// match: the sets are the upper limit.
class FirstSet {
  /// Buckets 0 to 127 are the ASCII code units. [nonAscii] is all other code
  /// units. [end] is the end of the source.
  static const nonAscii = 128;
  static const end = 129;
  static const bucketCount = 130;

  /// The match must start at a word boundary (`\b`).
  static const wordBoundary = 1;

  /// The match must start at the start of a line (`^`).
  static const lineStart = 2;

  final Uint8List buckets;

  /// The buckets of the code unit after the first one.
  ///
  /// With the Unicode flag, a part of the regex can match a surrogate pair,
  /// which is two units. Then [second] is correct only after a first unit
  /// that is not a surrogate.
  final Uint8List second;
  final int requires;

  /// For a regex that is one unit of [runStart], then a repeat of units of
  /// [run], then the rest: `[a-z]\w*(?=:)`. Else null. The index is an ASCII code unit.
  ///
  /// When such a regex fails at a unit of [runStart], it tried the rest at
  /// each position of the run. So it also fails at each position in the run.
  final Uint8List? runStart;
  final Uint8List? run;

  /// The regex is only the run: `\w+` or `[a-z]\w*`.
  final bool runOnly;

  /// The regex matches exactly this text and has no groups. Else null.
  final String? literal;

  /// The regex matches exactly one unit and has no groups. For an ASCII
  /// unit, [buckets] is exact. Else false.
  final bool single;

  FirstSet._(
    this.buckets,
    this.second,
    this.requires, [
    this.runStart,
    this.run,
    this.literal,
    this.single = false,
    this.runOnly = false,
  ]);

  /// A set that permits every position. It is correct for every regex.
  factory FirstSet.all() => FirstSet._(_all(), _everySecond, 0);

  /// The set for a JavaScript regex [source]. Syntax that the parser does not
  /// know gives [FirstSet.all].
  factory FirstSet.of(
    String source, {
    required bool caseSensitive,
    required bool unicode,
  }) {
    try {
      final parser = _Parser(source, !caseSensitive, unicode);
      final node = parser.parseAll();
      final buckets = Uint8List(bucketCount);
      for (var i = 0; i < bucketCount; i++) {
        buckets[i] = node.nonEmpty[i] | node.empty[i];
      }
      // With `iu`, `\b` uses a larger word set than the one tested here.
      final requires = !caseSensitive && unicode
          ? node.requires & ~wordBoundary
          : node.requires;
      // A match of fewer than two units says nothing about the next unit.
      final second = node.length1 || !_isEmptySet(node.empty)
          ? _everySecond
          : node.second;
      return FirstSet._(
        buckets,
        second,
        requires,
        parser.runStart,
        parser.run,
        caseSensitive ? _literal(source) : null,
        parser.single,
        parser.runOnly,
      );
    } on FormatException {
      return FirstSet.all();
    }
  }
}

/// The text of a regex that is only literal ASCII units, or null. A letter or
/// a digit after a backslash is not a literal.
String? _literal(String source) {
  if (source.isEmpty) return null;
  const meta = r'^$\.*+?()[]{}|';
  final text = StringBuffer();
  for (var i = 0; i < source.length; i++) {
    var c = source.codeUnitAt(i);
    if (c >= 128) return null;
    if (c == 0x5c /* \ */ ) {
      if (++i == source.length) return null;
      c = source.codeUnitAt(i);
      if (c >= 128 || isWordUnit(c)) return null;
    } else if (meta.contains(source[i])) {
      return null;
    }
    text.writeCharCode(c);
  }
  return text.toString();
}

/// The result for a part of a regex.
class _Node {
  /// The first code units of the matches that are not empty.
  final Uint8List nonEmpty;

  /// The code units before which an empty match is possible.
  final Uint8List empty;

  /// The second code units of the matches that have two or more.
  final Uint8List second;

  /// A match of one code unit is possible.
  final bool length1;

  /// The [FirstSet.requires] bits that every match meets at its start.
  final int requires;

  /// Every match is empty: the part is an assertion.
  final bool zeroWidth;

  _Node(
    this.nonEmpty,
    this.empty,
    this.requires,
    this.zeroWidth, {
    Uint8List? second,
    this.length1 = false,
  }) : second = second ?? _noUnits;
}

Uint8List _none() => Uint8List(FirstSet.bucketCount);
Uint8List _all() =>
    Uint8List(FirstSet.bucketCount)..fillRange(0, FirstSet.bucketCount, 1);

/// All buckets but the end: a consumed code unit cannot be the end.
Uint8List _allUnits() =>
    Uint8List(FirstSet.bucketCount)..fillRange(0, FirstSet.end, 1);

bool _isEmptySet(Uint8List set) {
  for (var i = 0; i < set.length; i++) {
    if (set[i] != 0) return false;
  }
  return true;
}

final _closed = _Node(_none(), _none(), 0, false);
final _noUnits = _none();
final _everySecond = _all();

class _Parser {
  final String src;
  final bool ignoreCase;
  final bool unicode;
  int i = 0;

  _Parser(this.src, this.ignoreCase, this.unicode);

  /// With `iu`, `s` and `k` each match a letter outside ASCII, and the
  /// reverse. Without `u`, a regex that ignores case does not mix an ASCII
  /// unit with a unit outside ASCII.
  bool get _foldsOutsideAscii => ignoreCase && unicode;

  Never _fail() => throw const FormatException();

  // The first two terms of the regex, when it has no alternatives.
  int _depth = 0;
  int _topTerms = 0;
  bool _topAlternatives = false;
  Uint8List? _unit0;
  Uint8List? _unit1;
  int _quantifier0 = 0;
  int _quantifier1 = 0;
  Uint8List? runStart;
  Uint8List? run;
  bool single = false;
  bool runOnly = false;

  /// One of the first two terms does not take the longest match.
  bool _lazy = false;

  _Node parseAll() {
    final node = _disjunction();
    if (i != src.length) _fail();
    const plus = 0x2b;
    const star = 0x2a;
    final unit0 = _unit0;
    final unit1 = _unit1;
    single =
        !_topAlternatives &&
        _topTerms == 1 &&
        unit0 != null &&
        _quantifier0 == 0;
    if (!_topAlternatives && unit0 != null) {
      if (_quantifier0 == plus) {
        runStart = run = unit0;
        runOnly = _topTerms == 1 && !_lazy;
      } else if (_quantifier0 == 0 &&
          unit1 != null &&
          (_quantifier1 == plus || _quantifier1 == star)) {
        runStart = unit0;
        run = unit1;
        runOnly = _topTerms == 2 && _quantifier1 == star && !_lazy;
      }
    }
    return node;
  }

  _Node _disjunction() {
    var node = _alternative();
    while (i < src.length && src.codeUnitAt(i) == 0x7c /* | */ ) {
      i++;
      if (_depth == 0) _topAlternatives = true;
      final other = _alternative();
      final nonEmpty = _none();
      final empty = _none();
      final second = _none();
      for (var b = 0; b < FirstSet.bucketCount; b++) {
        nonEmpty[b] = node.nonEmpty[b] | other.nonEmpty[b];
        empty[b] = node.empty[b] | other.empty[b];
        second[b] = node.second[b] | other.second[b];
      }
      node = _Node(
        nonEmpty,
        empty,
        node.requires & other.requires,
        node.zeroWidth && other.zeroWidth,
        second: second,
        length1: node.length1 || other.length1,
      );
    }
    return node;
  }

  _Node _alternative() {
    // The sequence so far: its first units, and where it can be empty.
    final nonEmpty = _none();
    var empty = _all();
    final second = _none();
    var canBeEmpty = true;
    var length1 = false;
    var requires = 0;
    var zeroWidth = true;
    // True when the sequence has two or more units: the rest adds nothing.
    var closed = false;
    while (i < src.length) {
      final c = src.codeUnitAt(i);
      if (c == 0x7c /* | */ || c == 0x29 /* ) */ ) break;
      final term = _term(closed);
      if (closed) continue;
      final termCanBeEmpty = !_isEmptySet(term.empty);
      final nextEmpty = _none();
      for (var b = 0; b < FirstSet.bucketCount; b++) {
        if (length1) second[b] |= term.nonEmpty[b];
        if (canBeEmpty) second[b] |= term.second[b];
        nonEmpty[b] |= empty[b] & term.nonEmpty[b];
        nextEmpty[b] = empty[b] & term.empty[b];
      }
      empty = nextEmpty;
      length1 = length1 && termCanBeEmpty || canBeEmpty && term.length1;
      canBeEmpty = canBeEmpty && termCanBeEmpty;
      if (zeroWidth) requires |= term.requires;
      zeroWidth = zeroWidth && term.zeroWidth;
      closed = !canBeEmpty && !length1;
    }
    return _Node(
      nonEmpty,
      empty,
      requires,
      zeroWidth,
      second: second,
      length1: length1,
    );
  }

  /// With [skip], the caller ignores the result: only the syntax is read.
  _Node _term(bool skip) {
    final top = _depth == 0;
    _loose = false;
    _unit = null;
    final atom = _atom(skip);
    // A set with too many units is not exact, and the run needs exact sets.
    final unit = _loose ? null : _unit;
    _lastQuantifier = 0;
    final term = _quantifier(atom);
    if (top) {
      if (_topTerms == 0) {
        _unit0 = unit;
        _quantifier0 = _lastQuantifier;
      } else if (_topTerms == 1) {
        _unit1 = unit;
        _quantifier1 = _lastQuantifier;
      }
      _topTerms++;
    }
    return term;
  }

  /// The ASCII units of the last atom, when it matches exactly one unit.
  Uint8List? _unit;
  int _lastQuantifier = 0;

  _Node _quantifier(_Node atom) {
    if (i >= src.length) return atom;
    final c = src.codeUnitAt(i);
    _lastQuantifier = c;
    int min;
    var repeats = true;
    if (c == 0x2a /* * */ ) {
      min = 0;
      i++;
    } else if (c == 0x3f /* ? */ ) {
      min = 0;
      repeats = false;
      i++;
    } else if (c == 0x2b /* + */ ) {
      min = 1;
      i++;
    } else if (c == 0x7b /* { */ ) {
      final parsed = _braces();
      if (parsed == null) {
        _lastQuantifier = 0;
        return atom;
      }
      min = parsed;
    } else {
      _lastQuantifier = 0;
      return atom;
    }
    if (i < src.length && src.codeUnitAt(i) == 0x3f /* ? */ ) {
      i++;
      if (_depth == 0 && _topTerms < 2) _lazy = true;
    }
    if (identical(atom, _closed)) return atom;
    // A second pass can start at the second unit.
    var second = atom.second;
    if (repeats && atom.length1) {
      second = _none();
      for (var b = 0; b < FirstSet.bucketCount; b++) {
        second[b] = atom.second[b] | atom.nonEmpty[b];
      }
    }
    return _Node(
      atom.nonEmpty,
      min > 0 ? atom.empty : _all(),
      min > 0 ? atom.requires : 0,
      atom.zeroWidth,
      second: second,
      length1: atom.length1,
    );
  }

  /// The minimum of a `{n}`, `{n,}` or `{n,m}` quantifier at [i], or null
  /// when the brace is a literal.
  int? _braces() {
    var j = i + 1;
    final digits = j;
    while (j < src.length && _isDigit(src.codeUnitAt(j))) {
      j++;
    }
    if (j == digits) return null;
    final min = int.parse(src.substring(digits, j));
    if (j < src.length && src.codeUnitAt(j) == 0x2c /* , */ ) {
      j++;
      while (j < src.length && _isDigit(src.codeUnitAt(j))) {
        j++;
      }
    }
    if (j >= src.length || src.codeUnitAt(j) != 0x7d /* } */ ) return null;
    i = j + 1;
    return min;
  }

  _Node _atom(bool skip) {
    final c = src.codeUnitAt(i);
    switch (c) {
      case 0x5e: // ^
        i++;
        return _Node(_none(), _all(), FirstSet.lineStart, true);
      case 0x24: // $
        i++;
        final empty = _none();
        empty[FirstSet.end] = 1;
        empty[0x0a] = 1;
        empty[0x0d] = 1;
        empty[FirstSet.nonAscii] = 1;
        return _Node(_none(), empty, 0, true);
      case 0x28: // (
        return _group();
      case 0x5b: // [
        return _units(_unit = _class());
      case 0x2e: // .
        i++;
        final set = _allUnits();
        set[0x0a] = 0;
        set[0x0d] = 0;
        _unit = set;
        return _Node(set, _none(), 0, false, length1: true);
      case 0x5c: // \
        return _escape();
      case 0x2a: // *
      case 0x2b: // +
      case 0x3f: // ?
      case 0x29: // )
        _fail();
      default:
        i++;
        // Only the first two terms of the regex need their sets after the
        // sequence is closed.
        if (skip && (_depth > 0 || _topTerms > 1)) return _closed;
        final set = _none();
        _addUnit(set, c);
        _unit = set;
        return _units(set);
    }
  }

  _Node _units(Uint8List set) {
    set[FirstSet.end] = 0;
    return _Node(set, _none(), 0, false, length1: true);
  }

  _Node _group() {
    i++; // (
    _depth++;
    var lookahead = false;
    var negative = false;
    var behind = false;
    if (i < src.length && src.codeUnitAt(i) == 0x3f /* ? */ ) {
      final next = i + 1 < src.length ? src.codeUnitAt(i + 1) : 0;
      if (next == 0x3a /* : */ ) {
        i += 2;
      } else if (next == 0x3d /* = */ ) {
        lookahead = true;
        i += 2;
      } else if (next == 0x21 /* ! */ ) {
        lookahead = negative = true;
        i += 2;
      } else if (next == 0x3c /* < */ ) {
        final after = i + 2 < src.length ? src.codeUnitAt(i + 2) : 0;
        if (after == 0x3d || after == 0x21) {
          behind = true;
          i += 3;
        } else {
          final close = src.indexOf('>', i);
          if (close < 0) _fail();
          i = close + 1;
        }
      } else {
        _fail();
      }
    }
    final inner = _disjunction();
    if (i >= src.length || src.codeUnitAt(i) != 0x29 /* ) */ ) _fail();
    i++;
    _depth--;
    // The inner atoms are not the atom of this term.
    _unit = null;
    if (behind || negative) return _Node(_none(), _all(), 0, true);
    if (lookahead) {
      // An empty match here needs a match of the inner part at the same
      // position.
      final empty = _none();
      for (var b = 0; b < FirstSet.bucketCount; b++) {
        empty[b] = inner.nonEmpty[b] | inner.empty[b];
      }
      return _Node(_none(), empty, inner.requires, true);
    }
    return inner;
  }

  _Node _escape() {
    i++; // \
    if (i >= src.length) _fail();
    final c = src.codeUnitAt(i);
    i++;
    switch (c) {
      case 0x62: // b
        return _Node(_none(), _all(), FirstSet.wordBoundary, true);
      case 0x42: // B
        return _Node(_none(), _all(), 0, true);
      case 0x6b: // k: a named backreference
        if (i < src.length && src.codeUnitAt(i) == 0x3c /* < */ ) {
          final close = src.indexOf('>', i);
          if (close < 0) _fail();
          i = close + 1;
          return _backreference();
        }
        final set = _none();
        _addUnit(set, 0x6b);
        return _units(set);
    }
    if (c >= 0x31 && c <= 0x39) {
      while (i < src.length && _isDigit(src.codeUnitAt(i))) {
        i++;
      }
      return _backreference();
    }
    final set = _none();
    _escapeUnits(c, set, inClass: false);
    _unit = set;
    return _units(set);
  }

  /// A backreference can match any text, or no text.
  _Node _backreference() =>
      _Node(_allUnits(), _all(), 0, false, second: _allUnits(), length1: true);

  /// Adds the units of the escape `\c` to [set]. [i] is after `c`.
  void _escapeUnits(int c, Uint8List set, {required bool inClass}) {
    switch (c) {
      case 0x64: // d
        for (var u = 0x30; u <= 0x39; u++) {
          set[u] = 1;
        }
      case 0x44: // D
        for (var u = 0; u <= FirstSet.nonAscii; u++) {
          if (!_isDigit(u)) set[u] = 1;
        }
      case 0x77: // w
        for (var u = 0; u < 128; u++) {
          if (isWordUnit(u)) set[u] = 1;
        }
        if (_foldsOutsideAscii) set[FirstSet.nonAscii] = 1;
      case 0x57: // W
        for (var u = 0; u <= FirstSet.nonAscii; u++) {
          if (!isWordUnit(u)) set[u] = 1;
        }
      case 0x73: // s
        for (final u in const [0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20]) {
          set[u] = 1;
        }
        set[FirstSet.nonAscii] = 1;
      case 0x53: // S
        for (var u = 0; u <= FirstSet.nonAscii; u++) {
          if (u > 0x20 || u < 0x09 || u > 0x0d && u < 0x20) set[u] = 1;
        }
      case 0x70: // p
      case 0x50: // P
        if (unicode) {
          final close = src.indexOf('}', i);
          if (close < 0) _fail();
          i = close + 1;
        }
        _loose = true;
        for (var u = 0; u <= FirstSet.nonAscii; u++) {
          set[u] = 1;
        }
      default:
        _addUnit(set, _escapeValue(c, inClass: inClass));
    }
  }

  /// The code unit or code point of the escape `\c`, which is not a set.
  int _escapeValue(int c, {required bool inClass}) {
    switch (c) {
      case 0x74: // t
        return 0x09;
      case 0x6e: // n
        return 0x0a;
      case 0x76: // v
        return 0x0b;
      case 0x66: // f
        return 0x0c;
      case 0x72: // r
        return 0x0d;
      case 0x62 when inClass: // b: backspace
        return 0x08;
      case 0x30: // 0
        if (i < src.length && _isDigit(src.codeUnitAt(i))) _fail();
        return 0;
      case 0x63: // c: a control letter
        if (i >= src.length) _fail();
        return src.codeUnitAt(i++) % 32;
      case 0x78: // x
        return _hex(2);
      case 0x75: // u
        if (i < src.length && src.codeUnitAt(i) == 0x7b /* { */ ) {
          final close = src.indexOf('}', i);
          if (close < 0) _fail();
          final value = int.tryParse(src.substring(i + 1, close), radix: 16);
          if (value == null) _fail();
          i = close + 1;
          return value;
        }
        return _hex(4);
      default:
        if (c >= 0x31 && c <= 0x39) _fail();
        return c;
    }
  }

  int _hex(int digits) {
    if (i + digits > src.length) _fail();
    final value = int.tryParse(src.substring(i, i + digits), radix: 16);
    if (value == null) _fail();
    i += digits;
    return value;
  }

  /// Adds the code unit or code point [u], and its other case when the regex
  /// ignores case.
  void _addUnit(Uint8List set, int u) {
    if (u >= 128) {
      set[FirstSet.nonAscii] = 1;
      // With `iu`, some letters outside ASCII match ASCII letters.
      if (_foldsOutsideAscii) _addLetters(set);
      return;
    }
    set[u] = 1;
    if (ignoreCase && _isLetter(u)) {
      set[u ^ 0x20] = 1;
      if (_foldsOutsideAscii) set[FirstSet.nonAscii] = 1;
    }
  }

  /// True when a set got more units than its regex part can match. The
  /// complement of such a set is not an upper limit.
  bool _loose = false;

  void _addLetters(Uint8List set) {
    _loose = true;
    for (var u = 0x41; u <= 0x5a; u++) {
      set[u] = 1;
      set[u | 0x20] = 1;
    }
  }

  /// A character class. [i] is at `[`.
  Uint8List _class() {
    i++; // [
    var negated = false;
    if (i < src.length && src.codeUnitAt(i) == 0x5e /* ^ */ ) {
      negated = true;
      i++;
    }
    final set = _none();
    while (true) {
      if (i >= src.length) _fail();
      if (src.codeUnitAt(i) == 0x5d /* ] */ ) break;
      final low = _classAtom(set);
      if (i + 1 < src.length &&
          src.codeUnitAt(i) == 0x2d /* - */ &&
          src.codeUnitAt(i + 1) != 0x5d) {
        i++;
        final high = _classAtom(set);
        // A class escape such as `\w` makes the hyphen a literal.
        if (low < 0 || high < 0) {
          set[0x2d] = 1;
          continue;
        }
        if (high < low) _fail();
        if (high >= 128) {
          set[FirstSet.nonAscii] = 1;
          if (_foldsOutsideAscii) _addLetters(set);
        }
        for (var u = low; u <= high && u < 128; u++) {
          _addUnit(set, u);
        }
      }
    }
    i++; // ]
    if (negated && _loose) return _allUnits();
    if (negated) {
      for (var u = 0; u < 128; u++) {
        set[u] ^= 1;
      }
      set[FirstSet.nonAscii] = 1;
    }
    return set;
  }

  /// Reads one class atom and adds it to [set]. Returns its code unit, or -1
  /// for an escape that is a set.
  int _classAtom(Uint8List set) {
    final c = src.codeUnitAt(i);
    i++;
    if (c != 0x5c /* \ */ ) {
      _addUnit(set, c);
      return c;
    }
    if (i >= src.length) _fail();
    final e = src.codeUnitAt(i);
    i++;
    const sets = [0x64, 0x44, 0x77, 0x57, 0x73, 0x53, 0x70, 0x50];
    if (sets.contains(e)) {
      _escapeUnits(e, set, inClass: true);
      return -1;
    }
    final value = _escapeValue(e, inClass: true);
    _addUnit(set, value);
    return value;
  }
}

bool _isDigit(int u) => u >= 0x30 && u <= 0x39;
bool _isLetter(int u) => (u | 0x20) >= 0x61 && (u | 0x20) <= 0x7a;

/// A unit of `\w`, without the `iu` additions.
bool isWordUnit(int u) => _isLetter(u) || _isDigit(u) || u == 0x5f;
