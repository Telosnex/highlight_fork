// ignore_for_file: non_constant_identifier_names

import 'mode.dart';
import 'token_tree.dart';
import 'regex.dart' as regex;
import 'utils.dart';
import 'mode_compiler.dart';

typedef LanguageDefinitionFn = Mode Function(Highlight hljs);

const _maxKeywordHits = 7;

/// An opaque, reusable parser checkpoint produced by [Highlight.highlight].
///
/// A checkpoint belongs to one engine and one registered language definition.
/// It retains open modes, callback data and named embedded-language states.
/// Resuming does not mutate the checkpoint, so callers can reparse a changing
/// tail from a stable prefix. Checkpoints are in-memory only, not serializable.
///
/// This is parser-state continuation, not an arbitrary streaming lexer: splitting
/// a token, delimiter, escape, or a grammar's lookahead can change highlighting.
/// Prefer complete-line boundaries and keep a reparsable tail. Even line
/// boundaries cannot guarantee equivalence for grammars with multiline lookahead.
class HighlightContinuation {
  final Highlight _owner;
  final Mode _language;
  final Mode _top;
  final Map<String, HighlightContinuation> _sublanguages;
  final Map<String, int> _keywordHits;

  HighlightContinuation._(
    this._owner,
    this._language,
    Mode top,
    Map<String, HighlightContinuation> sublanguages,
    Map<String, int> keywordHits,
  ) : _top = _copyModeStack(top),
      _sublanguages = Map.unmodifiable(sublanguages),
      _keywordHits = Map.unmodifiable(keywordHits);
}

// Callback state is usually scalar, but grammar authors can use nested standard
// collections. Copy those as well, so resuming a checkpoint cannot mutate it.
// Custom mutable objects in callback data remain the grammar author's concern.
dynamic _copyCallbackValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value.map((key, value) => MapEntry(key, _copyCallbackValue(value)));
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key, _copyCallbackValue(value)));
  }
  if (value is List) return value.map(_copyCallbackValue).toList();
  if (value is Set) return value.map(_copyCallbackValue).toSet();
  return value;
}

Mode _copyModeStack(Mode mode) {
  final copy = mode.shallowCopy()
    ..modeId = mode.modeId
    ..data = mode.data == null
        ? null
        : _copyCallbackValue(mode.data) as Map<String, dynamic>;
  if (mode.parent != null) copy.parent = _copyModeStack(mode.parent!);
  return copy;
}

class HighlightResult {
  String? _value;
  final String language;
  num relevance;
  final TokenTreeEmitter emitter;
  bool illegal;

  /// Legacy access to the active mode. Use [continuation] for resuming parses.
  Mode? top;

  /// Reusable state for the next chunk; null when parsing failed.
  final HighlightContinuation? continuation;
  HighlightResult? secondBest;
  String? code;
  dynamic errorRaised;
  Map<String, dynamic>? illegalBy;

  HighlightResult({
    required this.language,
    required this.relevance,
    required this.emitter,
    this.illegal = false,
    this.top,
    this.continuation,
    this.secondBest,
    this.code,
    this.errorRaised,
    this.illegalBy,
    String? value,
  }) : _value = value;

  String get value {
    _value ??= emitter.toHTML();
    return _value!;
  }

  String toHtml() => value;
}

// ignore: deprecated_implement
class _CallbackRegExpMatch implements RegExpMatch {
  final RegExpMatch _inner;
  final List<String?> _groups;

  _CallbackRegExpMatch(this._inner, this._groups);

  @override
  RegExp get pattern => _inner.pattern;

  @override
  String get input => _inner.input;

  @override
  int get start => _inner.start;

  @override
  int get end => _inner.end;

  @override
  int get groupCount => _groups.isEmpty ? 0 : _groups.length - 1;

  @override
  String? group(int group) {
    if (group == 0) {
      return _groups.isNotEmpty ? _groups[0] : _inner.group(0);
    }
    if (group < 0 || group >= _groups.length) return null;
    return _groups[group];
  }

  @override
  String? operator [](int group) => this.group(group);

  @override
  List<String?> groups(List<int> groupIndices) {
    return groupIndices.map(group).toList();
  }

