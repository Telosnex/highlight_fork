# highlight_fork

Syntax highlighting for Dart and Flutter, based on highlight.js 11.
The default registry contains Telosnex's 38 grammars and 78 fence aliases.

Version 0.8.0 migrates the legacy 0.7 engine to upstream master `696d9a4`.
See [the core package guide](highlight/README.md) for the new API, continuation limits, and evaluation commands.

Regenerate languages with `dart run tool/generate_languages.dart`.
Regenerate themes with `dart run tool/generate_themes.dart`.
The generators preserve the limited default registry and hand-ported Solidity/Vue grammars.

[View gallery built with Flutter web](https://git-touch.github.io/highlight/)

| Package | Version | Description |
| --- | --- | --- |
| [highlight](https://github.com/pd4d10/highlight/tree/master/highlight) | [![pub](https://img.shields.io/pub/v/highlight)](https://pub.dev/packages/highlight) | Core syntax highlighting library written in Dart |
| [flutter_highlight](https://github.com/pd4d10/highlight/tree/master/flutter_highlight) | [![pub](https://img.shields.io/pub/v/flutter_highlight)](https://pub.dev/packages/flutter_highlight) | Flutter syntax highlighting widget |
|  |

## References

- [All available languages](https://github.com/pd4d10/highlight/tree/master/highlight/lib/languages)
- [All available themes](https://github.com/pd4d10/highlight/blob/master/flutter_highlight/lib/themes)

## License

MIT
