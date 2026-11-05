import 'package:highlight_fork/highlight_core.dart';
import 'package:highlight_fork/highlight.dart' as defaults;
import 'package:highlight_fork/languages/solidity.dart' as sol;
import 'package:highlight_fork/languages/vue.dart' as vue;
import 'package:highlight_fork/languages/javascript.dart' as js;
import 'package:highlight_fork/languages/typescript.dart' as ts;
import 'package:highlight_fork/languages/xml.dart' as xml;
import 'package:highlight_fork/languages/css.dart' as css;
import 'package:highlight_fork/languages/scss.dart' as scss;
import 'package:highlight_fork/languages/stylus.dart' as stylus;
import 'package:highlight_fork/languages/go.dart' as go;
import 'package:test/test.dart';

import 'fixtures/vendor_sources.dart';

Highlight engine() => Highlight()
  ..registerLanguage('solidity', sol.solidity)
  ..registerLanguage('vue', vue.vue)
  ..registerLanguage('javascript', js.javascript)
  ..registerLanguage('typescript', ts.typescript)
  ..registerLanguage('xml', xml.xml)
  ..registerLanguage('css', css.css)
  ..registerLanguage('scss', scss.scss)
  ..registerLanguage('stylus', stylus.stylus)
  ..registerLanguage('go', go.go);

String plain(dynamic node) =>
    node is String ? node : (node as DataNode).children.map(plain).join();

void main() {
  test('Solidity factory, alias, types, builtins and nested assembly', () {
    final hljs = engine();
    final result = hljs.highlight(soliditySource, language: 'sol');
    expect(result.errorRaised, isNull);
    expect(plain(result.emitter.root), soliditySource);
    for (final token in ['pragma', 'mapping', 'uint256', 'payable', 'sload']) {
      expect(result.value, contains('>$token</span>'));
    }
    expect(result.value, contains('hljs-meta'));
    expect(result.value, contains('hljs-title'));
    expect(result.value, contains('hljs-built_in'));
    expect(hljs.highlightAuto(soliditySource).language, 'solidity');
  });

  test('Solidity relevance does not poison JavaScript or Go detection', () {
    final hljs = engine();
    expect(
      hljs
          .highlightAuto(
            javascriptSource,
            languageSubset: ['javascript', 'solidity'],
          )
          .language,
      'javascript',
    );
    expect(
      hljs.highlightAuto(goSource, languageSubset: ['go', 'solidity']).language,
      'go',
    );
    expect(
      hljs
          .highlight('return int uint bytes true false', language: 'solidity')
          .relevance,
      0,
    );
  });

  test(
    'Vue modern SFC embeds XML, TypeScript and SCSS without losing text',
    () {
      final result = engine().highlight(vueSource, language: 'vue');
      expect(result.errorRaised, isNull);
      expect(plain(result.emitter.root), vueSource);
      expect(result.value, contains('language-xml'));
      expect(result.value, contains('language-typescript'));
      expect(result.value, contains('language-scss'));
      expect(result.value, contains('hljs-keyword'));
      expect(result.value, contains('hljs-selector-tag'));
    },
  );

  test(
    'Vue vendor plain script and scoped style, comments and inline blocks',
    () {
      const source =
          '<!-- note --><template><p>Hello</p></template>'
          '<script>const value = "ok";</script>'
          '<style scoped>p { color: red; }</style>';
      final result = engine().highlight(source, language: 'vue');
      expect(result.errorRaised, isNull);
      expect(plain(result.emitter.root), source);
      expect(result.value, contains('hljs-comment'));
      expect(result.value, contains('language-javascript'));
      expect(result.value, contains('language-css'));
    },
  );

  test('Vue does not claim ordinary XML in the full default registry', () {
    defaults.ensureInitialized();
    const samples = [
      '<?xml version="1.0"?><catalog><item id="1">Title</item></catalog>',
      '<!DOCTYPE html><html><head><style>p { color: red; }</style></head>'
          '<body><!-- A normal web page --><p>Hello</p>'
          '<script>const message = "hello";</script></body></html>',
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
          '<circle cx="5" cy="5" r="4" /></svg>',
    ];
    for (final source in samples) {
      expect(defaults.hljs.highlightAuto(source).language, 'xml');
    }
    // The tie-breaker keeps Vue eligible for opt-in autodetection subsets as
    // well as explicit language hints; it does not disable the grammar.
    expect(
      defaults.hljs.highlightAuto(vueSource, languageSubset: ['vue']).language,
      'vue',
    );
    final explicit = defaults.hljs.highlight(vueSource, language: 'vue');
    expect(explicit.errorRaised, isNull);
    expect(plain(explicit.emitter.root), vueSource);
    expect(explicit.value, contains('language-typescript'));
    expect(explicit.value, contains('language-scss'));
  });

  test(
    'Vendor factories do not share mutable compiled modes across engines',
    () {
      for (var i = 0; i < 2; i++) {
        final hljs = engine();
        expect(
          hljs.highlight(soliditySource, language: 'sol').errorRaised,
          isNull,
        );
        expect(hljs.highlight(vueSource, language: 'vue').errorRaised, isNull);
      }
    },
  );
}