  @override
  Iterable<String> get groupNames => const [];

  @override
  String? namedGroup(String name) => null;
}

class Highlight {
  final Map<String, Mode> _languages = {};
  final Map<String, String> _aliases = {};
  final bool _safeMode = true;

  void registerLanguage(String name, LanguageDefinitionFn definition) {
    Mode lang;
    try {
      lang = definition(this);
    } catch (error) {
      if (!_safeMode) rethrow;
      lang = Mode(
        disableAutodetect: true,
        name: 'Plain text',
        contains: <dynamic>[],
      );
    }
    lang.name ??= name;
    _languages[name] = lang;
    lang.rawDefinition = definition;

    final aliases = lang.aliases;
    if (aliases != null) {
      registerAliases(aliases, languageName: name);
    }
  }

  void unregisterLanguage(String name) {
    _languages.remove(name);
    _aliases.removeWhere((_, v) => v == name);
  }

  List<String> listLanguages() => _languages.keys.toList();

  bool hasLanguage(String name) => getLanguage(name) != null;

  Mode? getLanguage(String name) {
    name = name.toLowerCase();
    return _languages[name] ?? _languages[_aliases[name]];
  }

  void registerAliases(List<String> aliasList, {required String languageName}) {
    for (final alias in aliasList) {
      _aliases[alias.toLowerCase()] = languageName;
    }
  }

  bool autoDetection(String name) {
    final lang = getLanguage(name);
    return lang != null && lang.disableAutodetect != true;
  }

  /// Highlights a source chunk, optionally resuming an earlier checkpoint.
  ///
  /// See [HighlightContinuation] for boundary limitations. A checkpoint from a
  /// different engine, language, or replaced language definition is rejected.
  HighlightResult highlight(
    String code, {
    required String language,
    HighlightContinuation? continuation,
  }) {
    if (continuation != null &&
        (!identical(continuation._owner, this) ||
            !identical(continuation._language, getLanguage(language)))) {
      throw ArgumentError('Continuation belongs to another engine or language');
    }
    final result = _highlight(language, code, true, continuation);
    result.code = code;
    return result;
  }

