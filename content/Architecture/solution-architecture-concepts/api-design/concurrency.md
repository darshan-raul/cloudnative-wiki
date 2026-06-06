---
title: Concurrency
tags: [architecture, systems, parallelism]
date: 2025-05-24
description: Concurrency models, patterns, and primitives for distributed systems
---

# Concurrency

Concurrency = **dealing with lots of things at once** (not necessarily doing lots of things at once). Critical for high-throughput systems.

---

## ELI5

```
Sequential:   You wash dishes, then dry dishes, then put away.
              Total: 30 min.

Concurrent:   You wash plate1 → hand to dryer →
 wash plate 2 → hand to dryer →
              overlap the work.
              Total: 20 min.

Parallel:     You wash dishes, your partner dries, your kid puts away.
              Total: 10 min.
              (requires multiple CPU cores)
```

---

## Concurrency vs Parallelism

| Dimension | Concurrency | Parallelism |
|-----------|-------------|-------------|
| Definition | Structuring to handle multiple tasks at once | Executing multiple tasks simultaneously |
| CPU requirement | 1 core enough | Multiple cores required |
| Goal | Responsiveness, throughput | Raw speed |
| Example | Async I/O, event loops | GPU compute, multiprocessing |
| Python | `asyncio` | `multiprocessing`, `threading` |
| Go | Goroutines (goroutines are concurrent) | GOMAXPROCS > 1 |

---

## Concurrency Models

### 1. Threads and Locks

```
Thread 1 ──▶  acquire(lock) ──▶ critical section ──▶ release(lock)
Thread 2 ───────────▶ blocked ──────────────────────────▶ critical section
```

**Problem:** Deadlocks, race conditions, hard to reason about.

```python
import threading

counter = 0
lock = threading.Lock()

def increment():
    global counter
    with lock:  # critical section
        counter += 1  # not atomic without lock
```

### 2. Actor Model

Each actor has its own state, communicates via messages.

```
Actor: mailbox ──▶ process(message) ──▶ state update
           ▲
           │
 messages │
 │
Actor: mailbox ──▶ process(message) ──▶ state update
```

**No shared state** — no locks needed. Examples: Erlang, Akka.

```python
# Erlang-style (pseudo)
def order_actor():
    state = {"orders": []}
    while True:
        msg = receive()
        if msg.type == "add_order":
            state["orders"].append(msg.order)
        elif msg.type == "get_orders":
            reply(state["orders"])
```

### 3. CSP (Communicating Sequential Processes)

Channels pass messages between goroutines / coroutines.

```go
// Go
ch := make(chan Order, 10)

go func() {
    for order := range ch {
        process(order)
    }
}()

ch <- Order{ID: "ord-1"}  // non-blocking send
```

### 4. Async / Event Loop

Single thread, event-driven, non-blocking I/O.

```python
import asyncio

async def fetch_user(user_id: int) -> dict:
    async with aiohttp.ClientSession() as session:
        async with session.get(f"/users/{user_id}") as resp:
            return await resp.json()

async def main():
    # Run concurrently — single thread
    users = await asyncio.gather(
        fetch_user(1),
        fetch_user(2),
        fetch_user(3),
    )
```

---

## Key Primitives

### Mutex / Lock
Mutual exclusion — only one thread in critical section.

### Semaphore
N concurrent accesses allowed.

```python
import threading

semaphore = threading.Semaphore(3)  # 3 concurrent connections

def make_request():
    with semaphore:
        # only 3 threads here at once
        return http.get("/expensive-endpoint")
```

### Condition Variable
Wait for a predicate to become true.

### Atomic Operations
Lock-free operations on primitive types.

```python
# Python
from atomiclong import AtomicLong
counter = AtomicLong(0)
counter.increment()  # thread-safe, no lock
```

### Channels
Synchronous or buffered message passing.

---

## Concurrency Problems

| Problem | What It Is | Solution |
|---------|-----------|---------|
| **Deadlock** | Threads waiting on each other forever | Lock ordering, timeouts |
| **Livelock** | Threads actively running but making no progress | Random backoff |
| **Race condition** | Outcome depends on timing | Atomic ops, locks, actors |
| **Starvation** | Thread never gets CPU time | Fair schedulers |
| **Priority inversion** | Low-priority thread holds lock that high-priority thread needs | Priority inheritance |

---

## Distributed Concurrency

In distributed systems, you don't have shared memory — you have **distributed coordination**.

### Distributed Locks

```python
# Redis-based distributed lock
import redis, time

def acquire_lock(lock_name, ttl=10):
    return redis.set(f"lock:{lock_name}", "1", nx=True, ex=ttl)

def release_lock(lock_name):
    redis.delete(f"lock:{lock_name}")

# Usage
if acquire_lock("payment:ord-123"):
    try:
        process_payment("ord-123")
    finally:
        release_lock("payment:ord-123")
```

### Leader Election

```python
# etcd / Consul leader election
# Only one instance becomes leader at a time
# Others watch and take over on failure
```

### Two-Phase Commit (2PC)

```
Phase 1 (Prepare): Coordinator asks all nodes: "can you commit?"
                    Nodes vote YES/NO, hold locks
Phase 2 (Commit):   If all YES → send commit
 If any NO → send rollback
```

2PC is rarely used in practice (too slow, blocks on coordinator failure) — Raft/Paxos are preferred.

---

## Go vs Python Concurrency

| Feature | Go | Python |
|---------|----|--------|
| Model | Goroutines + channels | asyncio + coroutines |
| Parallelism | GOMAXPROCS (real parallelism) | multiprocessing |
| Memory sharing | Share memory by communicating | Communicate via shared memory |
| Cancellation | Context propagation | asyncio.CancelledError |
| Blocking I/O | Non-blocking via channels | Native async/await |

---

## Quick Checklist

```
□ External calls have timeouts
□ Critical sections protected by locks or atomic ops
□ Distributed locks use a lock manager (Redis/etcd)
□ Leader election for active-passive components
□ Idempotency keys for all retry-able operations
□ Circuit breakers to prevent cascading failures
□ Back-pressure to prevent overload (producer throttling)
```

---

## Source

- [A Journey in Synchronous Concurrent Burgers](https://fastapi.tiangolo.com/async/#concurrent-burgers) (great intro)
- [Go Concurrency Patterns — Google](https://go.dev/tour/concurrency)
- [The Actor Model in 10 Minutes](https://www.b稟w.com/actor-model)
