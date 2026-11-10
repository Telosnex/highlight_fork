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

  /// The regex match. It is a match of the joined regex or of the regex of
  /// the rule; [groups] hides the difference.
  final RegExpMatch match;
  final String lexeme;
  final int _firstGroup;
  final int _groupCount;
  List<String?>? _groups;

  RuleMatch._(
    this.rule,
    this.match,
    this.lexeme,
    this._firstGroup,
    this._groupCount,
  );

  int get index => match.start;

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
  RegExp? matcherRe;
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
    if (_regexes.isEmpty) {
      matcherRe = null;
      return;
    }
    matcherRe = langRe(
      regex.rewriteBackreferences([
        for (final re in _regexes) re.pattern,
      ], joinWith: '|'),
      true,
    );
    _ruleStarts.add(matchAt);
    _testOrder = List<int>.generate(_rules.length, (i) => i);
    lastIndex = 0;
  }

  RuleMatch? exec(String s, [RuleMatchCache? cache]) {
    final re = matcherRe;
    if (re == null || lastIndex > s.length) return null;
    final from = lastIndex < 0 ? 0 : lastIndex;
    if (_calls == 64) {
      _calls = 32;
      _scanned >>= 1;
      _span >>= 1;
    }
    _calls++;
    if (from >= _lastFrom) _span += from - _lastFrom;
    _lastFrom = from;
    if (cache != null &&
        table != null &&
        _rules.length > 1 &&
        (debugRuleAtATime ??
            _scanned > _calls * _sparseUnits && _scanned * 2 > _span)) {
      return _execPerRule(s, from, cache);
    }

    final match = re.allMatches(s, from).firstOrNull;
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

  /// For tests: true or false makes every matcher use one way.
  static bool? debugRuleAtATime;
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

const _noMatch = 0x3fffffffffffffff;

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
    return regexes.length - 1;
  }();
}

/// The next match of each regex of a language in one source string. A parse
/// makes one. The next match of a rule does not depend on the mode that asks,
/// so all modes share the entries.
class RuleMatchCache {
  RegexTable? _table;
  List<int> _starts = const [];
  List<RegExpMatch?> _matches = const [];

  void _reset(RegexTable table) {
    _table = table;
    _starts = List<int>.filled(table.regexes.length, -1);
    _matches = List<RegExpMatch?>.filled(table.regexes.length, null);
  }
}

class ResumableMultiRegex {
  final List<(RegExp, MatchRule)> rules = [];
  final Map<int, MultiRegex> multiRegexes = {};
  int count = 0;
  int lastIndex = 0;
  int regexIndex = 0;
  final RegExp Function(String, bool) langRe;
  final RegexTable? table;

  ResumableMultiRegex(this.langRe, [this.table]);

  MultiRegex getMatcher(int index) {
    final existing = multiRegexes[index];
    if (existing != null) return existing;

    final matcher = MultiRegex(langRe, table);
    for (var i = index; i < rules.length; i++) {
      final (re, rule) = rules[i];
      matcher.addRule(re, rule);
    }
    matcher.compile();
    multiRegexes[index] = matcher;
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

    mode.keywordPatternRe = langRe(keywordPattern, true);

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