  HighlightResult _highlight(
    String languageName,
    String codeToHighlight,
    bool ignoreIllegals, [
    HighlightContinuation? continuation,
  ]) {
    final keywordHits = <String, int>{...?continuation?._keywordHits};

    // The match that a callback gets: the rule's own regex, matched in place,
    // so that input, start and end are those of the source.
    RegExpMatch callbackMatch(RegExp? re, RuleMatch match) {
      final direct = re?.matchAsPrefix(codeToHighlight, match.index);
      if (direct != null) return direct as RegExpMatch;
      return _CallbackRegExpMatch(match.match, match.groups);
    }

    final language = getLanguage(languageName);
    if (language == null) {
      throw ArgumentError('Unknown language: "$languageName"');
    }

    final md = _ensureCompiled(language);
    final options = <String, dynamic>{'classPrefix': 'hljs-'};
    var top = continuation == null
        ? (md.shallowCopy()..modeId = 0)
        : _copyModeStack(continuation._top);
    final continuations = <String, HighlightContinuation>{
      ...?continuation?._sublanguages,
    };
    final emitter = TokenTreeEmitter(options);
    final modeBuffer = StringBuffer();
    num relevance = 0;
    var index = 0;
    var iterations = 0;
    var resumeScanAtSamePosition = false;
    var modeIdCounter = 0;
    for (Mode? active = top; active != null; active = active.parent) {
      final id = active.modeId ?? 0;
      if (id > modeIdCounter) modeIdCounter = id;
    }

    late void Function() processBuffer;
    late void Function() processKeywords;

    void emitKeyword(String keyword, String scope) {
      if (keyword.isEmpty) return;
      emitter.startScope(scope);
      emitter.addText(keyword);
      emitter.endScope();
    }

    void emitMultiClass(Map<dynamic, dynamic> scope, RuleMatch match) {
      var i = 1;
      final groups = match.groups;
      final emit = scope['_emit'] as Map<int, bool>? ?? {};
      final max = groups.length - 1;

      while (i <= max) {
        if (emit[i] != true) {
          i++;
          continue;
        }
        final klass = _classNameAlias(language, scope[i] as String?);
        String? text;
        if (i < groups.length) {
          text = groups[i];
        }
        if (text == null || text.isEmpty) {
          i++;
          continue;
        }
        if (klass != null && klass.isNotEmpty) {
          emitKeyword(text, klass);
        } else {
          modeBuffer
            ..clear()
            ..write(text);
          processKeywords();
          modeBuffer.clear();
        }
        i++;
      }
    }

    processKeywords = () {
      if (modeBuffer.isEmpty) return;
      final text = modeBuffer.toString();
      final keywords = top.compiledKeywords;
      final keywordPatternRe = top.keywordPatternRe;
      if (keywords == null || keywordPatternRe == null) {
        emitter.addText(text);
        return;
      }

      // Text from [plainStart] up to the current word has no scope.
      var plainStart = 0;
      final caseInsensitive = language.caseInsensitive == true;

      void onWord(int start, int end) {
        final matched = text.substring(start, end);
        final word = caseInsensitive ? matched.toLowerCase() : matched;
        final data = keywords[word];
        if (data == null) return;
        final kind = data[0] as String;
        final keywordRelevance = data[1] as num;
        emitter.addText(text.substring(plainStart, start));
        plainStart = start;

        final hits = (keywordHits[word] ?? 0) + 1;
        keywordHits[word] = hits;
        if (hits <= _maxKeywordHits) {
          relevance += keywordRelevance;
        }
        if (!kind.startsWith('_')) {
          final cssClass = _classNameAlias(language, kind) ?? kind;
          emitKeyword(matched, cssClass);
          plainStart = end;
        }
      }

      final scan = top.keywordScan;
      if (scan != null) {
        scan.forEachWord(text, onWord);
      } else {
        for (final match in keywordPatternRe.allMatches(text)) {
          onWord(match.start, match.end);
        }
      }
      emitter.addText(plainStart == 0 ? text : text.substring(plainStart));
    };

    void processSubLanguage() {
      if (modeBuffer.isEmpty) return;
      final text = modeBuffer.toString();

      HighlightResult result;

      final subLang = top.subLanguage;
      if (subLang is String) {
        if (_languages[subLang] == null) {
          emitter.addText(text);
          return;
        }
        result = _highlight(subLang, text, true, continuations[subLang]);
        final next = result.continuation;
        if (next != null) continuations[subLang] = next;
      } else {
        final subset = subLang is List && subLang.isNotEmpty
            ? subLang.cast<String>()
            : null;
        result = highlightAuto(text, languageSubset: subset);
      }

      if ((top.relevance ?? 0) > 0) {
        relevance += result.relevance;
      }
      emitter.addSublanguage(result.emitter, result.language);
    }

    processBuffer = () {
      if (top.subLanguage != null) {
        processSubLanguage();
      } else {
        processKeywords();
      }
      modeBuffer.clear();
    };

    // [mode] is a rule of the grammar, which many parses share, so the open
    // mode is a copy. With [owned], the caller made that copy already.
    Mode startNewMode(Mode mode, RuleMatch match, {bool owned = false}) {
      final scope = mode.scope;
      if (mode.skip != true && scope is String && scope.isNotEmpty) {
        emitter.openNode(_classNameAlias(language, scope) ?? scope);
      }
      final beginScope = mode.beginScope;
      if (mode.skip != true && beginScope is Map) {
        if (beginScope['_wrap'] != null) {
          final wrap =
              _classNameAlias(language, beginScope['_wrap'] as String?) ??
              beginScope['_wrap'] as String;
          emitKeyword(modeBuffer.toString(), wrap);
          modeBuffer.clear();
        } else if (beginScope['_multi'] == true) {
          emitMultiClass(beginScope, match);
          modeBuffer.clear();
        }
      }

      top = (owned ? mode : mode.shallowCopy())
        ..parent = top
        ..modeId = ++modeIdCounter;
      return top;
    }

    Mode? endOfMode(Mode mode, int matchIndex) {
      // Match in place. A substring of the remaining source here made every
      // end match copy the rest of the document.
      final matched =
          mode.endRe?.matchAsPrefix(codeToHighlight, matchIndex)
              as RegExpMatch?;

      if (matched != null) {
        final onEnd = mode.onEnd;
        if (onEnd != null) {
          mode.data ??= {};
          final resp = CallbackResponse(mode.data!);
          onEnd(matched, resp);
          if (resp.isMatchIgnored) return null;
        }

        while (mode.endsParent == true && mode.parent != null) {
          mode = mode.parent!;
        }
        return mode;
      }
      if (mode.endsWithParent == true) {
        return endOfMode(mode.parent!, matchIndex);
      }
      return null;
    }

    int doIgnore(String lexeme) {
      final matcher = top.matcher;
      if (matcher != null && matcher.regexIndex == 0) {
        if (lexeme.isNotEmpty) modeBuffer.write(lexeme[0]);
        return 1;
      } else {
        resumeScanAtSamePosition = true;
        return 0;
      }
    }

    int doBeginMatch(RuleMatch match) {
      final lexeme = match.lexeme;
      // Callback data is local to this mode invocation, never the shared rule.
      final newMode = match.rule.mode!.shallowCopy();

      // Most rules have no callback. Build the callback match, its response
      // and the data map only for the rules that have one.
      final beforeBegin = newMode.beforeBeginCallback;
      final onBegin = newMode.onBegin;
      if (beforeBegin != null || onBegin != null) {
        final beginMatch = callbackMatch(newMode.beginRe, match);
        final resp = CallbackResponse(newMode.data ??= {});
        for (final cb in [beforeBegin, onBegin]) {
          if (cb == null) continue;
          (cb as Function)(beginMatch, resp);
          if (resp.isMatchIgnored) return doIgnore(lexeme);
        }
      }

      if (newMode.skip == true) {
        modeBuffer.write(lexeme);
      } else {
        if (newMode.excludeBegin == true) {
          modeBuffer.write(lexeme);
        }
        processBuffer();
        if (newMode.returnBegin != true && newMode.excludeBegin != true) {
          modeBuffer.write(lexeme);
        }
      }
      startNewMode(newMode, match, owned: true);
      return newMode.returnBegin == true ? 0 : lexeme.length;
    }

    final noMatch = Object();

    dynamic doEndMatch(RuleMatch match) {
      final lexeme = match.lexeme;
      final matchIndex = match.index;
      final endMode = endOfMode(top, matchIndex);
      if (endMode == null) return noMatch;

      final origin = top;

      final endScope = top.endScope;
      if (endScope is Map && endScope['_wrap'] != null) {
        processBuffer();
        final wrap =
            _classNameAlias(language, endScope['_wrap'] as String?) ??
            endScope['_wrap'] as String;
        emitKeyword(lexeme, wrap);
      } else if (endScope is Map && endScope['_multi'] == true) {
        processBuffer();
        emitMultiClass(endScope, match);
      } else if (origin.skip == true) {
        modeBuffer.write(lexeme);
      } else {
        if (origin.returnEnd != true && origin.excludeEnd != true) {
          modeBuffer.write(lexeme);
        }
        processBuffer();
        if (origin.excludeEnd == true) {
          modeBuffer.write(lexeme);
        }
      }

      bool isSameMode(Mode a, Mode b) {
        if (a.modeId != null && b.modeId != null) {
          return a.modeId == b.modeId;
        }
        return identical(a, b);
      }

      final stopMode = endMode.parent;
      do {
        if (top.scope != null && top.skip != true) {
          emitter.closeNode();
        }
        if (top.skip != true && top.subLanguage == null) {
          relevance += top.relevance ?? 0;
        }
        top = top.parent ?? top;
      } while (stopMode != null && !isSameMode(top, stopMode));

      if (endMode.starts != null) {
        startNewMode(endMode.starts!, match);
      }
      return origin.returnEnd == true ? 0 : lexeme.length;
    }

    void processContinuations() {
      final list = <String>[];
      var current = top;
      while (!identical(current, md) && current.parent != null) {
        final scope = current.scope;
        if (scope is String && scope.isNotEmpty) {
          if (current.skip != true) {
            list.insert(0, _classNameAlias(language, scope) ?? scope);
          }
        }
        current = current.parent!;
      }
      for (final item in list) {
        emitter.openNode(item);
      }
    }

    RuleMatch? lastMatch;

    // Adds the source from [start] to [end] to the buffer, then handles
    // [match]. Returns the number of units of the lexeme that are consumed.
    int processLexeme(int start, int end, RuleMatch? match) {
      if (end > start) modeBuffer.write(codeToHighlight.substring(start, end));

      if (match == null) {
        processBuffer();
        return 0;
      }
      final lexeme = match.lexeme;
      final type = match.rule.type;
      final last = lastMatch;

      if (last != null &&
          last.rule.type == MatchType.begin &&
          type == MatchType.end &&
          last.index == match.index &&
          lexeme.isEmpty) {
        final mi = match.index;
        if (mi < codeToHighlight.length) modeBuffer.write(codeToHighlight[mi]);
        if (!_safeMode) {
          throw StateError('0 width match regex ($languageName)');
        }
        return 1;
      }
      lastMatch = match;

      if (type == MatchType.begin) {
        return doBeginMatch(match);
      } else if (type == MatchType.illegal && !ignoreIllegals) {
        throw StateError(
          'Illegal lexeme "$lexeme" for mode "${top.scope ?? '<unnamed>'}"',
        );
      } else if (type == MatchType.end) {
        final processed = doEndMatch(match);
        if (!identical(processed, noMatch)) {
          return processed as int;
        }
      }

      if (type == MatchType.illegal && lexeme.isEmpty) {
        if (match.index < codeToHighlight.length) {
          modeBuffer.write('\n');
        }
        return 1;
      }

      if (iterations > 100000 && iterations > codeToHighlight.length * 3) {
        throw StateError(
          'potential infinite loop, way more iterations than matches',
        );
      }

      modeBuffer.write(lexeme);
      return lexeme.length;
    }

    processContinuations();
    final ruleMatches = RuleMatchCache();

    try {
      final emitTokens = language.emitTokens;
      if (emitTokens == null) {
        final matcher = top.matcher;
        matcher?.considerAll();

        while (true) {
          iterations++;
          if (resumeScanAtSamePosition) {
            resumeScanAtSamePosition = false;
          } else {
            final matcher = top.matcher;
            matcher?.considerAll();
          }
          final matcher = top.matcher;
          if (matcher == null) break;
          matcher.lastIndex = index;

          final match = matcher.exec(codeToHighlight, ruleMatches);
          if (match == null) break;

          final matchIdx = match.index;
          final safeIndex = index.clamp(0, codeToHighlight.length);
          final processedCount = processLexeme(
            safeIndex,
            matchIdx < safeIndex ? safeIndex : matchIdx,
            match,
          );
          index = matchIdx + processedCount;
        }
        processLexeme(
          index.clamp(0, codeToHighlight.length),
          codeToHighlight.length,
          null,
        );
      } else {
        emitTokens(codeToHighlight, emitter);
      }

      emitter.finalize();

      return HighlightResult(
        language: languageName,
        relevance: relevance,
        emitter: emitter,
        illegal: false,
        top: top,
        continuation: HighlightContinuation._(
          this,
          language,
          top,
          continuations,
          keywordHits,
        ),
      );
    } catch (err) {
      if (err is StateError && err.message.contains('Illegal')) {
        return HighlightResult(
          language: languageName,
          value: escapeHTML(codeToHighlight),
          relevance: 0,
          emitter: TokenTreeEmitter(options),
          illegal: true,
          illegalBy: {
            'message': err.message,
            'index': index,
            'context': codeToHighlight.substring(
              (index - 100).clamp(0, codeToHighlight.length),
              (index + 100).clamp(0, codeToHighlight.length),
            ),
            'mode': top.scope,
          },
        );
      } else if (_safeMode) {
        return HighlightResult(
          language: languageName,
          value: escapeHTML(codeToHighlight),
          relevance: 0,
          emitter: emitter,
          illegal: false,
          errorRaised: err,
          top: top,
        );
      } else {
        rethrow;
      }
    }
  }

