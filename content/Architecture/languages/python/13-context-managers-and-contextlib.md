---
title: "Python Context Managers and contextlib"
description: "Master deterministic resource management with the with statement, bytecode desugaring, __enter__ and __exit__, the try...finally yield trap in @contextmanager, ExitStack, and async context managers."
tags:
  - architecture
  - languages
  - python
  - context-managers
date: 2026-10-19
aliases:
  - Architecture/languages/python/context-managers-and-contextlib
---

# Python Context Managers and contextlib

Context managers provide deterministic setup and teardown guarantees. They ensure that file descriptors, database connections, distributed locks, and thread pools are cleanly released even when unhandled exceptions occur.

---

## 1. What `with expr as var:` Actually Compiles To

The `with` statement is syntactic sugar for a comprehensive `try...finally` block governed by the **Context Manager Protocol**:

```python
# The Pythonic 'with' syntax:
# with Manager() as resource:
#     do_work(resource)

# Is 100% equivalent to this underlying execution:
_mgr = Manager()
resource = _mgr.__enter__()  # 1. Setup phase: Return value binds to 'as resource'
_exc = True
try:
    try:
        do_work(resource)    # 2. Main execution body
    except:
        _exc = False
        # 3. If an exception occurred, pass (exc_type, exc_val, exc_tb) to __exit__
        # If __exit__ returns True, the exception is suppressed; otherwise re-raised!
        if not _mgr.__exit__(*sys.exc_info()):
            raise
finally:
    # 4. If no exception occurred, call __exit__(None, None, None)
    if _exc:
        _mgr.__exit__(None, None, None)
```

---

## 2. Implementing a Class-Based Context Manager

```python
class DatabaseTransaction:
    def __init__(self, conn_id: str):
        self.conn_id = conn_id

    def __enter__(self):
        print(f"1. [BEGIN] Started transaction on {self.conn_id}")
        return self  # The object returned here is bound to 'as txn'

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            # An error occurred inside the 'with' block!
            print(f"2. [ROLLBACK] Aborting transaction on {self.conn_id} due to: {exc_val}")
            # Returning True suppresses the exception; False allows it to propagate upward!
            return False

        # Normal termination:
        print(f"2. [COMMIT] Successfully committed transaction on {self.conn_id}")
        return True

# Scenario A: Successful operation
with DatabaseTransaction("conn_01") as txn:
    print("   -> Executing balance transfer...")

# Scenario B: Failed operation with automatic rollback
try:
    with DatabaseTransaction("conn_02") as txn:
        print("   -> Executing invalid operation...")
        raise ValueError("Violated uniqueness constraint on user_id!")
except ValueError:
    print("   -> Caught propagated error outside context manager.")
```

---

## 3. Generator Context Managers and the `try...finally` Trap

The `@contextlib.contextmanager` decorator turns a simple generator into a context manager.

> [!WARNING]
> **The Critical `@contextmanager` Bug:**  
> In generator context managers, code before `yield` runs on `__enter__`, and code after `yield` runs on `__exit__`.  
> **You MUST wrap `yield` inside a `try...finally` block!**  
> If an exception occurs inside the user's `with` block, Python injects that exception directly into the generator at the `yield` statement. Without `finally`, code after `yield` will NEVER execute!

```python
import contextlib
import time

# ✅ PRODUCTION PATTERN: Always wrap yield in try...finally!
@contextlib.contextmanager
def execution_timer(operation_name: str):
    start = time.perf_counter()
    print(f"[START] Beginning {operation_name}...")
    try:
        # Code before yield runs on __enter__
        yield start
    finally:
        # Code in finally runs on __exit__ UNCONDITIONALLY (even on errors!)
        elapsed = time.perf_counter() - start
        print(f"[FINISH] {operation_name} finished in {elapsed:.5f}s")

with execution_timer("Allocation Task"):
    _ = [i * 2 for i in range(100_000)]
```

---

## 4. Dynamic Resource Management with `ExitStack`

When you need to acquire an unpredictable number of files, sockets, or locks dynamically at runtime, nested `with` blocks are impossible to write statically. Use `contextlib.ExitStack`:

```python
import contextlib
from pathlib import Path

# Create sample temporary files:
paths = [Path("/tmp/worker_1.log"), Path("/tmp/worker_2.log"), Path("/tmp/worker_3.log")]
for p in paths:
    p.write_text("sample log line\n")

# Dynamically manage all files in a single context:
with contextlib.ExitStack() as stack:
    # stack.enter_context() registers each opened file's __exit__ callback
    open_file_handles = [stack.enter_context(p.open("r")) for p in paths]
    print(f"Successfully opened {len(open_file_handles)} file descriptors.")

    for idx, handle in enumerate(open_file_handles, start=1):
        print(f"File #{idx} content: {handle.read().strip()}")

    # Upon exiting the 'with' block, ExitStack closes all opened handles in clean LIFO order!
```

---

## 5. Async Context Managers (`async with`)

In modern asynchronous architectures (FastAPI, aiohttp, asyncpg), resources like database connection pools and HTTP sessions require async setup and teardown:

```python
import asyncio
import contextlib

@contextlib.asynccontextmanager
async def database_pool_lifespan():
    print("[POOL] Initializing async connection pool to PostgreSQL...")
    await asyncio.sleep(0.01)  # Non-blocking async connection
    pool = {"pool_id": "pg_pool_active"}
    try:
        yield pool
    finally:
        print("[POOL] Draining and closing all async database connections...")
        await asyncio.sleep(0.01)

async def main():
    async with database_pool_lifespan() as pool:
        print(f"Executing query with pool: {pool['pool_id']}")

asyncio.run(main())
```

---

## Next Steps

- [[Architecture/languages/python/14-concurrency-threads-processes-and-gil|14: Concurrency: Threads, Processes, and the GIL]] — Parallelism vs concurrency models.
- [[Architecture/languages/python/18-fastapi-production-middleware-async-db-and-auth|18: FastAPI Production: Lifespan and Async DB]] — Using lifespan context managers in production.
