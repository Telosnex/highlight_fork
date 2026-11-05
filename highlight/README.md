# highlight_fork

Telosnex's Dart port of highlight.js 11, based on upstream master `696d9a4`.
The default registry contains 38 grammars and preserves all 78 existing fence aliases.
Dart 3.8 or later is required.

## Highlight code

```dart
import 'package:highlight_fork/highlight.dart';

void main() {
  ensureInitialized();
  final result = hljs.highlight('print("hello");', language: 'dart');
  print(result.toHtml());
}
```

`hljs.highlightAuto(code)` detects a language. An unknown explicit language throws `ArgumentError`.
The result contains a `DataNode` tree at `result.emitter.root`.
Each child is a text string or another `DataNode` with an optional scope.
Scopes can contain dots, for example `title.function` and `title.class`.
Embedded language scopes use `language:javascript`.

For a custom registry, import `highlight_core.dart` and create a `Highlight` instance.
Register a grammar with `engine.registerLanguage('dart', dart)` from `languages/dart.dart`.
The default registry does not load the full generated grammar set, including the 1C grammar.

## Resume a parse

```dart
final first = hljs.highlight('/* first line\n', language: 'cpp');
final second = hljs.highlight(
  'second line */ int n = 1;\n',
  language: 'cpp',
  continuation: first.continuation,
);
```

`HighlightContinuation` is an opaque, reusable checkpoint. It retains open modes, callback data, and named embedded-language states.
A checkpoint belongs to its engine and registered language definition. Aliases for that definition work.
Resuming a checkpoint does not mutate it. This supports repeated parses of a partial trailing line.

Continuation does not guarantee that arbitrary chunks match a full parse.
A chunk boundary can divide a token, delimiter, escape, or grammar lookahead.
Even newline boundaries can change colours: JavaScript recognises `hello\n()` as a function call only when both lines are available.
Concatenated HTML also has different span boundaries when a scope spans chunks.
Tests compare scope paths per character instead.

## Validation

From this directory:

```sh
dart pub get
dart test
dart test -p chrome
dart test -p chrome -c dart2wasm
```

The native integration tests use the highlight.js 11 fixtures in `vendor/highlight.js`.
Initialize that submodule from the repository root before the tests.
Browser tests cover the limited registry, continuation, vendor grammar ports, and public streaming benchmarks.

## Reproduce the evaluation

```sh
dart run tool/evaluate.dart --bundle /path/to/hleval --output /tmp/highlight-evaluation
dart run tool/benchmark.dart
# Generate local browser fixtures, without committing private inputs:
dart run tool/evaluate.dart --bundle /path/to/hleval --output build/evaluation --skip-stream --emit-browser-test --emit-browser-stream-test
dart test build/evaluation --platform chrome --compiler dart2js
dart test build/evaluation --platform chrome --compiler dart2wasm
```

The evaluator reads the original bundle locally and writes fresh token runs, detection results, quality comparisons, and streaming timings.
The public benchmark generates its own 20 KB inputs and can compile with dart2js or dart2wasm.
Timing results include worst-chunk duration and scope differences from a full parse.
Do not commit evaluation outputs: they can contain private source text.

## Migration from 0.7.x

- Replace `highlight.parse` with `hljs.highlight`, or `hljs.highlightAuto` for detection.
- Call `ensureInitialized()` when using the default registry.
- Replace `Result.nodes` / `Node` with `HighlightResult.emitter.root` / `DataNode`.
- Replace `parseWithContinuation` and `result.top` with `highlight(..., continuation: ...)` and `result.continuation`.
- Theme `keyword` replaces legacy `meta-keyword`. Many built-in types now use `type`.
- Resolve dotted theme scopes explicitly or fall back to their parent scope.

## License

MIT. Generated grammars retain the upstream highlight.js definitions.