  HighlightResult _justTextResult(String code) {
    final options = <String, dynamic>{'classPrefix': 'hljs-'};
    final emitter = TokenTreeEmitter(options);
    emitter.addText(code);
    return HighlightResult(
      language: '',
      relevance: 0,
      value: escapeHTML(code),
      emitter: emitter,
      illegal: false,
    );
  }

  HighlightResult highlightAuto(String code, {List<String>? languageSubset}) {
    final subset = languageSubset ?? _languages.keys.toList();
    final plaintext = _justTextResult(code);

    final results = <HighlightResult>[];
    for (final name in subset) {
      if (getLanguage(name) == null) continue;
      if (!autoDetection(name)) continue;
      try {
        results.add(_highlight(name, code, false));
      } catch (_) {
        // skip languages that error
      }
    }
    results.insert(0, plaintext);

    final indexedResults = results.asMap().entries.toList();
    indexedResults.sort((a, b) {
      final resultA = a.value;
      final resultB = b.value;

      if (resultA.relevance != resultB.relevance) {
        return (resultB.relevance - resultA.relevance).sign.toInt();
      }

      if (resultA.language.isNotEmpty && resultB.language.isNotEmpty) {
        final langA = getLanguage(resultA.language);
        final langB = getLanguage(resultB.language);
        if (langA != null && langA.supersetOf == resultB.language) return 1;
        if (langB != null && langB.supersetOf == resultA.language) return -1;
      }

      return a.key.compareTo(b.key);
    });

    final sortedResults = indexedResults.map((entry) => entry.value).toList();
    final best = sortedResults[0];
    final second = sortedResults.length > 1 ? sortedResults[1] : null;
    best.secondBest = second;
    return best;
  }

