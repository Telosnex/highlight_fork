import 'package:highlight_fork/highlight.dart';
import 'package:test/test.dart';

void main() {
  ensureInitialized();
  const aliases = [
    'bash',
    'shell',
    'sh',
    'zsh',
    'console',
    'cpp',
    'c',
    'cc',
    'h',
    'hpp',
    'cs',
    'csharp',
    'css',
    'dart',
    'diff',
    'patch',
    'dockerfile',
    'docker',
    'go',
    'golang',
    'graphql',
    'gql',
    'http',
    'https',
    'ini',
    'toml',
    'java',
    'javascript',
    'js',
    'jsx',
    'mjs',
    'cjs',
    'json',
    'kotlin',
    'kt',
    'lua',
    'makefile',
    'mk',
    'markdown',
    'md',
    'nginx',
    'nginxconf',
    'objectivec',
    'objc',
    'obj-c',
    'mm',
    'perl',
    'pl',
    'php',
    'plaintext',
    'text',
    'txt',
    'powershell',
    'ps',
    'ps1',
    'python',
    'py',
    'r',
    'ruby',
    'rb',
    'rust',
    'rs',
    'scss',
    'solidity',
    'sol',
    'sql',
    'swift',
    'tex',
    'latex',
    'typescript',
    'ts',
    'vue',
    'xml',
    'html',
    'xhtml',
    'svg',
    'yaml',
    'yml',
  ];
  test('default registry has exactly 38 grammars', () {
    expect(hljs.listLanguages(), hasLength(38));
    expect(hljs.hasLanguage('1c'), isFalse);
  });
  for (final alias in aliases) {
    test('$alias resolves and parses losslessly', () {
      expect(hljs.hasLanguage(alias), isTrue);
      final result = hljs.highlight('a = "b" // c\n', language: alias);
      expect(result.errorRaised, isNull);
      String text(dynamic node) =>
          node is String ? node : (node as DataNode).children.map(text).join();
      expect(text(result.emitter.root), 'a = "b" // c\n');
    });
  }
}
