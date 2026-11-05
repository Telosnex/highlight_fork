# Single-full-parse size benchmark

Opt-in measurement, not a CI timing assertion. Run on the local macOS host with Dart Dart SDK version: 3.13.1 (stable) (Tue Aug 18 01:00:59 2026 -0700) on "macos_arm64". Chrome targets used the installed Google Chrome (156.0.8078.81). Native means the JIT VM (`dart run`), not an AOT release application.

Each cell is p95 **microseconds**, nearest-rank (19th of 20), after 5 warmups per language/size. KB = 1024 UTF-16 units; prefixes stop at the last newline at or below the requested size. Exact unit counts, medians and maxima are in the JSON logs. Construction and truncation are outside the timer; timing includes highlight and its error check, but not flattening.

## Recommendation

- **Web: 4 KB (4096 UTF-16 units)**: the worst public p95 is 2800 µs for dart2js and 3900 µs for dart2wasm; private prefixes also pass. At 8 KB, public JSON reaches 5400/6601 µs and TypeScript 4400/8099 µs (JS/wasm). This is a measured upper bound with very little wasm headroom, not a universal frame guarantee. Consider 2 KB for a conservative default on slower devices. Web cannot move this work to `Isolate.run`; larger blocks need a yielding/incremental strategy or a worker architecture.
- **Native VM: 2 KB (2048 UTF-16 units)**: worst public p95 2899 µs, bundled 2828 µs. At 4 KB public TypeScript is 6097 µs and bundled TypeScript 6265 µs. These are JIT-host measurements: remeasure release AOT on target devices before treating this as a production budget.
- Thresholds use a strict p95 < 4000 µs for the worst language across both corpora and all tested sizes up to the threshold. They apply once per complete block, not per streaming delta.

## Public generated corpus

| Language | KB | Native p95 µs | Chrome JS p95 µs | Chrome wasm p95 µs |
|---|---:|---:|---:|---:|
| cpp | 1 | 1504 | 500 | 900 |
| cpp | 2 | 2126 | 700 | 1000 |
| cpp | 4 | 3825 | 1200 | 1800 |
| cpp | 8 | 8050 | 2101 | 3100 |
| cpp | 16 | 19243 | 4000 | 6099 |
| cpp | 20 | 25923 | 4801 | 7500 |
| dart | 1 | 450 | 300 | 300 |
| dart | 2 | 937 | 401 | 599 |
| dart | 4 | 2049 | 799 | 901 |
| dart | 8 | 4569 | 1400 | 1901 |
| dart | 16 | 10923 | 2800 | 3800 |
| dart | 20 | 14217 | 3500 | 4500 |
| json | 1 | 1001 | 800 | 901 |
| json | 2 | 1812 | 1500 | 1700 |
| json | 4 | 4426 | 2800 | 3300 |
| json | 8 | 11442 | 5400 | 6601 |
| json | 16 | 34628 | 12000 | 13701 |
| json | 20 | 47892 | 13301 | 18000 |
| markdown | 1 | 386 | 201 | 300 |
| markdown | 2 | 865 | 400 | 500 |
| markdown | 4 | 1849 | 700 | 901 |
| markdown | 8 | 3874 | 1300 | 1800 |
| markdown | 16 | 10398 | 2600 | 3700 |
| markdown | 20 | 14635 | 3200 | 4700 |
| python | 1 | 1284 | 201 | 500 |
| python | 2 | 1843 | 401 | 801 |
| python | 4 | 3859 | 801 | 1600 |
| python | 8 | 8178 | 1700 | 3201 |
| python | 16 | 17900 | 3101 | 6300 |
| python | 20 | 24059 | 3901 | 7801 |
| typescript | 1 | 1429 | 601 | 1000 |
| typescript | 2 | 2899 | 1200 | 2100 |
| typescript | 4 | 6097 | 2201 | 3900 |
| typescript | 8 | 14230 | 4400 | 8099 |
| typescript | 16 | 34709 | 9000 | 16299 |
| typescript | 20 | 46817 | 11100 | 20600 |
| yaml | 1 | 633 | 400 | 500 |
| yaml | 2 | 1358 | 700 | 1000 |
| yaml | 4 | 2757 | 1300 | 1901 |
| yaml | 8 | 6800 | 2600 | 3601 |
| yaml | 16 | 17393 | 5000 | 7601 |
| yaml | 20 | 25025 | 6500 | 9299 |

## Private bundled documents (metrics only; no private text)

All seven documents are shorter than 20 KB, so 20 KB is omitted, not padded or repeated.