  Mode _ensureCompiled(Mode language) {
    if (!language.isCompiled) {
      return compileLanguage(language);
    }
    return language;
  }

  String? _classNameAlias(Mode language, String? kind) {
    if (kind == null) return null;
    final aliases = language.classNameAliases;
    if (aliases != null && aliases.containsKey(kind)) {
      return aliases[kind];
    }
    return kind;
  }

  // Common modes - mirrors MODES in highlight.js
  Mode get MATCH_NOTHING_RE => Mode(begin: r'\b\B');

  static const IDENT_RE = r'[a-zA-Z]\w*';
  static const UNDERSCORE_IDENT_RE = r'[a-zA-Z_]\w*';
  static const NUMBER_RE = r'\b\d+(\.\d+)?';
  static const C_NUMBER_RE =
      r'(-?)(\b0[xX][a-fA-F0-9]+|(\b\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?)';
  static const BINARY_NUMBER_RE = r'\b(0b[01]+)';
  static const RE_STARTERS_RE =
      r'!|!=|!==|%|%=|&|&&|&=|\*|\*=|\+|\+=|,|-|-=|/=|/|:|;|<<|<<=|<=|<|===|==|=|>>>=|>>=|>=|>>>|>>|>|\?|\[|\{|\(|\^|\^=|\||\|=|\|\||~';

