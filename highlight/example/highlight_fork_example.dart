import 'package:highlight_fork/highlight.dart' show hljs, ensureInitialized;

void main() {
  ensureInitialized();
  var source = '''main() {
  print("Hello, World!");
}
''';

  var result = hljs.highlight(source, language: 'dart');
  var html = result.toHtml();
  print(html); // HTML string
}
