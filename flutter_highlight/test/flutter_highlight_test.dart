import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HighlightView preserves unregistered languages as plain text',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: HighlightView('some code', language: '1c'),
    ));
    expect(tester.widget<RichText>(find.byType(RichText)).text.toPlainText(),
        'some code');
  });

  testWidgets('HighlightView styles tokens with the theme', (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: HighlightView('final x = 1; // one',
          language: 'dart', theme: githubTheme),
    ));
    final text = tester.widget<RichText>(find.byType(RichText)).text;
    // A token's colour can come from a parent span: take the innermost one.
    final styled = <String, Color?>{};
    void walk(InlineSpan span, Color? inherited) {
      if (span is! TextSpan) return;
      final color = span.style?.color ?? inherited;
      if (span.text != null) styled[span.text!] = color;
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, color);
      }
    }

    walk(text, null);
    expect(text.toPlainText(), 'final x = 1; // one');
    expect(styled['final'], githubTheme['keyword']!.color);
    expect(styled['1'], githubTheme['number']!.color);
    expect(styled['// one'], githubTheme['comment']!.color);
  });
}
