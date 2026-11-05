import 'package:highlight_fork/highlight.dart';
import 'package:test/test.dart';

// Compare effective scope stacks per UTF-16 code unit, not HTML span boundaries:
// resumed parses intentionally reopen the scopes that span the boundary.
List<String> scopes(HighlightResult result) {
  expect(result.errorRaised, isNull);
  final output = <String>[];
  void walk(dynamic node, List<String> stack) {
    if (node is String) {
      output.addAll(node.codeUnits.map((unit) => '$unit:${stack.join('/')}'));
    } else if (node is DataNode) {
      final next = node.scope == null ? stack : [...stack, node.scope!];
      for (final child in node.children) {
        walk(child, next);
      }
    }
  }

  walk(result.emitter.root, []);
  return output;
}

void expectChunks(Highlight engine, String language, List<String> chunks) {
  final whole = engine.highlight(chunks.join(), language: language);
  final actual = <String>[];
  HighlightContinuation? checkpoint;
  for (final chunk in chunks) {
    final result = engine.highlight(
      chunk,
      language: language,
      continuation: checkpoint,
    );
    expect(result.continuation, isNotNull);
    checkpoint = result.continuation;
    actual.addAll(scopes(result));
  }
  expect(actual, scopes(whole), reason: language);
}

// These are deliberately chosen safe complete-line boundaries, not a promise
// that every newline is safe. Each fixture has three independently resumed
// chunks. Several fixtures also leave comments, strings or container scopes
// open so this exercises actual mode continuation rather than just fresh parses.
const defaultGrammarChunks = <String, List<String>>{
  'bash': ['#!/bin/bash\n', 'name="world"\n', 'echo "\$name"\n'],
  'shell': ['\$ echo hello\n', 'hello\n', '\$ pwd\n'],
  'cpp': [
    'int main() { /* begin\n',
    'comment */ int value = 42;\n',
    'return value; }\n',
  ],
  'cs': [
    'class Example { /* begin\n',
    'comment */ string name = "hello";\n',
    '}\n',
  ],
  'css': ['.example { /* begin\n', 'comment */ color: red;\n', '}\n'],
  'dart': [
    'void main() { /* begin\n',
    'comment */ final value = 42;\n',
    'print(value); }\n',
  ],
  'diff': ['--- old.txt\n', '+++ new.txt\n', '@@ -1 +1 @@\n-old\n+new\n'],
  'dockerfile': ['FROM alpine:3.20\n', 'ENV APP=example\n', 'RUN echo hello\n'],
  'go': ['package main\n', '/* begin\n', 'comment */ var value = 42\n'],
  'graphql': ['query Example {\n', '  viewer { id name }\n', '}\n'],
  'http': [
    'GET /example HTTP/1.1\n',
    'Host: example.com\n',
    'Accept: text/plain\n',
  ],
  'ini': ['[example]\n', 'enabled = true\n', 'name = "hello"\n'],
  'java': ['class Example { /* begin\n', 'comment */ int value = 42;\n', '}\n'],
  'javascript': [
    '/* begin\n',
    'comment */ const value = 42;\n',
    'console.log(value);\n',
  ],
  'json': ['{\n', '  "name": "hello",\n', '  "enabled": true\n}\n'],
  'kotlin': ['/* begin\n', 'comment */ val value = 42\n', 'println(value)\n'],
  'lua': ['--[[ begin\n', 'comment ]] local value = 42\n', 'print(value)\n'],
  'makefile': ['all: build\n', '\techo hello\n', 'build:\n\techo done\n'],
  'markdown': ['# Example\n', '## Details\n', '### More details\n'],
  'nginx': [
    'server {\n',
    '  listen 8080;\n',
    '  server_name example.com;\n}\n',
  ],
  'objectivec': [
    '/* begin\n',
    'comment */ NSString *name = @"hello";\n',
    'NSLog(@"%@", name);\n',
  ],
  'perl': ['my \$name = "hello";\n', '# a comment\n', 'print \$name;\n'],
  'php': ['<?php\n/* begin\n', 'comment */ \$value = 42;\n', 'echo \$value;\n'],
  'plaintext': ['Example plain text.\n', 'Second line: 42.\n', 'The end.\n'],
  'powershell': [
    '<# begin\n',
    'comment #> \$name = "hello"\n',
    'Write-Host \$name\n',
  ],
  'python': ['name = """first\n', 'second\n', 'third"""\nprint(name)\n'],
  'r': ['value <- 42\n', '# a comment\n', 'print(value)\n'],
  'ruby': ['name = "hello"\n', '# a comment\n', 'puts name\n'],
  'rust': [
    'fn main() { /* begin\n',
    'comment */ let value = 42;\n',
    'println!("{}", value); }\n',
  ],
  'scss': [
    '\$color: red;\n.example { /* begin\n',
    'comment */ color: \$color;\n',
    '}\n',
  ],
  'solidity': [
    'pragma solidity ^0.8.0;\ncontract Example { /* begin\n',
    'comment */ uint256 public value = 42;\n',
    '}\n',
  ],
  'sql': [
    '/* begin\n',
    'comment */ SELECT id, name\n',
    'FROM users WHERE id = 42;\n',
  ],
  'swift': ['/* begin\n', 'comment */ let value = 42\n', 'print(value)\n'],
  'tex': ['\\section{Example}\n', '\\textbf{Hello world}\n', '% a comment\n'],
  'typescript': [
    '/* begin\n',
    'comment */ const value: number = 42;\n',
    'console.log(value);\n',
  ],
  'vue': [
    '<template>\n',
    '<div class="example">Hello</div>\n',
    '</template>\n',
  ],
  'xml': [
    '<example><!-- begin\n',
    'comment --><item id="42">Hello</item>\n',
    '</example>\n',
  ],
  'yaml': ['example:\n', '  name: "hello"\n', '  enabled: true\n'],
};

