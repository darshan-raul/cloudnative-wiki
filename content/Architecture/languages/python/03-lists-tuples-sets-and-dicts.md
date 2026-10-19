---
title: "Python Lists, Tuples, Sets, and Dictionaries"
description: "Master Python's core collections: dynamic array over-allocation, immutable tuples, hash-based sets, compact dict internals, time complexity, and collections module helpers."
tags:
  - architecture
  - languages
  - python
  - data-structures
date: 2026-10-19
aliases:
  - Architecture/languages/python/lists-tuples-sets-and-dicts
---

# Python Lists, Tuples, Sets, and Dictionaries

To write high-performance Python services that scale under load, you must understand how Python's built-in collections manage memory under the hood.

---

## 1. Asymptotic Complexity Reference

| Collection  | Operation                                 | Average Complexity | Worst-Case Complexity    | Memory Overhead                                           |
| :---------- | :---------------------------------------- | :----------------- | :----------------------- | :-------------------------------------------------------- |
| **`list`**  | Index lookup (`arr[i]`)                   | $O(1)$             | $O(1)$                   | Contiguous pointer array (dynamic over-allocation)        |
| **`list`**  | Append right (`arr.append(x)`)            | $O(1)$ amortized   | $O(n)$ when resizing     | Resizes by factor $\approx 1.125$ to amortize allocations |
| **`list`**  | Insert/Delete middle (`arr.insert(0, x)`) | $O(n)$             | $O(n)$                   | Shifts all subsequent elements in memory                  |
| **`tuple`** | Index lookup (`tup[i]`)                   | $O(1)$             | $O(1)$                   | Immutable fixed-size contiguous array (minimal RAM)       |
| **`set`**   | Membership test (`x in s`)                | $O(1)$             | $O(n)$ on hash collision | Hash table (keys only, no values)                         |
| **`dict`**  | Key lookup / insertion (`d[k]`)           | $O(1)$             | $O(n)$ on hash collision | Compact hash table (preserves insertion order)            |

---

## 2. Lists: Dynamic Arrays and Slicing Mechanics

A Python `list` is a contiguous array of pointers to `PyObject*` instances. When elements are appended, CPython over-allocates extra capacity to prevent reallocating memory on every single append:

```python
import sys

# Watch CPython list over-allocation in real time:
dynamic_list = []
prev_size = sys.getsizeof(dynamic_list)
print(f"Empty list initial size: {prev_size} bytes")

for i in range(10):
    dynamic_list.append(i)
    current_size = sys.getsizeof(dynamic_list)
    if current_size != prev_size:
        print(f"Appended item {i:2d}: List resized from {prev_size} to {current_size} bytes (holds {len(dynamic_list)} items)")
        prev_size = current_size

# Slicing Mechanics: [start:stop:step]
# Slicing a list creates a brand-new list shallow copy!
items = [10, 20, 30, 40, 50, 60]
print("Slice [1:4]:", items[1:4])          # Output: [20, 30, 40]
print("Every 2nd element [::2]:", items[::2])  # Output: [10, 30, 50]
print("Reversed list [::-1]:", items[::-1])    # Output: [60, 50, 40, 30, 20, 10]

# Shallow vs Deep Copy Trap:
import copy
nested_original = [["node-1", "active"], ["node-2", "standby"]]
shallow_copied = list(nested_original)  # Creates new outer list, but shares inner lists!
deep_copied = copy.deepcopy(nested_original)  # Recursively clones all nested objects

nested_original[0][1] = "DOWN"
print("Shallow copy mutated:", shallow_copied[0])  # Output: ['node-1', 'DOWN'] (unintended mutation!)
print("Deep copy preserved:", deep_copied[0])      # Output: ['node-1', 'active'] (isolated)
```

---

## 3. Tuples and `namedtuple`

Tuples are fixed-size and immutable. Because Python knows a tuple's length can never change, it allocates exact memory and uses internal freelists to recycle small deallocated tuples:

