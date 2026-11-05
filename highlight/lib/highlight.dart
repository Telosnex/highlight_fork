/// Telosnex's limited registry: 38 grammars, with all existing fence aliases.
/// Import highlight_core.dart instead to create an isolated custom registry.
library;

export 'highlight_core.dart';
import 'highlight_core.dart';
import 'languages/bash.dart' as lang_bash;
import 'languages/shell.dart' as lang_shell;
import 'languages/cpp.dart' as lang_cpp;
import 'languages/csharp.dart' as lang_cs;
import 'languages/css.dart' as lang_css;
import 'languages/dart.dart' as lang_dart;
import 'languages/diff.dart' as lang_diff;
import 'languages/dockerfile.dart' as lang_dockerfile;
import 'languages/go.dart' as lang_go;
import 'languages/graphql.dart' as lang_graphql;
import 'languages/http.dart' as lang_http;
import 'languages/ini.dart' as lang_ini;
import 'languages/java.dart' as lang_java;
import 'languages/javascript.dart' as lang_javascript;
import 'languages/json.dart' as lang_json;
import 'languages/kotlin.dart' as lang_kotlin;
import 'languages/lua.dart' as lang_lua;
import 'languages/makefile.dart' as lang_makefile;
import 'languages/markdown.dart' as lang_markdown;
import 'languages/nginx.dart' as lang_nginx;
import 'languages/objectivec.dart' as lang_objectivec;
import 'languages/perl.dart' as lang_perl;
import 'languages/php.dart' as lang_php;
import 'languages/plaintext.dart' as lang_plaintext;
import 'languages/powershell.dart' as lang_powershell;
import 'languages/python.dart' as lang_python;
import 'languages/r.dart' as lang_r;
import 'languages/ruby.dart' as lang_ruby;
import 'languages/rust.dart' as lang_rust;
import 'languages/scss.dart' as lang_scss;
import 'languages/solidity.dart' as lang_solidity;
import 'languages/sql.dart' as lang_sql;
import 'languages/swift.dart' as lang_swift;
import 'languages/latex.dart' as lang_tex;
import 'languages/typescript.dart' as lang_typescript;
import 'languages/vue.dart' as lang_vue;
import 'languages/xml.dart' as lang_xml;
import 'languages/yaml.dart' as lang_yaml;

final _initialized = _init();

bool _init() {
  hljs.registerLanguage('bash', lang_bash.bash);
  hljs.registerLanguage('shell', lang_shell.shell);
  hljs.registerLanguage('cpp', lang_cpp.cpp);
  hljs.registerLanguage('cs', lang_cs.csharp);
  hljs.registerLanguage('css', lang_css.css);
  hljs.registerLanguage('dart', lang_dart.dart);
  hljs.registerLanguage('diff', lang_diff.diff);
  hljs.registerLanguage('dockerfile', lang_dockerfile.dockerfile);
  hljs.registerLanguage('go', lang_go.go);
  hljs.registerLanguage('graphql', lang_graphql.graphql);
  hljs.registerLanguage('http', lang_http.http);
  hljs.registerLanguage('ini', lang_ini.ini);
  hljs.registerLanguage('java', lang_java.java);
  hljs.registerLanguage('javascript', lang_javascript.javascript);
  hljs.registerLanguage('json', lang_json.json);
  hljs.registerLanguage('kotlin', lang_kotlin.kotlin);
  hljs.registerLanguage('lua', lang_lua.lua);
  hljs.registerLanguage('makefile', lang_makefile.makefile);
  hljs.registerLanguage('markdown', lang_markdown.markdown);
  hljs.registerLanguage('nginx', lang_nginx.nginx);
  hljs.registerLanguage('objectivec', lang_objectivec.objectivec);
  hljs.registerLanguage('perl', lang_perl.perl);
  hljs.registerLanguage('php', lang_php.php);
  hljs.registerLanguage('plaintext', lang_plaintext.plaintext);
  hljs.registerLanguage('powershell', lang_powershell.powershell);
  hljs.registerLanguage('python', lang_python.python);
  hljs.registerLanguage('r', lang_r.r);
  hljs.registerLanguage('ruby', lang_ruby.ruby);
  hljs.registerLanguage('rust', lang_rust.rust);
  hljs.registerLanguage('scss', lang_scss.scss);
  hljs.registerLanguage('solidity', lang_solidity.solidity);
  hljs.registerLanguage('sql', lang_sql.sql);
  hljs.registerLanguage('swift', lang_swift.swift);
  hljs.registerLanguage('tex', lang_tex.latex);
  hljs.registerLanguage('typescript', lang_typescript.typescript);
  hljs.registerLanguage('vue', lang_vue.vue);
  hljs.registerLanguage('xml', lang_xml.xml);
  hljs.registerLanguage('yaml', lang_yaml.yaml);
  hljs.registerAliases(['sh', 'zsh'], languageName: 'bash');
  hljs.registerAliases(['console'], languageName: 'shell');
  hljs.registerAliases(['c', 'cc', 'h', 'hpp'], languageName: 'cpp');
  hljs.registerAliases(['csharp'], languageName: 'cs');
  hljs.registerAliases(['patch'], languageName: 'diff');
  hljs.registerAliases(['docker'], languageName: 'dockerfile');
  hljs.registerAliases(['golang'], languageName: 'go');
  hljs.registerAliases(['gql'], languageName: 'graphql');
  hljs.registerAliases(['https'], languageName: 'http');
  hljs.registerAliases(['toml'], languageName: 'ini');
  hljs.registerAliases(['js', 'jsx', 'mjs', 'cjs'], languageName: 'javascript');
  hljs.registerAliases(['kt'], languageName: 'kotlin');
  hljs.registerAliases(['mk'], languageName: 'makefile');
  hljs.registerAliases(['md'], languageName: 'markdown');
  hljs.registerAliases(['nginxconf'], languageName: 'nginx');
  hljs.registerAliases(['objc', 'obj-c', 'mm'], languageName: 'objectivec');
  hljs.registerAliases(['pl'], languageName: 'perl');
  hljs.registerAliases(['text', 'txt'], languageName: 'plaintext');
  hljs.registerAliases(['ps', 'ps1'], languageName: 'powershell');
  hljs.registerAliases(['py'], languageName: 'python');
  hljs.registerAliases(['rb'], languageName: 'ruby');
  hljs.registerAliases(['rs'], languageName: 'rust');
  hljs.registerAliases(['sol'], languageName: 'solidity');
  hljs.registerAliases(['latex'], languageName: 'tex');
  hljs.registerAliases(['ts'], languageName: 'typescript');
  hljs.registerAliases(['html', 'xhtml', 'svg'], languageName: 'xml');
  hljs.registerAliases(['yml'], languageName: 'yaml');
  return true;
}

/// Initializes the default registry before using [hljs].
void ensureInitialized() {
  // ignore: unnecessary_statements
  _initialized;
}
