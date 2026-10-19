---
title: "Python Concurrency: Threads, Processes, and the GIL"
description: "Master Python concurrency: CPU vs I/O workloads, why the GIL does NOT prevent race conditions, bytecode disassembly of counter += 1, threading.Lock, and multiprocessing IPC."
tags:
  - architecture
  - languages
  - python
  - concurrency
date: 2026-10-19
aliases:
  - Architecture/languages/python/concurrency-threads-processes-and-gil
---

# Python Concurrency: Threads, Processes, and the GIL

Concurrency in Python is frequently misunderstood. Developers often assume that because Python has a **Global Interpreter Lock (GIL)**, multi-threaded code is automatically safe from race conditions, or that threads are useless. Both assumptions are dangerously wrong.

---

## 1. Concurrency Model Decision Matrix

| Model                 | Mechanism                                 | Best Suited For                                    | Multi-Core Scaling                              | Primary Trade-Off                                   |
| :-------------------- | :---------------------------------------- | :------------------------------------------------- | :---------------------------------------------- | :-------------------------------------------------- |
| **`threading`**       | Native OS threads sharing one memory heap | I/O-bound tasks (HTTP calls, DB queries, disk I/O) | ❌ Restricted to 1 CPU core for Python bytecode | Race conditions on shared mutable memory            |
| **`multiprocessing`** | Separate OS processes with isolated heaps | CPU-bound computation (ML, data parsing, crypto)   | ✅ Full multi-core CPU parallelism              | Memory overhead & `pickle` serialization IPC cost   |
| **`asyncio`**         | Single thread cooperative event loop      | Massive concurrent I/O (10,000+ web requests)      | ❌ Single thread / single core                  | Cooperative (blocking CPU code freezes entire loop) |

---

## 2. What the GIL Actually Does (and Doesn't Do)

In CPython, memory is managed via reference counting. If two OS threads modify an object's reference counter simultaneously, memory would leak or be deallocated prematurely. The **Global Interpreter Lock (GIL)** is a mutual-exclusion lock that ensures **only one native thread executes Python bytecode at any given moment**.

### How Thread Switching Works:

CPython switches active threads in two scenarios:

1. **Voluntary I/O Release:** Whenever a thread performs network I/O, file reading, or sleep (`time.sleep()`), CPython immediately **releases the GIL**, allowing another thread to execute.
2. **Preemptive Bytecode Ticks:** If a thread is running CPU-bound Python code without I/O, CPython pauses it every **`5ms`** (configurable via `sys.getswitchinterval()`), forcing a GIL release.

---

## 3. 💥 The Great Myth: "The GIL Makes Code Thread-Safe"

> [!WARNING]
> **The GIL protects CPython interpreter memory, NOT your application state!**  
> Simple Python statements like `counter += 1` are **NOT atomic**.

### Proof with Bytecode Disassembly (`dis.dis`):

```python
import dis

def increment(counter: int):
    counter += 1

dis.dis(increment)
```

Look at the generated CPython bytecode:

```text
  1           0 LOAD_FAST                0 (counter)
              2 LOAD_CONST               1 (1)
              4 BINARY_OP                0 (+)
              8 STORE_FAST               0 (counter)
             10 RETURN_VALUE
```

Notice that `counter += 1` is **4 distinct bytecode operations**! If Thread A loads the counter (say, value `5`) and the GIL switches to Thread B before Thread A executes `STORE_FAST`, Thread B also reads `5`. Both threads write back `6`, losing an update!

### Demonstrating the Race Condition and the `Lock` Solution:

```python
import threading
import time

shared_counter = 0
counter_lock = threading.Lock()

# 💥 UNPROTECTED: Loses updates due to thread preemption!
def unsafe_worker():
    global shared_counter
    for _ in range(100_000):
        shared_counter += 1

# ✅ PROTECTED: Uses explicit mutex lock
def safe_worker():
    global shared_counter
    for _ in range(100_000):
        with counter_lock:
            shared_counter += 1

# Run 10 concurrent threads:
threads = [threading.Thread(target=safe_worker) for _ in range(10)]
for t in threads: t.start()
for t in threads: t.join()

print("Final Counter (Expected 1,000,000):", shared_counter)
# With safe_worker: exactly 1,000,000!
# With unsafe_worker: typically ~620,000 (huge data loss!)
```

---

## 4. Multiprocessing: True Multi-Core Parallelism

To perform CPU-intensive data transformations or encryption across all available CPU cores, bypass the GIL using `concurrent.futures.ProcessPoolExecutor`:

```python
import concurrent.futures
import hashlib
import time

def compute_sha256(batch_id: int) -> str:
    # CPU-bound hashing workload running on a separate OS process
    hasher = hashlib.sha256()
    for i in range(500_000):
        hasher.update(f"item_{batch_id}_{i}".encode())
    return hasher.hexdigest()[:16]

if __name__ == "__main__":
    start_time = time.perf_counter()
    batch_ids = list(range(8))

    # Spawns worker processes matching machine CPU core count:
    with concurrent.futures.ProcessPoolExecutor() as executor:
        results = list(executor.map(compute_sha256, batch_ids))

    print(f"Computed 8 heavy hashes across CPU cores in {time.perf_counter() - start_time:.2f}s")
    print("Sample result:", results[0])
```

### The Cost of Multiprocessing: Pickling Overhead

`multiprocessing` communicates between parent and child processes by serializing data via **`pickle`** through OS pipes or shared memory. If your worker accepts a 2GB dataframe, serializing and deserializing that payload across process boundaries can take longer than the computation itself!

---

## Next Steps

- [[Architecture/languages/python/15-asyncio-and-event-loop|15: Asyncio and the Event Loop]] — Single-threaded cooperative multitasking.
- [[Architecture/languages/python/23-profiling-optimization-and-c-extensions|23: Profiling, Optimization, and C Extensions]] — Profiling threads and Python 3.13 free-threading.
