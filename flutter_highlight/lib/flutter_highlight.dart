import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:highlight_fork/highlight.dart'
    show hljs, ensureInitialized, DataNode;

/// Highlight Flutter Widget
class HighlightView extends StatelessWidget {
  /// The original code to be highlighted
  final String source;

  /// Highlight language
  ///
  /// It is recommended to give it a value for performance
  ///
  /// [All available languages](https://github.com/pd4d10/highlight/tree/master/highlight/lib/languages)
  final String? language;

  /// Highlight theme
  ///
  /// [All available themes](https://github.com/pd4d10/highlight/blob/master/flutter_highlight/lib/themes)
  final Map<String, TextStyle> theme;

  /// Padding
  final EdgeInsetsGeometry? padding;

  /// Text styles
  ///
  /// Specify text styles such as font family and font size
  final TextStyle? textStyle;

  HighlightView(
    String input, {
    this.language,
    this.theme = const {},
    this.padding,
    this.textStyle,
    int tabSize = 8, // TODO: https://github.com/flutter/flutter/issues/50087
  }) : source = input.replaceAll('\t', ' ' * tabSize);

  List<TextSpan> _convert(List<dynamic> nodes) {
    return nodes.map((node) {
      if (node is String) return TextSpan(text: node);
      final data = node as DataNode;
      final scope = data.scope;
      TextStyle? style;
      if (scope != null && !scope.startsWith('language:')) {
        var key = scope;
        while (true) {
          style = theme[key];
          if (style != null || !key.contains('.')) break;
          key = key.substring(0, key.lastIndexOf('.'));
        }
      }
      return TextSpan(children: _convert(data.children), style: style);
    }).toList();
  }

  static const _rootKey = 'root';
  static const _defaultFontColor = Color(0xff000000);
  static const _defaultBackgroundColor = Color(0xffffffff);

  // TODO: dart:io is not available at web platform currently
  // See: https://github.com/flutter/flutter/issues/39998
  // So we just use monospace here for now
  static const _defaultFontFamily = 'monospace';

  @override
  Widget build(BuildContext context) {
    ensureInitialized();
    final result = language == null
        ? hljs.highlightAuto(source)
        : hljs.highlight(
            source,
            language: hljs.hasLanguage(language!) ? language! : 'plaintext',
          );
    var _textStyle = TextStyle(
      fontFamily: _defaultFontFamily,
      color: theme[_rootKey]?.color ?? _defaultFontColor,
    );
    if (textStyle != null) {
      _textStyle = _textStyle.merge(textStyle);
    }

    return Container(
      color: theme[_rootKey]?.backgroundColor ?? _defaultBackgroundColor,
      padding: padding,
      child: RichText(
        text: TextSpan(
          style: _textStyle,
          children: _convert(result.emitter.root.children),
        ),
      ),
    );
  }
}
