import 'dart:typed_data';

import 'first_set.dart';
import 'keyword_scan.dart';
import 'mode.dart';
import 'regex.dart' as regex;
import 'compiler_extensions.dart' as ext;
import 'before_match.dart';
import 'compile_keywords.dart';
import 'multi_class.dart';

enum MatchType { begin, end, illegal }

/// One rule of a mode: the start of a child mode, the end of the mode, or
/// illegal text.
class MatchRule {
  final MatchType type;

  /// The child mode, for [MatchType.begin].
  final Mode? mode;

  /// The index of the rule in the matcher that was built last. The matchers
  /// of a [ResumableMultiRegex] share their rules, as in highlight.js.
  int position = 0;

  MatchRule(this.type, [this.mode]);
}

/// A match of one rule in the source.
class RuleMatch {
  final MatchRule rule;
  final int index;
  final String lexeme;
  final int _firstGroup;
  final int _groupCount;
  List<String?>? _groups;
  RegExpMatch? _match;

  // For a match that was found without the regex: the regex and the source.
  final RegExp? _regex;
  final String? _source;

  RuleMatch._(
    this.rule,
    RegExpMatch match,
    this.lexeme,
    this._firstGroup,
    this._groupCount,
  ) : _match = match,
      index = match.start,
      _regex = null,
      _source = null;

  /// A match of a rule that has no capture groups.
  RuleMatch._known(
    this.rule,
    this.index,
    this.lexeme,
    RegExp this._regex,
    String this._source,
  ) : _firstGroup = 0,
      _groupCount = 0;

  /// The regex match. It is a match of the joined regex or of the regex of
  /// the rule; [groups] hides the difference.
  RegExpMatch get match =>
      _match ??= _regex!.matchAsPrefix(_source!, index)! as RegExpMatch;

  /// The lexeme, then the capture groups of the rule.
  List<String?> get groups => _groups ??= [
    lexeme,
    for (var g = 1; g <= _groupCount; g++) match.group(_firstGroup + g),
  ];
}

class MultiRegex {
  final List<MatchRule> _rules = [];
  final List<RegExp> _regexes = [];
  int matchAt = 1;
  RegExp? _matcherRe;
  bool _compiled = false;

  /// The regex of all rules, joined with `|`. Null when there are no rules.
  /// It is built on first use: a matcher that reads the source itself, see
  /// [_execDispatch], does not need it.
  RegExp? get matcherRe {
    if (!_compiled || _regexes.isEmpty) return null;
    return _matcherRe ??= langRe(
      regex.rewriteBackreferences([
        for (final re in _regexes) re.pattern,
      ], joinWith: '|'),
      true,
    );
  }

  int lastIndex = 0;
  final RegExp Function(String, bool) langRe;

  /// The capture group that wraps each rule, in rule order, then the group
  /// count plus one. Rule `n` owns the groups from `_ruleStarts[n]` up to,
  /// but not including, `_ruleStarts[n + 1]`.
  final List<int> _ruleStarts = [];
  List<int> _testOrder = const [];

  /// The id of each rule's regex in [table].
  final List<int> _ruleIds = [];
  final RegexTable? table;

  MultiRegex(this.langRe, [this.table]);

  void addRule(RegExp re, MatchRule rule) {
    _ruleIds.add(table?.idOf(re) ?? -1);
    rule.position = _rules.length;
    _rules.add(rule);
    _regexes.add(re);
    _ruleStarts.add(matchAt);
    matchAt += regex.countMatchGroups(re) + 1;
  }

  void compile() {
    _compiled = true;
    if (_regexes.isEmpty) return;
    _ruleStarts.add(matchAt);
    _testOrder = List<int>.generate(_rules.length, (i) => i);
    lastIndex = 0;
  }