```python
from collections import namedtuple
import sys

# Memory comparison: Tuple vs List
sample_tuple = (1, 2, 3, 4, 5)
sample_list = [1, 2, 3, 4, 5]

print("Tuple size:", sys.getsizeof(sample_tuple), "bytes")  # Output: 80 bytes
print("List size: ", sys.getsizeof(sample_list), "bytes")   # Output: 104 bytes

# Namedtuple: Readable, self-documenting lightweight record
# Has zero extra memory overhead compared to a plain tuple!
ClusterNode = namedtuple("ClusterNode", ["hostname", "ip_address", "cpu_cores"])
node = ClusterNode("k8s-worker-01", "10.0.1.5", 16)

# Access by attribute name or by index:
print(f"Node: {node.hostname} ({node.ip_address}) with {node.cpu_cores} cores")
print(f"Index access: {node[0]}")
```

---

## 4. Sets: Hash Tables for $O(1)$ Deduplication & Set Algebra

Sets use hash tables where only keys are stored. Testing `item in my_set` computes `hash(item)` to jump directly to the memory bucket:

```python
# Comparing membership test speed: List vs Set
large_list = list(range(100_000))
large_set = set(large_list)

# Checking '99_999 in large_list' takes O(n) = 100,000 steps
# Checking '99_999 in large_set' takes O(1) = 1 step!

# Set Algebra in Production Workflows:
prod_nodes = {"node-1", "node-2", "node-3"}
canary_nodes = {"node-3", "node-4"}

print("Union (|):", prod_nodes | canary_nodes)
# Output: {'node-1', 'node-2', 'node-3', 'node-4'} (all unique nodes)

print("Intersection (&):", prod_nodes & canary_nodes)
# Output: {'node-3'} (nodes running both roles)

print("Difference (-):", prod_nodes - canary_nodes)
# Output: {'node-1', 'node-2'} (pure prod nodes)

print("Symmetric Difference (^):", prod_nodes ^ canary_nodes)
# Output: {'node-1', 'node-2', 'node-4'} (in either set, but not both)
```

---

## 5. Dictionaries and the `collections` Module

Since Python 3.7, dictionaries are **compact and order-preserving**. They split storage into an `indices` array and an `entries` array, saving 25% RAM compared to legacy versions:

```python
from collections import Counter, defaultdict

# 1. Safe access with .get() vs .setdefault()
config = {"host": "localhost"}
print("Get with fallback:", config.get("port", 8080))  # Output: 8080 (dict unchanged)

# .setdefault() inserts the default if the key is missing:
config.setdefault("timeout", 30)
print("Config after setdefault:", config)  # Output: {'host': 'localhost', 'timeout': 30}

# 2. defaultdict: Eliminates boilerplate KeyError checks
# Grouping elements into lists automatically:
logs_by_level = defaultdict(list)
events = [("INFO", "boot"), ("ERROR", "timeout"), ("INFO", "ready"), ("ERROR", "crash")]

for level, message in events:
    logs_by_level[level].append(message)  # No need for 'if level not in logs:'!

print("Errors:", logs_by_level["ERROR"])  # Output: ['timeout', 'crash']

# 3. Counter: High-performance frequency aggregation
status_codes = [200, 200, 404, 500, 200, 404, 200, 503, 200]
code_counts = Counter(status_codes)

print("Status 200 hits:", code_counts[200])  # Output: 5
print("Top 2 errors/codes:", code_counts.most_common(2))  # Output: [(200, 5), (404, 2)]
```

---

## Next Steps

- [[Architecture/languages/python/04-comprehensions-iterables-and-builtin-funcs|04: Comprehensions, Iterables, and Built-in Functions]] — Declarative transforms and functional tools.
- [[Architecture/languages/python/08-classes-oop-and-dunder-methods|08: Classes, OOP, and Dunder Methods]] — Object-oriented architecture and hash contracts.