  Mode SHEBANG([Mode? opts]) {
    const beginShebang = r'^#![ ]*/';
    dynamic begin = beginShebang;
    if (opts?.binary != null) {
      begin = regex.concat(beginShebang, r'.*\b', opts!.binary!, r'\b.*');
    }
    return Mode(
      scope: 'meta',
      begin: begin,
      end: r'$',
      relevance: 0,
      onBegin: (RegExpMatch m, CallbackResponse resp) {
        if (m.start != 0) resp.ignoreMatch();
      },
    );
  }

  Mode get BACKSLASH_ESCAPE => Mode(begin: r'\\[\s\S]', relevance: 0);

  Mode get APOS_STRING_MODE => Mode(
    scope: 'string',
    begin: "'",
    end: "'",
    illegal: r'\n',
    contains: [BACKSLASH_ESCAPE],
  );

  Mode get QUOTE_STRING_MODE => Mode(
    scope: 'string',
    begin: '"',
    end: '"',
    illegal: r'\n',
    contains: [BACKSLASH_ESCAPE],
  );

  Mode get PHRASAL_WORDS_MODE => Mode(
    begin:
        r"\b(a|an|the|are|I'm|isn't|don't|doesn't|won't|but|just|should|pretty|simply|enough|gonna|going|wtf|so|such|will|you|your|they|like|more)\b",
  );