void main() {
  ensureInitialized();

  test('safe-line table covers exactly the default registry', () {
    expect(defaultGrammarChunks.keys.toSet(), hljs.listLanguages().toSet());
    expect(defaultGrammarChunks, hasLength(38));
  });

  for (final fixture in defaultGrammarChunks.entries) {
    test('safe-line chunk/full scope equivalence: ${fixture.key}', () {
      expect(fixture.value, hasLength(3));
      expectChunks(hljs, fixture.key, fixture.value);
    });
  }

  test('registered multiline grammars retain scopes over line boundaries', () {
    for (final language in [
      'dart',
      'javascript',
      'typescript',
      'java',
      'c',
      'cpp',
      'css',
      'rust',
      'swift',
      'kotlin',
      'go',
    ]) {
      expectChunks(hljs, language, ['/* first\n', 'second\n', 'last */\n']);
    }
    for (final language in ['python', 'dart']) {
      expectChunks(hljs, language, ['x = """first\n', 'second\n', 'last"""\n']);
    }
    expectChunks(hljs, 'xml', ['<!-- first\n', 'second\n', 'last -->\n']);
  });

  test('checkpoint can be reused after multiple unrelated resumes', () {
    final prefix = hljs.highlight('/* first\n', language: 'javascript');
    final checkpoint = prefix.continuation!;
    final one = hljs.highlight(
      'second */ const x = 1;\n',
      language: 'javascript',
      continuation: checkpoint,
    );
    hljs.highlight(
      'other /* nested */\n',
      language: 'javascript',
      continuation: checkpoint,
    );
    hljs.highlight('const x = "unrelated";', language: 'javascript');
    final again = hljs.highlight(
      'second */ const x = 1;\n',
      language: 'javascript',
      continuation: checkpoint,
    );
    expect(scopes(again), scopes(one));
    // Mutating the legacy public top field must not mutate the saved snapshot.
    prefix.top!.data = {'corrupt': true};
    expect(
      scopes(
        hljs.highlight(
          'second */ const x = 1;\n',
          language: 'javascript',
          continuation: checkpoint,
        ),
      ),
      scopes(one),
    );
  });

  test(
    'aliases accept a checkpoint but other languages and engines reject it',
    () {
      final checkpoint = hljs
          .highlight('/* open\n', language: 'javascript')
          .continuation!;
      expect(
        hljs
            .highlight('close */', language: 'js', continuation: checkpoint)
            .errorRaised,
        isNull,
      );
      expect(
        () => hljs.highlight('x', language: 'python', continuation: checkpoint),
        throwsArgumentError,
      );
      final other = Highlight()..registerLanguage('javascript', (_) => Mode());
      expect(
        () => other.highlight(
          'x',
          language: 'javascript',
          continuation: checkpoint,
        ),
        throwsArgumentError,
      );
      final local = Highlight()..registerLanguage('test', (_) => Mode());
      final old = local.highlight('', language: 'test').continuation!;
      local.registerLanguage('test', (_) => Mode());
      expect(
        () => local.highlight('x', language: 'test', continuation: old),
        throwsArgumentError,
      );
    },
  );

  test('named embedded languages retain independent continuation state', () {
    final local = Highlight()
      ..registerLanguage(
        'inner',
        (h) => Mode(contains: [h.C_BLOCK_COMMENT_MODE]),
      )
      ..registerLanguage(
        'outer',
        (_) => Mode(
          contains: [
            Mode(
              begin: '<script>',
              end: '</script>',
              subLanguage: 'inner',
              excludeBegin: true,
              excludeEnd: true,
            ),
          ],
        ),
      );
    expectChunks(local, 'outer', [
      '<script>/* first\n',
      'second\n',
      'last */</script>\n',
    ]);
    // Re-entering a sublanguage region resumes its last state as highlight.js does.
    expectChunks(local, 'outer', [
      '<script>/* first</script>\n',
      '<script>last */</script>\n',
    ]);
  });

  test('end callback data and nested mode identities survive resume', () {
    final local = Highlight()
      ..registerLanguage(
        'custom',
        (h) => Mode(
          contains: [
            h.END_SAME_AS_BEGIN(
              Mode(
                scope: 'string',
                begin: r'<(\w+)>',
                end: r'</(\w+)>',
                contains: [Mode(scope: 'subst', begin: r'\{', end: r'\}')],
              ),
            ),
          ],
        ),
      );
    expectChunks(local, 'custom', [
      '<tag>first\n',
      '{second}\n',
      '</wrong>still string\n',
      '</tag>plain\n',
    ]);
    final checkpoint = local
        .highlight('<tag>first\n', language: 'custom')
        .continuation!;
    local.highlight(
      '</tag><different>x</different>',
      language: 'custom',
      continuation: checkpoint,
    );
    final second = local.highlight(
      '</wrong>still string</tag>plain',
      language: 'custom',
      continuation: checkpoint,
    );
    expect(
      scopes(second),
      scopes(
        local.highlight(
          '<tag></wrong>still string</tag>plain',
          language: 'custom',
        ),
      ).skip('<tag>'.length).toList(),
    );
  });

  test('skip scopes and class aliases reopen consistently', () {
    final local = Highlight()
      ..registerLanguage(
        'custom',
        (_) => Mode(
          classNameAliases: {'old': 'new'},
          contains: [
            Mode(
              scope: 'old',
              begin: '<',
              end: '>',
              contains: [
                Mode(scope: 'hidden', skip: true, begin: r'\[', end: r'\]'),
              ],
            ),
          ],
        ),
      );
    expectChunks(local, 'custom', ['<first[skip\n', 'more]last>\n']);
  });

  test('keyword relevance limits continue across chunks', () {
    final local = Highlight()
      ..registerLanguage('custom', (_) => Mode(keywords: 'word'));
    final full = local.highlight('word ' * 10, language: 'custom');
    HighlightContinuation? checkpoint;
    num total = 0;
    for (var i = 0; i < 10; i++) {
      final part = local.highlight(
        'word ',
        language: 'custom',
        continuation: checkpoint,
      );
      checkpoint = part.continuation;
      total += part.relevance;
    }
    expect(total, full.relevance);
    expect(total, 7);
  });

  test('real multiline lookahead requires reparsing the earlier tail', () {
    // JavaScript function-call recognition looks forward through whitespace.
    // A parser checkpoint cannot revise an already-emitted earlier chunk.
    final prefix = hljs.highlight('hello\n', language: 'javascript');
    final suffix = hljs.highlight(
      '()',
      language: 'javascript',
      continuation: prefix.continuation,
    );
    final full = hljs.highlight('hello\n()', language: 'javascript');
    expect(full.value, contains('hljs-title function_'));
    expect([...scopes(prefix), ...scopes(suffix)], isNot(scopes(full)));
  });

  test('arbitrary token splits are explicitly not a streaming lexer', () {
    final first = hljs.highlight('con', language: 'javascript');
    final rest = hljs.highlight(
      'st x = 1;',
      language: 'javascript',
      continuation: first.continuation,
    );
    expect([
      ...scopes(first),
      ...scopes(rest),
    ], isNot(scopes(hljs.highlight('const x = 1;', language: 'javascript'))));
  });
}
