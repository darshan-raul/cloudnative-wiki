---
title: "Processes, Threads & Coroutines (Goroutines)"
description: "Understanding concurrency units — OS processes (separate houses), threads (roommates sharing a house), and lightweight coroutines/goroutines (actors)."
tags:
  - architecture
  - programming-concepts
  - concurrency
  - operating-systems
  - goroutines
date: 2026-10-19
---

# Processes, Threads & Coroutines (Goroutines) 🧵

When an operating system executes code, it organizes work into different units of execution: **Processes**, **Threads**, and user-space **Coroutines (Goroutines / Fibers)**.

Understanding how these units differ in memory, overhead, and communication is fundamental to architecting scalable systems.

---

## 1. The Real-World Analogy: The House & Roommates

```
PROCESS (An Entire House):
  ┌───────────────────────────────────────────────┐
  │ Isolated kitchen, plumbing, power meter.       │
  │ Cannot see into neighboring houses.            │
  │ Very secure, but expensive to build.          │
  └───────────────────────────────────────────────┘

THREADS (Roommates Sharing the House):
  ┌───────────────────────────────────────────────┐
  │ Share the kitchen, living room, and fridge.   │
  │ Communication is instant (just talk in room). │
  │ ⚠️ If someone leaves the stove on, the whole   │
  │    house burns down (shared memory bugs!).     │
  └───────────────────────────────────────────────┘

COROUTINES / GOROUTINES (Cooperative Tasks):
  ┌───────────────────────────────────────────────┐
  │ Lightweight chore-swapping between roommates. │
  │ When roommate A waits for the washer,         │
  │ roommate B steps in to chop vegetables.       │
  └───────────────────────────────────────────────┘
```

---

## 2. Comparing the Three Units

| Dimension            | Process                                   | OS Thread                            | Coroutine / Goroutine                 |
| :------------------- | :---------------------------------------- | :----------------------------------- | :------------------------------------ |
| **Managed By**       | Operating System Kernel                   | Operating System Kernel              | Language Runtime (Go, Python, Node)   |
| **Memory Isolation** | **Total isolation** (own address space)   | **Shared memory** within process     | **Shared memory** within process      |
| **Startup Cost**     | 🐢 Heavy (fork/exec, page tables)         | ⏳ Medium (1–8 MB stack reservation) | ⚡ Ultralight (~2 KB initial stack)   |
| **Context Switch**   | Slow (swapping CPU registers + MMU flush) | Medium (kernel context switch)       | ⚡ Fast (user-space pointer swap)     |
| **Scale Limit**      | Hundreds per machine                      | Thousands per machine                | **Hundreds of thousands** per process |
| **Communication**    | IPC (sockets, pipes, files, gRPC)         | Shared variables + Mutexes/Locks     | Channels (Go), message queues, async  |

---

## 3. Deep Dive on Each Unit

### 1. Process

A **Process** is an independent running instance of a program (e.g., your PostgreSQL server, Python app, or Docker container).

- Has its own dedicated virtual memory space, file descriptors, and security permissions.
- If Process A crashes, **Process B is completely unaffected**.
- Communication between processes requires **Inter-Process Communication (IPC)**—such as TCP sockets, Unix domain sockets, or shared pipes.

### 2. Thread (OS Thread)

A **Thread** is a lightweight path of execution _inside_ a process.

- All threads inside a process share the same heap memory, global variables, and open files.
- **The Concurrency Danger:** Because threads share memory, if Thread 1 writes to a dictionary while Thread 2 is reading it, the program will crash or corrupt data (**Race Condition**). You must protect shared memory with **Locks (Mutexes)**.

### 3. Coroutine / Goroutine (User-Space Threads)

An OS thread is relatively heavy (reserving 2 MB to 8 MB of stack space). Spawning 100,000 OS threads will crash your server with an Out-of-Memory error.

Languages like Go, Erlang, and Java (Project Loom) solve this with **User-Space Fibers / Goroutines**:

- A Goroutine starts with only **2 KB of stack space** that grows and shrinks dynamically.
- The Go runtime multiplexes 100,000 goroutines onto a small pool of OS threads (matching your CPU core count).
- When a goroutine waits on network I/O, the runtime swaps it out and runs another goroutine—with **zero kernel context switch overhead**!

```go
// In Go: Spawning 10,000 concurrent tasks takes only a few megabytes of RAM!
for i := 0; i < 10000; i++ {
    go func(id int) {
        processTask(id)
    }(i)
}
```

---

## Across the Wiki

- [[Architecture/programming-concepts/sync-vs-async-programming|Sync vs Async Programming]] — Coordinating non-blocking work.
- [[Architecture/solution-architecture-concepts/api-design/concurrency|Concurrency Models]] — Threads, locks, actors, and CSP.
- [[Architecture/languages/golang/channels|Go Channels]] — Communicating safely between goroutines without shared memory locks.
- [[Linux/concepts/03-processes|Linux Processes]] — How the Linux kernel manages processes and signals.
