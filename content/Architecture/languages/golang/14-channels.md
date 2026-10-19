---
title: "Channels & Goroutines in Go: Concurrency Patterns"
description: "Go channels and the common patterns for using them to communicate between goroutines — unbuffered vs buffered, select, worker pools, fan-in/fan-out, and pipelines."
tags:
  - architecture
  - languages
  - golang
  - channels
  - concurrency
date: 2026-10-19
aliases:
  - Architecture/languages/golang/channels
---

# Channels & Goroutines in Go: Concurrency Patterns ⚡

Go implements the **CSP (Communicating Sequential Processes)** concurrency model:

> _"Do not communicate by sharing memory; instead, share memory by communicating."_

A **Channel** is a typed conduit through which you can send and receive values between concurrent goroutines using the channel operator `<-`.

---

## 1. Unbuffered vs Buffered Channels

```
UNBUFFERED: Synchronization Point (Rendezvous)
  Sender Goroutine   ──(Blocks until Receiver is ready!)──▶ Receiver Goroutine

BUFFERED: Asynchronous Queue (Up to Capacity)
  Sender Goroutine   ──[ Msg 1 ][ Msg 2 ]──▶ Receiver Goroutine (Pops when ready)
```

```go
package main

import "fmt"

func main() {
	// 1. Unbuffered Channel (make(chan T))
	// Send BLOCKS until another goroutine is actively receiving!
	unbuffered := make(chan string)

	go func() {
		unbuffered <- "hello from goroutine" // Blocks until main receives
	}()

	msg := <-unbuffered
	fmt.Println(msg)

	// 2. Buffered Channel (make(chan T, capacity))
	// Sends only block when the buffer is FULL!
	buffered := make(chan int, 2)
	buffered <- 10
	buffered <- 20
	// buffered <- 30 // This would block because cap=2!

	fmt.Println(<-buffered) // 10
	fmt.Println(<-buffered) // 20
}
```

---

## 2. Directional Channels (Type-Safe Ownership)

When passing channels into functions, you can restrict their direction using `<-chan` (read-only) or `chan<-` (write-only) to enforce clear producer/consumer contracts:

```go
// producer can ONLY send to ch
func producer(ch chan<- int) {
	for i := 1; i <= 3; i++ {
		ch <- i
	}
	close(ch) // Only sender should close!
}

// consumer can ONLY receive from ch
func consumer(ch <-chan int) {
	for val := range ch {
		println("Received:", val)
	}
}
```

---

## 3. The `select` Statement (Multiplexing Channels)

The `select` statement lets a goroutine wait on multiple channel operations simultaneously. It blocks until one of its cases can proceed:

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	fastCh := make(chan string)
	slowCh := make(chan string)

	go func() {
		time.Sleep(100 * time.Millisecond)
		fastCh <- "Fast ping"
	}()

	go func() {
		time.Sleep(300 * time.Millisecond)
		slowCh <- "Slow ping"
	}()

	// Wait for the first response or a timeout:
	select {
	case msg := <-fastCh:
		fmt.Println("Received:", msg)
	case msg := <-slowCh:
		fmt.Println("Received:", msg)
	case <-time.After(200 * time.Millisecond):
		fmt.Println("Timeout! Operation took too long.")
	}
}
```

### Non-Blocking Channel Operations (`default`)

Standard channel sends and receives block until the opposite side is ready. Adding a `default:` clause to a `select` statement makes the operation non-blocking:

```go
package main

import "fmt"

func main() {
	messages := make(chan string)
	signals := make(chan bool)

	// 1. Non-blocking receive
	select {
	case msg := <-messages:
		fmt.Println("Received message:", msg)
	default:
		fmt.Println("No message available (non-blocking receive)")
	}

	// 2. Non-blocking send
	msg := "hello"
	select {
	case messages <- msg:
		fmt.Println("Sent message:", msg)
	default:
		fmt.Println("Cannot send message (no receiver ready, non-blocking send)")
	}

	// 3. Multi-way non-blocking select
	select {
	case msg := <-messages:
		fmt.Println("Received message:", msg)
	case sig := <-signals:
		fmt.Println("Received signal:", sig)
	default:
		fmt.Println("Neither message nor signal was ready")
	}
}
```

---

## 4. The 5 Core Channel Concurrency Patterns

### Pattern 1: Range Over Channel & Closing

Use `for val := range ch` to drain a channel until the sender closes it:

```go
ch := make(chan int)
go func() {
	for i := 1; i <= 5; i++ {
		ch <- i
	}
	close(ch) // Signals that no more values will be sent
}()

for val := range ch {
	fmt.Println(val)
}
```

### Pattern 2: Worker Pool (Fan-Out / Fan-In)

Spawn $N$ persistent worker goroutines to process jobs concurrently from a shared input channel:

```go
package main

import (
	"fmt"
	"sync"
	"time"
)

func worker(id int, jobs <-chan int, results chan<- int, wg *sync.WaitGroup) {
	defer wg.Done()
	for j := range jobs {
		time.Sleep(50 * time.Millisecond) // Simulating work
		results <- j * 2
	}
}

func main() {
	jobs := make(chan int, 10)
	results := make(chan int, 10)
	var wg sync.WaitGroup

	// Start 3 workers
	for w := 1; w <= 3; w++ {
		wg.Add(1)
		go worker(w, jobs, results, &wg)
	}

	// Send 6 jobs
	for j := 1; j <= 6; j++ {
		jobs <- j
	}
	close(jobs) // Closes input channel; workers finish when drained

	wg.Wait()
	close(results)

	for res := range results {
		fmt.Println("Processed result:", res)
	}
}
```

### Pattern 3: Pipelines (Stream Processing)

Chaining stages together where each stage consumes from an upstream channel and outputs to a downstream channel:

```go
func generateNumbers(nums ...int) <-chan int {
	out := make(chan int)
	go func() {
		for _, n := range nums {
			out <- n
		}
		close(out)
	}()
	return out
}

func squareNumbers(in <-chan int) <-chan int {
	out := make(chan int)
	go func() {
		for n := range in {
			out <- n * n
		}
		close(out)
	}()
	return out
}
```

---

## 5. Channel Rules to Avoid Panics & Deadlocks

| Operation               | Channel is Open                    | Channel is Closed              | Channel is `nil`   |
| :---------------------- | :--------------------------------- | :----------------------------- | :----------------- |
| **Send (`ch <- v`)**    | Succeeds (or blocks if full)       | 💥 **PANIC!**                  | **Blocks forever** |
| **Receive (`<-ch`)**    | Returns value (or blocks if empty) | Returns zero-value immediately | **Blocks forever** |
| **Close (`close(ch)`)** | Succeeds                           | 💥 **PANIC!**                  | 💥 **PANIC!**      |

### Golden Rules:

1. **Only the SENDER should close a channel** (never the receiver, to avoid sending on closed channels).
2. **Never send on a closed channel** (causes a panic).
3. If multiple goroutines send to the same channel, coordinate closing with `sync.Once` or a `done` channel.

---

## Across the Wiki

- [[Architecture/languages/golang/13-concurrency-architecture|Go Concurrency Philosophy]] — Choosing between channels and mutexes.
- [[Architecture/languages/golang/15-sync-and-atomic|Go Sync Package]] — Combining channels with `sync.WaitGroup` and `sync.Mutex`.
- [[Architecture/languages/golang/17-context|Go Context]] — Propagating cancellation to channels.
