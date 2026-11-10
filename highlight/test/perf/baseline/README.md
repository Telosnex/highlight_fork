# Baseline engine

A frozen copy of `lib/` at 0.8.0 (commit `63b7615`): the engine and the
grammars that `../full_parse_perf.dart` uses. Do not edit these files. The
perf script compares them with the current `lib/`.

To add a grammar:

```sh
git show 63b7615:highlight/lib/languages/<name>.dart > languages/<name>.dart
```