  RuleMatch? exec(String s, [RuleMatchCache? cache]) {
    if (!_compiled || _regexes.isEmpty || lastIndex > s.length) return null;
    final from = lastIndex < 0 ? 0 : lastIndex;
    final table = this.table;
    final strategy = debugStrategy;
    if (table != null &&
        (strategy == null || strategy == MatchStrategy.dispatch)) {
      return _execDispatch(s, from, table, cache);
    }
    if (_calls == 64) {
      _calls = 32;
      _scanned >>= 1;
      _span >>= 1;
    }
    _calls++;
    if (from >= _lastFrom) _span += from - _lastFrom;
    _lastFrom = from;
    if (table != null &&
        cache != null &&
        _rules.length > 1 &&
        (strategy == null
            ? _scanned > _calls * _sparseUnits && _scanned * 2 > _span
            : strategy == MatchStrategy.ruleAtATime)) {
      return _execPerRule(s, from, cache);
    }

    final match = matcherRe!.allMatches(s, from).firstOrNull;
    _scanned += (match?.start ?? s.length) - from;
    if (match == null) return null;

    // Exactly one rule matched: the one whose wrapping group took part. That
    // group is the whole match. Test only the wrapping groups, not the groups
    // inside each rule. Each test is a call into the VM, so test the rules
    // that matched most often first: a hit moves its rule one place forward.
    final starts = _ruleStarts;
    final order = _testOrder;
    for (var i = 0; i < order.length; i++) {
      final rule = order[i];
      final first = starts[rule];
      final lexeme = match.group(first);
      if (lexeme != null) {
        if (i > 0) {
          order[i] = order[i - 1];
          order[i - 1] = rule;
        }
        return RuleMatch._(
          _rules[rule],
          match,
          lexeme,
          first,
          starts[rule + 1] - first - 1,
        );
      }
    }
    return null;
  }

  // The VM interprets a regex, and the joined regex tries every rule at
  // every position. Most rules can start with only a few code units. So read
  // the source here: at each position, try only the rules that can start
  // with the unit there, in rule order. The first rule that matches is the
  // match of the joined regex. Most positions have no such rule and cost one
  // table read.
  List<List<int>?>? _dispatch;
  List<int> _requires = const [];
  List<Uint8List> _seconds = const [];

  // The rules for a first bucket are fewer when the unit before and the
  // unit after are known. [_rows] has a row for each first bucket, which is
  // built on first use. Its index is `context * (_classCount + 1) + class`.
  // The context is one of the three below. The class is [_nextClass] of the
  // bucket of the next unit: two buckets are in one class when the second
  // sets of all rules agree on them. The class [_classCount] is for a next
  // unit that is not known.
  static const _afterWord = 0;
  static const _atLineStart = 1;
  static const _afterOther = 2;
  final List<List<List<int>?>?> _rows = List.filled(FirstSet.bucketCount, null);
  Uint8List _nextClass = Uint8List(0);
  final List<int> _classBuckets = [];
  int _classCount = 0;
  final _sharedLists = <String, List<int>>{};

  List<List<int>?> _buildRow(int bucket) {
    final rules = _dispatch![bucket]!;
    final unitIsWord = bucket < 128 && isWordUnit(bucket);
    final classes = _classCount + 1;
    final row = List<List<int>?>.filled(3 * classes, null);
    for (var context = 0; context < 3; context++) {
      for (var c = 0; c < classes; c++) {
        final list = <int>[];
        for (final rule in rules) {
          if (c < _classCount && _seconds[rule][_classBuckets[c]] == 0) {
            continue;
          }
          final needs = _requires[rule];
          if (needs & FirstSet.wordBoundary != 0 &&
              (context == _afterWord) == unitIsWord) {
            continue;
          }
          if (needs & FirstSet.lineStart != 0 && context != _atLineStart) {
            continue;
          }
          list.add(rule);
        }
        if (list.isEmpty) continue;
        row[context * classes + c] = _sharedLists[list.join(',')] ??= list;
      }
    }
    return _rows[bucket] = row;
  }

  List<Uint8List?> _runStarts = const [];
  List<Uint8List?> _runs = const [];
  List<Prefix?> _prefixes = const [];

  // Rules whose match needs no regex call.
  static const _always = 1;
  static const _single = 2;
  static const _literal = 3;
  List<int> _kinds = const [];
  List<String?> _literals = const [];
  bool _unicode = false;

