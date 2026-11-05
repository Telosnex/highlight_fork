import 'package:highlight_fork/highlight_core.dart' show hljs;
import 'package:highlight_fork/languages/dart.dart';

void main() {
  var source = '''main() {
  print("Hello, World!");
}
''';

  hljs.registerLanguage('dart', dart);

  var result = hljs.highlight(source, language: 'dart');
  var html = result.toHtml();
  print(html); // HTML string
}