  Mode COMMENT(dynamic begin, dynamic end, [Mode? modeOptions]) {
    final mode = Mode(
      scope: modeOptions?.scope ?? 'comment',
      begin: modeOptions?.begin ?? begin,
      end: modeOptions?.end ?? end,
      contains: modeOptions?.contains != null
          ? List.from(modeOptions!.contains!)
          : <dynamic>[],
      relevance: modeOptions?.relevance,
      keywords: modeOptions?.keywords,
      illegal: modeOptions?.illegal,
    );

    final contains = mode.contains as List<dynamic>;
    contains.add(
      Mode(
        scope: 'doctag',
        begin: r'[ ]*(?=(TODO|FIXME|NOTE|BUG|OPTIMIZE|HACK|XXX):)',
        end: RegExp(r'(TODO|FIXME|NOTE|BUG|OPTIMIZE|HACK|XXX):'),
        excludeBegin: true,
        relevance: 0,
      ),
    );

    final englishWord = regex.either(
      'I',
      'a',
      'is',
      'so',
      'us',
      'to',
      'at',
      'if',
      'in',
      'it',
      'on',
      RegExp(r"[A-Za-z]+['][](d|ve|re|ll|t|s|n)"),
      RegExp(r'[A-Za-z]+[-][a-z]+'),
      RegExp(r'[A-Za-z][a-z]{2,}'),
    );
    contains.add(
      Mode(
        begin: regex.concat(
          r'[ ]+',
          '(',
          englishWord,
          r'[.]?[:]?([.][ ]|[ ])',
          '){3}',
        ),
      ),
    );

    return mode;
  }

  Mode get C_LINE_COMMENT_MODE => COMMENT('//', r'$');
  Mode get C_BLOCK_COMMENT_MODE => COMMENT(r'/\*', r'\*/');
  Mode get HASH_COMMENT_MODE => COMMENT('#', r'$');

  Mode get NUMBER_MODE => Mode(scope: 'number', begin: NUMBER_RE, relevance: 0);

  Mode get C_NUMBER_MODE =>
      Mode(scope: 'number', begin: C_NUMBER_RE, relevance: 0);

  Mode get BINARY_NUMBER_MODE =>
      Mode(scope: 'number', begin: BINARY_NUMBER_RE, relevance: 0);

  Mode get REGEXP_MODE => Mode(
    scope: 'regexp',
    begin: r'/(?=[^/\n]*\/)',
    end: r'/[gimuy]*',
    contains: [
      BACKSLASH_ESCAPE,
      Mode(
        begin: r'\[',
        end: r'\]',
        relevance: 0,
        contains: [BACKSLASH_ESCAPE],
      ),
    ],
  );

  Mode get TITLE_MODE => Mode(scope: 'title', begin: IDENT_RE, relevance: 0);

  Mode get UNDERSCORE_TITLE_MODE =>
      Mode(scope: 'title', begin: UNDERSCORE_IDENT_RE, relevance: 0);

  Mode get METHOD_GUARD =>
      Mode(begin: '\\.\\s*$UNDERSCORE_IDENT_RE', relevance: 0);

  Mode END_SAME_AS_BEGIN(Mode mode) {
    mode.onBegin = (RegExpMatch m, CallbackResponse resp) {
      resp.data['_beginMatch'] = m.group(1);
    };
    mode.onEnd = (RegExpMatch m, CallbackResponse resp) {
      if (resp.data['_beginMatch'] != m.group(1)) resp.ignoreMatch();
    };
    return mode;
  }

  // regex utilities exposed for language definitions
  Map<String, dynamic> get regexHelpers => {
    'concat': regex.concat,
    'lookahead': regex.lookahead,
    'either': regex.either,
    'optional': regex.optional,
    'anyNumberOfTimes': regex.anyNumberOfTimes,
  };
}

final hljs = Highlight();