  void _buildDispatch(RegexTable table) {
    final sets = [for (final id in _ruleIds) table.firstSet(id)];
    _requires = [for (final set in sets) set.requires];
    _seconds = [for (final set in sets) set.second];
    _runStarts = [for (final set in sets) set.runStart];
    _runs = [for (final set in sets) set.run];
    _prefixes = [for (final set in sets) set.prefix];
    _literals = [for (final set in sets) set.literal];
    _kinds = [
      for (var r = 0; r < sets.length; r++)
        // The begin or the end of a mode that has none.
        if (_regexes[r].pattern == r'\B|\b')
          _always
        else if (sets[r].literal != null)
          _literal
        else if (sets[r].single)
          _single
        else
          0,
    ];
    _unicode = _regexes.any((re) => re.isUnicode);
    final shared = _sharedLists;
    _dispatch = List<List<int>?>.generate(FirstSet.bucketCount, (bucket) {
      final rules = [
        for (var r = 0; r < sets.length; r++)
          if (sets[r].buckets[bucket] != 0) r,
      ];
      if (rules.isEmpty) return null;
      return shared[rules.join(',')] ??= rules;
    });
    // Each distinct second set is one bit of the signature of a bucket.
    final distinct = Set<Uint8List>.identity()..addAll(_seconds);
    final classOf = <String, int>{};
    _nextClass = Uint8List(FirstSet.bucketCount);
    for (var bucket = 0; bucket < FirstSet.bucketCount; bucket++) {
      final signature = [for (final set in distinct) set[bucket]].join();
      _nextClass[bucket] = classOf[signature] ??= () {
        _classBuckets.add(bucket);
        return _classBuckets.length - 1;
      }();
    }
    _classCount = _classBuckets.length;
  }

  RuleMatch? _execDispatch(
    String s,
    int from,
    RegexTable table,
    RuleMatchCache? cache,
  ) {
    if (_dispatch == null) _buildDispatch(table);
    if (cache != null && !identical(cache._runTable, table)) {
      cache._resetRuns(table);
    }
    final failFrom = cache?._failFrom;
    final failUntil = cache?._failUntil;
    final ids = _ruleIds;
    final runStarts = _runStarts;
    final runs = _runs;
    final kinds = _kinds;
    final prefixes = _prefixes;
    final dispatch = _dispatch!;
    final allRows = _rows;
    final nextClass = _nextClass;
    final classes = _classCount + 1;
    final contexts = _contexts;
    final regexes = _regexes;
    final length = s.length;
    var unit = from > 0 ? s.codeUnitAt(from - 1) : -1;
    for (var pos = from; pos <= length; pos++) {
      final before = unit;
      int bucket;
      if (pos < length) {
        unit = s.codeUnitAt(pos);
        bucket = unit < 128 ? unit : FirstSet.nonAscii;
      } else {
        unit = -1;
        bucket = FirstSet.end;
      }
      if (dispatch[bucket] == null) continue;
      var known = true;
      if (unit >= 128 && _unicode) {
        // A Unicode regex does not start a match inside a surrogate pair.
        if (pos > from &&
            unit & 0xfc00 == 0xdc00 &&
            before & 0xfc00 == 0xd800) {
          continue;
        }
        // See [FirstSet.second].
        if (unit & 0xf800 == 0xd800) known = false;
      }
      var column = classes - 1;
      if (known) {
        final next = pos + 1 < length ? s.codeUnitAt(pos + 1) : -1;
        column =
            nextClass[next < 0
                ? FirstSet.end
                : next < 128
                ? next
                : FirstSet.nonAscii];
      }
      final context = before < 0
          ? _atLineStart
          : before < 128
          ? contexts[before]
          : before == 0x2028 || before == 0x2029
          ? _atLineStart
          : _afterOther;
      final rules =
          (allRows[bucket] ?? _buildRow(bucket))[context * classes + column];
      if (rules == null) continue;
      for (var i = 0; i < rules.length; i++) {
        final rule = rules[i];
        final kind = kinds[rule];
        if (kind != 0) {
          String? lexeme;
          if (kind == _always) {
            lexeme = '';
          } else if (kind == _literal) {
            final literal = _literals[rule]!;
            if (!s.startsWith(literal, pos)) continue;
            lexeme = literal;
          } else if (unit >= 0 && unit < 128) {
            lexeme = s[pos];
          }
          if (lexeme != null) {
            return RuleMatch._known(
              _rules[rule],
              pos,
              lexeme,
              regexes[rule],
              s,
            );
          }
        }
        final runStart = runStarts[rule];
        if (runStart != null && failUntil != null) {
          final id = ids[rule];
          if (pos < failUntil[id] && pos >= failFrom![id]) continue;
        }
        final prefix = prefixes[rule];
        final match = prefix != null && prefix.rejects(s, pos)
            ? null
            : regexes[rule].matchAsPrefix(s, pos) as RegExpMatch?;
        if (match != null) {
          return RuleMatch._(
            _rules[rule],
            match,
            match.group(0)!,
            0,
            _ruleStarts[rule + 1] - _ruleStarts[rule] - 1,
          );
        }
        // See [FirstSet.run]: the rule fails in the rest of the run too.
        if (runStart != null &&
            failUntil != null &&
            unit < 128 &&
            runStart[unit] != 0) {
          final run = runs[rule]!;
          var end = pos + 1;
          while (end < length) {
            final u = s.codeUnitAt(end);
            if (u >= 128 || run[u] == 0) break;
            end++;
          }
          final id = ids[rule];
          failFrom![id] = pos;
          failUntil[id] = end;
        }
      }
    }
    return null;
  }

