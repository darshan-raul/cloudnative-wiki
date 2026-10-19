---
title: "Python Iterators, Generators, and Itertools"
description: "Master the iterator protocol, bytecode for-loop desugaring, generator stack frame suspension, the single-pass exhaustion trap, and itertools recipes."
tags:
  - architecture
  - languages
  - python
  - functional
date: 2026-10-19
aliases:
  - Architecture/languages/python/iterators-generators-and-itertools
---

# Python Iterators, Generators, and Itertools

Efficient backend systems must process high-volume event streams, gigabyte log files, and database cursors without exhausting memory. Understanding Python's iteration mechanics is the key to achieving $O(1)$ constant-memory streaming pipelines.

---

## 1. What a `for` Loop Actually Does Under the Hood

When you write `for item in sequence:`, Python does not magically iterate over the collection. The compiler translates the loop into a precise while loop driven by the **Iterator Protocol**:

```python
# The Pythonic 'for' loop:
# for item in collection:
#     process(item)

# Is 100% equivalent to this underlying bytecode execution:
iterator = iter(collection)  # Invokes collection.__iter__() to get an iterator object
while True:
    try:
        item = next(iterator)  # Invokes iterator.__next__()
    except StopIteration:
        # Loop terminates when iterator raises StopIteration
        break
    else:
        process(item)
```

### Building a Custom Iterator Class

An **iterable** implements `__iter__()` (returning an iterator). An **iterator** implements both `__iter__()` (returning `self`) and `__next__()` (returning values or raising `StopIteration`):

```python
class ExponentialBackoff:
    """Yields exponential retry delays up to a maximum cap."""
    def __init__(self, base_delay: float = 0.5, factor: float = 2.0, max_retries: int = 4):
        self.current_delay = base_delay
        self.factor = factor
        self.max_retries = max_retries
        self.attempts = 0

    def __iter__(self):
        return self

    def __next__(self) -> float:
        if self.attempts >= self.max_retries:
            raise StopIteration
        delay = self.current_delay
        self.current_delay *= self.factor
        self.attempts += 1
        return delay

# Iterate over our custom backoff schedule:
for retry_delay in ExponentialBackoff():
    print(f"Waiting {retry_delay:.2f}s before next retry...")
# Output:
# Waiting 0.50s before next retry...
# Waiting 1.00s before next retry...
# Waiting 2.00s before next retry...
# Waiting 4.00s before next retry...
```

---

## 2. Generators: Stack Frame Suspension with `yield`

Writing an iterator class with manual state tracking (`self.attempts`, `self.current_delay`) is verbose. A **generator function** accomplishes the exact same behavior using `yield`:

```python
def exponential_backoff_gen(base_delay: float = 0.5, factor: float = 2.0, max_retries: int = 4):
    delay = base_delay
    for _ in range(max_retries):
        yield delay  # Suspends execution and returns value to caller!
        delay *= factor
```

### The Mental Model: How `yield` Works

When a generator yields, CPython **freezes the function's stack frame**, preserving local variables, loop positions, and instruction pointers in heap memory. When `next()` is called again, execution resumes immediately at the instruction following `yield`.

---

## 3. The Single-Pass Exhaustion Trap

A very common bug in production:

> [!WARNING]
> **Generators can only be consumed once!**  
> Once a generator reaches its end, it remains exhausted. Subsequent attempts to iterate over it yield zero items without any warning!

```python
def generate_ids():
    yield "id_101"
    yield "id_102"

ids_stream = generate_ids()

# Pass 1: Prints all items
print("First pass:")
for i in ids_stream:
    print(" -", i)

# Pass 2: Silent failure! The generator is already exhausted!
print("Second pass:")
for i in ids_stream:
    print(" -", i)  # Never executes!

# ✅ Fix: If you need to iterate multiple times, either construct a new generator
# or collect into a list: cached_ids = list(generate_ids())
```

---

## 4. Streaming Pipelines: Processing Gigabytes in $O(1)$ RAM

Chain generators together like Unix command-line pipes (`cat | grep | cut`):

```python
# Raw mock log lines:
raw_log_stream = [
    "2026-10-19T10:00:00Z [INFO] Service started",
    "2026-10-19T10:00:01Z [ERROR] Failed to connect to Redis",
    "2026-10-19T10:00:02Z [DEBUG] Cache miss on user_99",
    "2026-10-19T10:00:03Z [ERROR] PostgreSQL query timeout",
]

# Pipeline Stage 1: Strip whitespace
def stage_strip(lines):
    for line in lines:
        yield line.strip()

# Pipeline Stage 2: Filter error lines only
def stage_filter_errors(lines):
    for line in lines:
        if "[ERROR]" in line:
            yield line

# Pipeline Stage 3: Extract timestamp and message
def stage_parse(lines):
    for line in lines:
        ts, msg = line.split(" [ERROR] ")
        yield {"timestamp": ts, "error": msg}

# Connect stages together:
pipeline = stage_parse(stage_filter_errors(stage_strip(raw_log_stream)))

# Streams element-by-element with ZERO intermediate lists in RAM!
for error_event in pipeline:
    print("Parsed incident:", error_event)
# Output:
# Parsed incident: {'timestamp': '2026-10-19T10:00:01Z', 'error': 'Failed to connect to Redis'}
# Parsed incident: {'timestamp': '2026-10-19T10:00:03Z', 'error': 'PostgreSQL query timeout'}
```

---

## 5. `itertools` and `functools` Production Recipes

```python
import itertools
import functools

# 1. itertools.chain: Concatenates sequences without allocating a new list
combined = itertools.chain([1, 2], [3, 4], [5])
print("Chained items:", list(combined))  # Output: [1, 2, 3, 4, 5]

# 2. itertools.islice: Lazily takes N elements from an infinite generator
def infinite_sequence():
    n = 1
    while True:
        yield n
        n += 1

first_three = list(itertools.islice(infinite_sequence(), 3))
print("Sliced infinite stream:", first_three)  # Output: [1, 2, 3]

# 3. functools.lru_cache: High-performance function memoization
@functools.lru_cache(maxsize=256)
def resolve_tenant_tier(tenant_id: str) -> str:
    print(f"[DB QUERY] Resolving tier for {tenant_id}...")
    return "enterprise" if "ent" in tenant_id else "standard"

print(resolve_tenant_tier("tenant_ent_01"))  # Triggers DB query
print(resolve_tenant_tier("tenant_ent_01"))  # Instant cache hit (no query!)
```

---

## Next Steps

- [[Architecture/languages/python/12-closures-and-decorators|12: Closures and Decorators]] — Higher-order functions and metaprogramming.
- [[Architecture/languages/python/13-context-managers-and-contextlib|13: Context Managers and contextlib]] — Resource cleanup protocols.
