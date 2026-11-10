// Sources for full_parse_perf.dart. Written for this benchmark: no private
// or third-party text.

/// Repeats [seed] up to [units] UTF-16 units and stops at a line end.
String sized(String seed, int units) {
  final out = StringBuffer();
  while (out.length < units) {
    out.write(seed);
  }
  final text = out.toString();
  return text.substring(0, text.lastIndexOf('\n', units - 1) + 1);
}

/// A JSON document of [units] UTF-16 units in which most of the text is long
/// string values with escapes, as in a saved API request.
String longStringJson(int units) {
  const prose =
      'The parser reads the next line.\\nIt keeps a \\"checkpoint\\" for '
      'each completed line,\\tthen continues. Path: C:\\\\tmp\\\\out.json. ';
  final out = StringBuffer('{\n  "messages": [\n');
  for (var i = 0; out.length < units; i++) {
    out.write('    {"role": "user", "index": $i, "cached": false, "text": "');
    for (var n = 0; n < 2 + i % 30; n++) {
      out.write(prose);
    }
    out.write('"},\n');
  }
  out.write('    {"role": "assistant", "text": null}\n  ]\n}\n');
  return out.toString();
}

const corpus = <String, String>{
  'cpp': r'''
#include <algorithm>
#include <memory>
#include <string>
#include <vector>

namespace cache {

/// Least-recently-used cache with a fixed capacity.
template <typename Key, typename Value>
class LruCache {
 public:
  explicit LruCache(std::size_t capacity) : capacity_(capacity) {}

  const Value* find(const Key& key) const {
    auto it = std::find_if(items_.begin(), items_.end(),
                           [&](const auto& item) { return item.first == key; });
    return it == items_.end() ? nullptr : &it->second;
  }

  void insert(Key key, Value value) {
    if (items_.size() >= capacity_) {
      items_.erase(items_.begin());  // drop the oldest entry
    }
    items_.emplace_back(std::move(key), std::move(value));
  }

  [[nodiscard]] std::size_t size() const noexcept { return items_.size(); }

 private:
  std::size_t capacity_;
  std::vector<std::pair<Key, Value>> items_;
};

}  // namespace cache

int main(int argc, char** argv) {
  cache::LruCache<std::string, int> counts(128);
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (const int* seen = counts.find(arg); seen != nullptr) {
      counts.insert(arg, *seen + 1);
    } else {
      counts.insert(arg, 1);
    }
  }
  /* Exit status is the number of distinct arguments, capped at 0x7f. */
  return static_cast<int>(std::min<std::size_t>(counts.size(), 0x7f));
}
''',
  'dart': r'''
import 'dart:async';
import 'dart:convert';

/// A retry policy with exponential backoff.
///
/// The delay doubles after each attempt, up to [maxDelay].
class RetryPolicy {
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;

  const RetryPolicy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 30),
  });

  Duration delayFor(int attempt) {
    final ms = initialDelay.inMilliseconds * (1 << attempt);
    return ms > maxDelay.inMilliseconds ? maxDelay : Duration(milliseconds: ms);
  }
}

Future<T> retry<T>(
  Future<T> Function() action, {
  RetryPolicy policy = const RetryPolicy(),
  bool Function(Object error)? retryIf,
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await action();
    } on TimeoutException catch (error, stack) {
      if (attempt + 1 >= policy.maxAttempts) {
        Error.throwWithStackTrace(error, stack);
      }
      print('attempt ${attempt + 1} timed out; next in ${policy.delayFor(attempt)}');
    } catch (error) {
      if (retryIf != null && !retryIf(error)) rethrow;
      if (attempt + 1 >= policy.maxAttempts) rethrow;
    }
    await Future<void>.delayed(policy.delayFor(attempt));
  }
}

void main(List<String> args) async {
  final body = await retry(() async => jsonEncode({'args': args, 'pi': 3.14159}));
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  // Print each key with its runtime type.
  for (final MapEntry(:key, :value) in decoded.entries) {
    print("$key: ${value.runtimeType} = '$value'");
  }
}
''',
  'json': r'''
{
  "name": "example-service",
  "version": "2.14.0",
  "private": true,
  "description": "A service that shows nested objects, arrays and escapes.",
  "scripts": {
    "build": "tsc --project tsconfig.json",
    "test": "vitest run --coverage",
    "lint": "eslint \"src/**/*.ts\" --max-warnings 0"
  },
  "dependencies": {
    "fastify": "^5.1.0",
    "pino": "^9.5.0",
    "zod": "^3.23.8"
  },
  "limits": {
    "maxBodyBytes": 1048576,
    "timeoutSeconds": 30.5,
    "retries": [1, 2, 4, 8, 16],
    "enabled": true,
    "fallback": null
  },
  "routes": [
    {"path": "/health", "method": "GET", "auth": false, "weight": 0.1},
    {"path": "/items/:id", "method": "GET", "auth": true, "weight": 2.5},
    {"path": "/items", "method": "POST", "auth": true, "weight": 4e2},
    {"path": "/search", "method": "GET", "auth": false, "tags": ["a\tb", "c\u00e9"]}
  ]
}
''',
  'markdown': r'''
# Release notes

The **2.14** release changes the cache and adds a _retry policy_.
See the [migration guide](https://example.test/docs/migrate) for details.

## Changes

- Replace the LRU cache with a `LinkedHashMap`.
- Add `RetryPolicy` with exponential backoff.
  - The default is 5 attempts.
  - The maximum delay is 30 seconds.
- Remove the deprecated `fetchAll()` function.

1. Update the dependency.
2. Run the tests.
3. Deploy to staging.

> Note: the cache size is now in entries, not in bytes.

```dart
final policy = RetryPolicy(maxAttempts: 3);
await retry(() => client.get(url), policy: policy);
```

| Setting | Default | Unit |
|---|---:|---|
| `maxAttempts` | 5 | attempts |
| `maxDelay` | 30 | seconds |

Inline HTML such as <kbd>Ctrl</kbd>+<kbd>C</kbd> is also possible.

---

### Known issues

The parser does not accept `***nested emphasis***` in all positions.
![diagram](https://example.test/img/cache.png "Cache layout")
''',
  'python': r'''
"""Retry helpers with exponential backoff."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from typing import Awaitable, Callable, TypeVar

T = TypeVar("T")
log = logging.getLogger(__name__)


@dataclass(frozen=True)
class RetryPolicy:
    max_attempts: int = 5
    initial_delay: float = 0.2
    max_delay: float = 30.0
    retry_on: tuple[type[BaseException], ...] = field(default=(TimeoutError,))

    def delay_for(self, attempt: int) -> float:
        return min(self.initial_delay * 2**attempt, self.max_delay)


async def retry(action: Callable[[], Awaitable[T]], policy: RetryPolicy | None = None) -> T:
    policy = policy or RetryPolicy()
    for attempt in range(policy.max_attempts):
        try:
            return await action()
        except policy.retry_on as error:
            if attempt + 1 >= policy.max_attempts:
                raise
            delay = policy.delay_for(attempt)
            log.warning(f"attempt {attempt + 1} failed: {error!r}; next in {delay:.1f}s")
            await asyncio.sleep(delay)
    raise RuntimeError("unreachable")


if __name__ == "__main__":
    # Count the words in each argument.
    import sys

    counts = {word: len(word) for word in sys.argv[1:] if not word.startswith("-")}
    for word, size in sorted(counts.items(), key=lambda item: -item[1]):
        print('%-20s %5d 0x%04x' % (word, size, size))
''',
  'typescript': r'''
import { readFile } from 'node:fs/promises';
import type { IncomingMessage, ServerResponse } from 'node:http';

/** A retry policy with exponential backoff. */
export interface RetryPolicy {
  readonly maxAttempts: number;
  readonly initialDelayMs: number;
  readonly maxDelayMs?: number;
}

const DEFAULT_POLICY: RetryPolicy = { maxAttempts: 5, initialDelayMs: 200 };

export class HttpError extends Error {
  constructor(public readonly status: number, message: string) {
    super(`HTTP ${status}: ${message}`);
  }
}

export async function retry<T>(
  action: () => Promise<T>,
  policy: RetryPolicy = DEFAULT_POLICY,
): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await action();
    } catch (error: unknown) {
      const last = attempt + 1 >= policy.maxAttempts;
      if (last || (error instanceof HttpError && error.status < 500)) throw error;
      const delay = Math.min(policy.initialDelayMs * 2 ** attempt, policy.maxDelayMs ?? 30_000);
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }
}

type Handler = (req: IncomingMessage, res: ServerResponse) => void | Promise<void>;

const routes = new Map<string, Handler>([
  ['/health', (_req, res) => res.end('ok')],
  ['/config', async (_req, res) => {
    const text = await retry(() => readFile('./config.json', 'utf8'));
    const keys = Object.keys(JSON.parse(text)).filter((key) => !/^_/.test(key));
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ keys, count: keys.length }));  // only public keys
  }],
]);

export default routes;
''',
  'yaml': r'''
# Deployment for the example service.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-service
  labels:
    app: example
    tier: "backend"
spec:
  replicas: 3
  selector:
    matchLabels: {app: example}
  template:
    metadata:
      annotations:
        checksum/config: 9f86d081884c7d659a2feaa0c55ad015
    spec:
      containers:
        - name: api
          image: registry.example.test/api:2.14.0
          args: ["--port", "8080", "--log-level=info"]
          env:
            - name: MAX_BODY_BYTES
              value: "1048576"
            - name: RETRY_ENABLED
              value: 'true'
          resources:
            limits: {cpu: 500m, memory: 256Mi}
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            periodSeconds: 10
          command:
            - /bin/sh
            - -c
            - |
              echo "starting"
              exec /app/server --config /etc/app/config.yaml
      terminationGracePeriodSeconds: 30
''',
};