  // The joined regex is slow for each unit that it scans, because it tries
  // every rule at every position. One regex for each rule scans faster, and
  // [RuleMatchCache] keeps the match of a rule until the parse passes it. But
  // a rule alone also searches text that a child mode would consume, and that
  // search can cost more than it saves. So use the rules one at a time only
  // while this mode scans far for each match (more than [_sparseUnits] units)
  // and scans most of the text that the parse passes between its calls.
  //
  // The counts are a moving average. They continue from one parse to the
  // next, which lets a line-by-line parse use them. Both ways give the same
  // match, so the counts change only the speed.
  static const _sparseUnits = 24;

  /// For tests: makes every matcher use one way.
  static MatchStrategy? debugStrategy;
  int _calls = 0;
  int _scanned = 0;
  int _span = 0;
  int _lastFrom = 0;

  /// The leftmost match of any rule at or after [from]; the first rule wins
  /// at equal positions. This is what the joined regex gives.
  RuleMatch? _execPerRule(String s, int from, RuleMatchCache cache) {
    final table = this.table!;
    if (!identical(cache._table, table)) cache._reset(table);
    final starts = cache._starts;
    final matches = cache._matches;
    final ids = _ruleIds;
    var best = -1;
    var bestId = -1;
    var bestStart = _noMatch;
    for (var r = 0; r < ids.length; r++) {
      final id = ids[r];
      var start = starts[id];
      if (start < from) {
        final match = table.regexes[id].allMatches(s, from).firstOrNull;
        matches[id] = match;
        start = starts[id] = match?.start ?? _noMatch;
      }
      if (start < bestStart) {
        best = r;
        bestId = id;
        bestStart = start;
        // No later rule can win against a match at the scan position.
        if (start == from) break;
      }
    }
    _scanned += (best < 0 ? s.length : bestStart) - from;
    if (best < 0) return null;
    final match = matches[bestId]!;
    return RuleMatch._(
      _rules[best],
      match,
      match.group(0)!,
      0,
      _ruleStarts[best + 1] - _ruleStarts[best] - 1,
    );
  }
}

/// For each ASCII unit, the context of the position after it.
final Uint8List _contexts = () {
  final contexts = Uint8List(128)..fillRange(0, 128, MultiRegex._afterOther);
  for (var unit = 0; unit < 128; unit++) {
    if (isWordUnit(unit)) contexts[unit] = MultiRegex._afterWord;
  }
  contexts[0x0a] = contexts[0x0d] = MultiRegex._atLineStart;
  return contexts;
}();

// Above every string index, and exact as a JavaScript number.
const _noMatch = 0x1fffffffffffff;

/// How a [MultiRegex] finds the next match. All ways give the same match.
enum MatchStrategy { joined, ruleAtATime, dispatch }

/// The distinct regexes of one compiled language. Equal sources share one
/// [RegExp], so a rule that is in many modes has one id.
class RegexTable {
  final List<RegExp> regexes = [];
  final _bySource = <String, RegExp>{};
  final _ids = Map<RegExp, int>.identity();

  RegExp intern(String source, RegExp Function() create) =>
      _bySource[source] ??= create();

  int idOf(RegExp re) => _ids[re] ??= () {
    regexes.add(re);
    _firstSets.add(null);
    return regexes.length - 1;
  }();

  final List<FirstSet?> _firstSets = [];

  FirstSet firstSet(int id) {
    final re = regexes[id];
    return _firstSets[id] ??= FirstSet.of(
      re.pattern,
      caseSensitive: re.isCaseSensitive,
      unicode: re.isUnicode,
    );
  }
}

