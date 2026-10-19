---
title: "Python Asyncio and the Event Loop"
description: "Master asynchronous Python: the event loop architecture, coroutines vs Tasks, structured concurrency with TaskGroup, cancellation mechanics, semaphores, queues, and asyncio.to_thread."
tags:
  - architecture
  - languages
  - python
  - asyncio
date: 2026-10-19
aliases:
  - Architecture/languages/python/asyncio-and-event-loop
---

# Python Asyncio and the Event Loop

`asyncio` provides a high-throughput concurrency model based on **cooperative multitasking**. Rather than letting the operating system pre-empt threads every few milliseconds, coroutines voluntarily yield control back to an **Event Loop** whenever waiting on network I/O, timers, or disk events.

---

## 1. The Event Loop Mental Model

Understanding the event loop lifecycle prevents the most common mistake in async Python: accidentally running sequential code when you thought it was concurrent.

```mermaid
flowchart TD
    subgraph EventLoop["The Asyncio Event Loop"]
        ReadyQueue["Ready Queue\n(Tasks ready to run)"]
        ExecFrame["Run Active Coroutine\n(Until next 'await')"]
        OSSelector["OS Selector (epoll / kqueue)\n(Waiting on network sockets & timers)"]
    end

    ReadyQueue -->|Pop next task| ExecFrame
    ExecFrame -->|Hits 'await socket.read()'| OSSelector
    OSSelector -->|Socket data arrives| ReadyQueue
    ExecFrame -->|Task completed| Done["Task Finished"]
```

1. **The Event Loop** continuously checks the Ready Queue.
2. An active coroutine executes instructions synchronously until it encounters an **`await`** statement waiting on non-blocking I/O.
3. At the `await` statement, the coroutine **suspends its stack frame** and registers its file descriptor with the OS kernel (`epoll` on Linux, `kqueue` on macOS).
4. The loop immediately picks up the next ready task from the queue—zero idle CPU time!

---

## 2. Coroutine Functions vs. Coroutine Objects vs. Tasks

A common source of confusion:

```python
import asyncio

async def fetch_status():
    await asyncio.sleep(0.01)
    return 200

# 1. Calling an 'async def' function DOES NOT run it!
# It merely instantiates a coroutine object:
coro_obj = fetch_status()
print("Type:", type(coro_obj))  # Output: <class 'coroutine'>

# 2. Sequential execution with await:
# 'await coro' runs immediately, pausing the current function until it finishes:
# res = await coro_obj

# 3. Concurrent scheduling with Tasks:
# 'asyncio.create_task()' wraps the coroutine into an asyncio.Task and
# pushes it onto the Event Loop's Ready Queue immediately!
# task = asyncio.create_task(fetch_status())
```

---

## 3. Structured Concurrency: `asyncio.TaskGroup` (Python 3.11+)

Prior to Python 3.11, `asyncio.gather` was standard, but dangerous: if one task raised an unhandled exception, other sibling tasks were left running as "orphaned" background leaks.

`TaskGroup` enforces **Structured Concurrency**:

- All spawned tasks must complete before the `async with` block exits.
- If **any** subtask fails, all other active tasks in the group are **automatically cancelled**.
- Multiple simultaneous errors are wrapped cleanly into an `ExceptionGroup`.

```python
import asyncio

async def fetch_user(user_id: int):
    await asyncio.sleep(0.05)
    print(f"Fetched user {user_id}")
    return f"User_{user_id}"

async def fetch_orders(user_id: int):
    await asyncio.sleep(0.08)
    print(f"Fetched orders for {user_id}")
    return [101, 102]

async def main():
    async with asyncio.TaskGroup() as tg:
        # Both tasks start executing concurrently on the event loop:
        task1 = tg.create_task(fetch_user(42))
        task2 = tg.create_task(fetch_orders(42))

    # Code here runs ONLY after BOTH tasks finish successfully!
    print("User result:", task1.result())
    print("Orders result:", task2.result())

asyncio.run(main())
```

---

## 4. Task Cancellation Mechanics

When a task is cancelled, the event loop injects an `asyncio.CancelledError` into the coroutine at its current `await` point:

```python
import asyncio

async def long_poll_worker():
    try:
        while True:
            print("[WORKER] Polling upstream server...")
            await asyncio.sleep(1.0)
    except asyncio.CancelledError:
        # Crucial: Perform cleanup before allowing the cancellation to propagate!
        print("[WORKER] Cancellation received! Cleaning up open connection...")
        raise  # Re-raise CancelledError to let the task manager know it shut down cleanly

async def main():
    task = asyncio.create_task(long_poll_worker())
    await asyncio.sleep(0.05)  # Let worker run briefly
    task.cancel()              # Request cancellation
    try:
        await task
    except asyncio.CancelledError:
        print("[MAIN] Worker task has confirmed termination.")

asyncio.run(main())
```

> [!NOTE]
> Since Python 3.8, `asyncio.CancelledError` inherits from `BaseException`, not `Exception`. This prevents standard `except Exception:` blocks from accidentally swallowing cancellation signals and creating zombie tasks!

---

## 5. Rate Limiting with `asyncio.Semaphore`

When making thousands of concurrent outbound API calls, prevent connection pool exhaustion and HTTP 429 rate limits with an `asyncio.Semaphore`:

```python
import asyncio

async def fetch_url(sem: asyncio.Semaphore, url_id: int):
    async with sem:
        # At most 3 coroutines are permitted inside this block at any given time
        print(f"-> Starting download #{url_id}")
        await asyncio.sleep(0.05)
        print(f"<- Finished download #{url_id}")
        return f"payload_{url_id}"

async def main():
    rate_limiter = asyncio.Semaphore(3)  # Maximum 3 concurrent in-flight requests

    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(fetch_url(rate_limiter, i)) for i in range(6)]

    results = [t.result() for t in tasks]
    print("All downloads complete:", len(results))

asyncio.run(main())
```

---

## 6. Safe Offloading of Blocking Code with `asyncio.to_thread`

> [!WARNING]
> **The #1 Asyncio Disaster:**  
> Never call synchronous blocking functions (like `time.sleep()`, standard `requests.get()`, or legacy DB drivers) directly inside an `async def` function!  
> Because Python runs on a single thread, **one blocking call freezes the entire event loop**, pausing all other concurrent requests for every connected client!

Use `asyncio.to_thread` to push blocking operations to an internal background worker threadpool:

```python
import asyncio
import time

def legacy_sync_hash(data: str) -> str:
    # Simulates synchronous blocking CPU or disk operation
    time.sleep(0.2)
    return f"hashed_{data}"

async def handle_request(req_id: int):
    print(f"Handling request #{req_id}...")
    # Safely offload to threadpool without freezing other async requests:
    result = await asyncio.to_thread(legacy_sync_hash, f"input_{req_id}")
    print(f"Request #{req_id} completed: {result}")

async def main():
    # Both requests execute concurrently without blocking each other:
    async with asyncio.TaskGroup() as tg:
        tg.create_task(handle_request(1))
        tg.create_task(handle_request(2))

asyncio.run(main())
```

---

## Next Steps

- [[Architecture/languages/python/16-pydantic-v2-validation-and-settings|16: Pydantic v2 Validation and Settings]] — High-performance Rust-backed data modeling.
- [[Architecture/languages/python/17-fastapi-foundations-and-dependency-injection|17: FastAPI Foundations and Dependency Injection]] — Building async REST APIs.
