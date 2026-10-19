---
title: "Synchronous vs Asynchronous Programming (async/await)"
description: "Blocking vs non-blocking I/O, the restaurant buzzer analogy, why web servers use async, and how async/await works in practice."
tags:
  - architecture
  - programming-concepts
  - async
  - concurrency
  - event-loop
date: 2026-10-19
---

# Synchronous vs Asynchronous Programming (async/await) ⏱️

When building backend services and APIs, your code spends most of its time **waiting**: waiting for a PostgreSQL query to return, waiting for an external payment API (Stripe), or reading a file from disk.

How your code handles this waiting time determines whether your server can handle **100 requests per second or 50,000 requests per second**.

---

## 1. The Real-World Analogy: The Coffee Shop

Imagine ordering coffee at a busy café:

### Synchronous (Blocking)

1. You step up to the counter and order a latte.
2. The barista stops everything and begins steaming milk.
3. **The line behind you freezes.** Nobody else can order or pay until your cup is in your hand.
4. If your latte takes 3 minutes, 10 people behind you wait 30 minutes total!

### Asynchronous (Non-Blocking)

1. You step up to the counter and order a latte.
2. The cashier gives you a **buzzer (a Promise / Future)** and says _"We'll buzz you when it's ready."_
3. You step aside to wait. The cashier **immediately serves the next customer in line**.
4. When your buzzer vibrates, you walk over and pick up your cup (**Callback / `await`**).

```
SYNCHRONOUS (Blocking):
Thread ──▶ [ Handle Req 1: Wait 50ms for DB... ] ──▶ [ Handle Req 2: Wait 50ms for DB... ]
Total time for 2 requests = 100ms

ASYNCHRONOUS (Non-Blocking):
Thread ──▶ [ Start Req 1 DB Query ] ──▶ [ Start Req 2 DB Query ] ──▶ [ Both DB queries running in parallel! ]
Total time for 2 requests = ~50ms
```

---

## 2. The Code: `async` and `await`

Modern languages (Python, JavaScript/TypeScript, C#, Rust) provide **`async` / `await`** syntax, which makes asynchronous code look as readable as normal sequential code:

```python
import asyncio
import httpx

# An async function returns a coroutine (the buzzer)
async def fetch_weather(city):
    print(f"Requesting weather for {city}...")
    async with httpx.AsyncClient() as client:
        # 'await' yields control back so other tasks can run while waiting for the network!
        response = await client.get(f"https://api.example.com/weather/{city}")
        return response.json()

async def main():
    # Fetch 3 cities concurrently in a single thread!
    results = await asyncio.gather(
        fetch_weather("Tokyo"),
        fetch_weather("London"),
        fetch_weather("New York"),
    )
    print("All weather reports received!")

asyncio.run(main())
```

---

## 3. I/O-Bound vs CPU-Bound Tasks

Async programming is not a magic wand for all performance problems. You must distinguish between two types of work:

| Work Type     | What It Does                                          | Best Approach                        | Example                                                     |
| :------------ | :---------------------------------------------------- | :----------------------------------- | :---------------------------------------------------------- |
| **I/O-Bound** | Waiting on external devices (network, disk, database) | **Async / Event Loop / Goroutines**  | Fetching data from DB, calling Stripe API, reading S3 files |
| **CPU-Bound** | Heavy math, cryptography, parsing, image processing   | **Multiprocessing / Worker Threads** | Resizing an image, hashing passwords, training an ML model  |

> **Crucial Warning:** Running a heavy CPU-bound loop inside an `async` function (like calculating a million fibonacci numbers) **blocks the entire event loop thread**. All other connected users freeze until that calculation finishes!

---

## 4. How Go Takes a Different Approach (Goroutines)

In Python and JavaScript, you have to carefully mark functions as `async` and remember to write `await`.

**Go** takes a simpler architectural approach:

- Every function is written as normal, sequential code (no `async` or `await` keywords!).
- When you want to run something concurrently, you simply put the word `go` in front of it: `go fetchWeather("Tokyo")`.
- The Go runtime automatically parks the goroutine when it waits on network I/O and wakes it up when data arrives, without blocking the underlying OS thread.

---

## Across the Wiki

- [[Architecture/programming-concepts/processes-threads-and-coroutines|Processes vs Threads vs Coroutines]] — How operating systems and runtimes schedule concurrent work.
- [[Architecture/solution-architecture-concepts/api-design/concurrency|Concurrency Patterns]] — Concurrency vs parallelism and distributed coordination.
- [[Architecture/languages/golang/channels|Go Channels & Goroutines]] — Go's CSP concurrency model.