| Language | KB | Native p95 µs | Chrome JS p95 µs | Chrome wasm p95 µs |
|---|---:|---:|---:|---:|
| cpp | 1 | 863 | 399 | 601 |
| cpp | 2 | 1307 | 500 | 700 |
| cpp | 4 | 2323 | 701 | 1000 |
| cpp | 8 | 5313 | 1301 | 2000 |
| cpp | 16 | 12699 | 2301 | 3801 |
| dart | 1 | 557 | 200 | 201 |
| dart | 2 | 912 | 401 | 399 |
| dart | 4 | 1375 | 500 | 601 |
| dart | 8 | 2813 | 801 | 1000 |
| dart | 16 | 5845 | 1300 | 2000 |
| json | 1 | 905 | 800 | 900 |
| json | 2 | 1454 | 1201 | 1401 |
| json | 4 | 3424 | 2301 | 2800 |
| json | 8 | 8915 | 4700 | 5599 |
| json | 16 | 26124 | 8901 | 11400 |
| markdown | 1 | 350 | 101 | 101 |
| markdown | 2 | 760 | 100 | 101 |
| markdown | 4 | 1591 | 101 | 101 |
| markdown | 8 | 3309 | 200 | 201 |
| markdown | 16 | 6233 | 401 | 500 |
| python | 1 | 782 | 101 | 200 |
| python | 2 | 1577 | 200 | 200 |
| python | 4 | 2817 | 300 | 401 |
| python | 8 | 5478 | 700 | 1100 |
| python | 16 | 11934 | 1500 | 2599 |
| typescript | 1 | 1480 | 500 | 801 |
| typescript | 2 | 2828 | 901 | 1599 |
| typescript | 4 | 6265 | 1701 | 3401 |
| typescript | 8 | 12016 | 3200 | 6199 |
| typescript | 16 | 32114 | 7401 | 15500 |
| yaml | 1 | 333 | 200 | 300 |
| yaml | 2 | 669 | 301 | 500 |
| yaml | 4 | 1479 | 601 | 901 |
| yaml | 8 | 3447 | 1200 | 1700 |
| yaml | 16 | 9013 | 2401 | 3500 |

## Native isolate round trip at 20 KB

Includes `ensureInitialized`, full parse, flattening to plain `[text, scopePath]` runs, and (for isolates) worker creation, transfer and completion. Five warmups then 20 sequential samples per mode; source integrity checked after timing. Isolate initialization happens in each newly spawned isolate. Plain on-thread comparison also flattens; the size tables above do not. Difference of medians is an approximate overhead estimate, not a separately paired spawn-only experiment.

| Language | On-thread median µs | Isolate median µs | Difference µs | On-thread p95 µs | Isolate p95 µs |
|---|---:|---:|---:|---:|---:|
| cpp | 25256.5 | 28142.0 | 2885.5 | 25991 | 28397 |
| dart | 14818.5 | 17876.0 | 3057.5 | 14950 | 20717 |
| json | 49197.0 | 53515.0 | 4318.0 | 50553 | 57971 |
| markdown | 13991.0 | 15819.0 | 1828.0 | 14416 | 16516 |
| python | 23743.0 | 27027.5 | 3284.5 | 23981 | 29062 |
| typescript | 44470.0 | 47960.5 | 3490.5 | 45517 | 48900 |
| yaml | 23656.5 | 26674.5 | 3018.0 | 24521 | 27795 |

Isolates keep parsing off the UI thread but add latency; spawning a new worker for every small block is not free. A persistent worker may amortize initialization, but is not measured here. The private documents have no 20 KB prefix, so no private 20 KB isolate comparison was manufactured.

## Reproduce

From the `highlight/` package directory (run targets sequentially):

```sh
dart format tool/benchmark.dart tool/full_parse_native.dart tool/full_parse_support.dart test/full_parse_benchmark_test.dart
dart analyze --fatal-infos
ps -axo pid,pcpu,command | grep -E "dart|flutter" # check for competing suites
dart run tool/benchmark.dart --full-parse-sizes # public parse-only alternative
dart run tool/full_parse_native.dart > /tmp/highlight-fullparse-native.log
dart run tool/full_parse_native.dart --bundle /tmp/highlight-upgrade-eval/hleval > /tmp/highlight-fullparse-bundled-native.log
dart run tool/full_parse_native.dart --bundle /tmp/highlight-upgrade-eval/hleval --emit-test
for target in js wasm; do
  compiler=dart2$target
  dart test test/full_parse_benchmark_test.dart --run-skipped --platform chrome --compiler "$compiler" --reporter expanded > /tmp/highlight-fullparse-$target.log 2>&1
  dart test build/full_parse/bundled_full_parse_test.dart --platform chrome --compiler "$compiler" --reporter expanded > /tmp/highlight-fullparse-bundled-$target.log 2>&1
done
```

`test/full_parse_benchmark_test.dart` is skipped by default; explicit `--run-skipped` opts in. The shared benchmark is browser-safe and can also be compiled via `dart compile js -DFULL_PARSE_SIZES=true tool/benchmark.dart` or `dart compile wasm -DFULL_PARSE_SIZES=true tool/benchmark.dart`. Generated private test files and helper copies live only in ignored `build/full_parse/`. Never commit that directory.

Timing runs were sequential. `ps` showed no active competing dart/flutter test suites; an existing editor Flutter daemon/frontend and Chrome processes were idle. The concurrent widget-maintenance agent was asked to defer its heavy suite and notified after all six targets completed. No noisy target needed a rerun. Browser stopwatch granularity is visible (~100 µs); these 20-sample p95s are exploratory rather than statistically tight guarantees.