/// The next match of each regex of a language in one source string. A parse
/// makes one. The next match of a rule does not depend on the mode that asks,
/// so all modes share the entries.
class RuleMatchCache {
  RegexTable? _table;
  List<int> _starts = const [];
  List<RegExpMatch?> _matches = const [];

  // A regex with a [FirstSet.run] fails at each position from [_failFrom]
  // up to, but not including, [_failUntil].
  RegexTable? _runTable;
  List<int> _failFrom = const [];
  List<int> _failUntil = const [];

  void _resetRuns(RegexTable table) {
    _runTable = table;
    _failFrom = List<int>.filled(table.regexes.length, 0);
    _failUntil = List<int>.filled(table.regexes.length, 0);
  }

  void _reset(RegexTable table) {
    _table = table;
    _starts = List<int>.filled(table.regexes.length, -1);
    _matches = List<RegExpMatch?>.filled(table.regexes.length, null);
  }
}

class ResumableMultiRegex {
  final List<(RegExp, MatchRule)> rules = [];
  // The matcher that starts at each rule index.
  final List<MultiRegex?> _matchers = [];
  int count = 0;
  int lastIndex = 0;
  int regexIndex = 0;
  final RegExp Function(String, bool) langRe;
  final RegexTable? table;

  ResumableMultiRegex(this.langRe, [this.table]);

  MultiRegex getMatcher(int index) {
    final matchers = _matchers;
    if (index < matchers.length) {
      final existing = matchers[index];
      if (existing != null) return existing;
    }

    final matcher = MultiRegex(langRe, table);
    for (var i = index; i < rules.length; i++) {
      final (re, rule) = rules[i];
      matcher.addRule(re, rule);
    }
    matcher.compile();
    while (matchers.length <= index) {
      matchers.add(null);
    }
    matchers[index] = matcher;
    return matcher;
  }

  bool resumingScanAtSamePosition() {
    return regexIndex != 0;
  }

  void considerAll() {
    regexIndex = 0;
  }

  void addRule(RegExp re, MatchRule rule) {
    // Give the id now. Matchers are built on first use, after a parse has
    // sized its cache.
    table?.idOf(re);
    rules.add((re, rule));
    if (rule.type == MatchType.begin) count++;
  }

  RuleMatch? exec(String s, [RuleMatchCache? cache]) {
    final m = getMatcher(regexIndex);
    m.lastIndex = lastIndex;
    var result = m.exec(s, cache);

    if (resumingScanAtSamePosition()) {
      if (result != null && result.index == lastIndex) {
        // valid resume
      } else {
        final m2 = getMatcher(0);
        m2.lastIndex = lastIndex + 1;
        result = m2.exec(s, cache);
      }
    }

    if (result != null) {
      regexIndex += result.rule.position + 1;
      if (regexIndex == count) {
        considerAll();
      }
    }

    return result;
  }
}

ResumableMultiRegex buildModeRegex(
  Mode mode,
  RegExp Function(String, bool) langRe, [
  RegexTable? table,
]) {
  final mm = ResumableMultiRegex(langRe, table);

  final contains = mode.contains ?? [];
  for (final term in contains) {
    if (term is Mode) {
      final beginRe = term.beginRe;
      if (beginRe != null) {
        mm.addRule(beginRe, MatchRule(MatchType.begin, term));
      }
    }
  }

  final terminatorEnd = mode.terminatorEnd;
  if (terminatorEnd != null && terminatorEnd.isNotEmpty) {
    mm.addRule(langRe(terminatorEnd, false), MatchRule(MatchType.end));
  }
  final illegalRe = mode.illegalRe;
  if (illegalRe != null) {
    mm.addRule(illegalRe, MatchRule(MatchType.illegal));
  }

  return mm;
}

bool _dependencyOnParent(Mode? mode) {
  if (mode == null) return false;
  return mode.endsWithParent == true || _dependencyOnParent(mode.starts);
}

dynamic _expandOrCloneMode(Mode mode) {
  if (mode.variants != null && mode.cachedVariants == null) {
    mode.cachedVariants = mode.variants!.map((variant) {
      return mode.copyWith(clearVariants: true).mergeWith(variant);
    }).toList();
  }

  if (mode.cachedVariants != null) {
    return mode.cachedVariants!;
  }

  if (_dependencyOnParent(mode)) {
    return mode.copyWith();
  }

  return mode;
}

