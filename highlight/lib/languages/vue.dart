// Port of vendor/highlightjs-vue/vue.js (fe48d26), with attribute-order and
// <script setup> support for contemporary single-file components.
import '../highlight_core.dart';

Mode vue(Highlight hljs) {
  Mode block(String tag, String language, [String? lang]) => Mode(
    begin: lang == null
        ? '<$tag\\b[^>]*>'
        : '<$tag\\b(?=[^>]*\\blang\\s*=\\s*["\'](?:$lang)["\'])[^>]*>',
    end: '</$tag\\s*>',
    subLanguage: language,
    excludeBegin: true,
    excludeEnd: true,
  );
  return Mode(
    name: 'Vue',
    // Plain markup delegates to XML and receives the same relevance. Prefer
    // XML on ties rather than claiming every XML/HTML/SVG document as Vue.
    supersetOf: 'xml',
    subLanguage: 'xml',
    contains: [
      hljs.COMMENT('<!--', '-->', Mode(relevance: 10)),
      block('script', 'typescript', 'ts|typescript'),
      block('script', 'javascript'),
      block('style', 'scss', 'scss|sass'),
      block('style', 'stylus', 'stylus'),
      block('style', 'css'),
    ],
  );
}