Mode compileLanguage(Mode language) {
  final table = RegexTable();
  RegExp langRe(String value, bool global) {
    final caseInsensitive = language.caseInsensitive == true;
    final unicodeRegex = language.unicodeRegex == true;
    return table.intern(
      value,
      () => RegExp(
        value,
        multiLine: true,
        caseSensitive: !caseInsensitive,
        unicode: unicodeRegex,
      ),
    );
  }

  Mode compileMode(Mode mode, Mode? parent) {
    if (mode.isCompiled) return mode;

    ext.scopeClassName(mode, parent);
    ext.compileMatch(mode, parent);
    multiClass(mode);
    beforeMatchExt(mode, parent);

    final compilerExtensions = language.compilerExtensions ?? [];
    for (final e in compilerExtensions) {
      if (e is Function) {
        (e as void Function(Mode, Mode?))(mode, parent);
      }
    }

    final extensions2 = <void Function(Mode, Mode?)>[
      ext.beginKeywords,
      ext.compileIllegal,
      ext.compileRelevance,
    ];
    for (final e in extensions2) {
      e(mode, parent);
    }

    mode.isCompiled = true;

    String? keywordPattern;
    final keywords = mode.keywords;
    if (keywords is Map && keywords.containsKey(r'$pattern')) {
      final kwMap = Map<String, dynamic>.from(keywords);
      keywordPattern = regex.source(kwMap.remove(r'$pattern'));
      mode.keywords = kwMap;
    }
    keywordPattern ??= r'\w+';

    if (mode.keywords != null) {
      mode.compiledKeywords = compileKeywords(
        mode.keywords,
        language.caseInsensitive == true,
      );
    }

    final keywordPatternRe = langRe(keywordPattern, true);
    mode.keywordPatternRe = keywordPatternRe;
    final compiledKeywords = mode.compiledKeywords;
    if (compiledKeywords != null) {
      mode.keywordScan = KeywordScan.of(
        keywordPatternRe,
        compiledKeywords.keys,
        language.caseInsensitive == true,
      );
    }

    if (parent != null) {
      mode.begin ??= r'\B|\b';
      mode.beginRe = langRe(regex.source(mode.begin) ?? r'\B|\b', false);
      final endSource = regex.source(mode.end);
      final hasEnd =
          endSource != null && endSource.isNotEmpty && mode.end != false;
      if (!hasEnd && mode.endsWithParent != true) {
        mode.end = r'\B|\b';
      }
      if (mode.end != null && mode.end != false) {
        mode.endRe = langRe(regex.source(mode.end)!, false);
      }
      mode.terminatorEnd = regex.source(mode.end) ?? '';
      if (mode.endsWithParent == true &&
          parent.terminatorEnd != null &&
          parent.terminatorEnd!.isNotEmpty) {
        mode.terminatorEnd = mode.terminatorEnd!.isNotEmpty
            ? '${mode.terminatorEnd}|${parent.terminatorEnd}'
            : parent.terminatorEnd;
      }
    }
    if (mode.illegal != null) {
      mode.illegalRe = langRe(regex.source(mode.illegal)!, false);
    }
    mode.contains ??= <dynamic>[];

    final expandedContains = <dynamic>[];

    void addExpandedContains(dynamic entry) {
      if (entry is List) {
        for (final nested in entry) {
          addExpandedContains(nested);
        }
        return;
      }

      final target = entry == 'self' ? mode : (entry as Mode);
      final expanded = _expandOrCloneMode(target);
      if (expanded is List) {
        expandedContains.addAll(expanded);
      } else {
        expandedContains.add(expanded);
      }
    }

    for (final c in mode.contains!) {
      addExpandedContains(c);
    }
    mode.contains = expandedContains;

    for (final c in mode.contains!) {
      if (c is Mode) {
        compileMode(c, mode);
      }
    }

    if (mode.starts != null) {
      compileMode(mode.starts!, parent);
    }

    mode.matcher = buildModeRegex(mode, langRe, table);
    return mode;
  }

  language.compilerExtensions ??= <dynamic>[];

  if (language.contains != null && language.contains!.contains('self')) {
    throw StateError(
      'ERR: contains `self` is not supported at the top-level of a language.',
    );
  }

  language.classNameAliases = Map<String, String>.from(
    language.classNameAliases ?? {},
  );

  return compileMode(language, null);
}
