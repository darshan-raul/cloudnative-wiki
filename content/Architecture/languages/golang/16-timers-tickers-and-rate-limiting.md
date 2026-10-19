---
title: "Timers, Tickers, Rate Limiting & Stateful Goroutines"
description: "Mastering time-based concurrency in Go — time.Timer, time.Ticker, bursty token bucket rate limiting, and actor-style stateful goroutines."
tags:
  - architecture
  - languages
  - golang
  - concurrency
  - timers
  - rate-limiting
date: 2026-10-19
aliases:
  - Architecture/languages/golang/timers-tickers-and-rate-limiting
---

# Timers, Tickers, Rate Limiting & Stateful Goroutines ⏱️

In cloud-native backend services, operations frequently require time coordination: periodic metric emission, heartbeat checks, connection timeouts, API rate limiting, and thread-safe state management.

---

## 1. Timers: One-Shot Delays (`time.NewTimer`)

A **Timer** represents a single event in the future. You tell the timer how long you want to wait, and it provides a channel that will be notified at that time:

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	// 1. Basic Timer: wait 1 second
	timer1 := time.NewTimer(1 * time.Second)
	<-timer1.C // Blocks until channel receives timestamp
	fmt.Println("Timer 1 fired!")

	// 2. Canceling a timer before it fires
	timer2 := time.NewTimer(2 * time.Second)
	go func() {
		<-timer2.C
		fmt.Println("Timer 2 fired")
	}()

	stop2 := timer2.Stop()
	if stop2 {
		fmt.Println("Timer 2 canceled before firing!")
	}
}
```

---

## 2. Tickers: Periodic Loops (`time.NewTicker`)

A **Ticker** ticks repeatedly at regular intervals until explicitly stopped:

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	ticker := time.NewTicker(500 * time.Millisecond)
	done := make(chan bool)

	go func() {
		for {
			select {
			case <-done:
				return
			case t := <-ticker.C:
				fmt.Println("Tick at", t.Format("15:04:05.000"))
			}
		}
	}()

	time.Sleep(1600 * time.Millisecond)
	ticker.Stop() // Stop ticker to avoid leaking timer resources!
	done <- true
	fmt.Println("Ticker stopped cleanly.")
}
```

---

## 3. Rate Limiting: Basic & Bursty Token Buckets

Rate limiting is essential for protecting downstream APIs from traffic surges.

### 1. Basic Fixed-Rate Limiter (Using Ticker)

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	requests := make(chan int, 5)
	for i := 1; i <= 5; i++ {
		requests <- i
	}
	close(requests)

	// Rate limiter: 1 request every 200ms
	limiter := time.Tick(200 * time.Millisecond)

	for req := range requests {
		<-limiter // Blocks until ticker emits
		fmt.Println("Processed request", req, time.Now().Format("15:04:05.000"))
	}
}
```

### 2. Bursty Token Bucket (Allows Short Spikes)

In production APIs, you often want to allow a burst of up to 3 requests instantly, but sustain an overall limit of 1 request per 200ms:

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	// Burst capacity of 3 tokens
	burstyLimiter := make(chan time.Time, 3)

	// Fill the bucket to allow immediate burst of 3
	for i := 0; i < 3; i++ {
		burstyLimiter <- time.Now()
	}

	// Continuously refill the bucket at 200ms intervals
	go func() {
		for t := range time.Tick(200 * time.Millisecond) {
			burstyLimiter <- t
		}
	}()

	burstyRequests := make(chan int, 5)
	for i := 1; i <= 5; i++ {
		burstyRequests <- i
	}
	close(burstyRequests)

	for req := range burstyRequests {
		<-burstyLimiter // First 3 succeed immediately; remaining 2 wait 200ms each!
		fmt.Println("Bursty request", req, time.Now().Format("15:04:05.000"))
	}
}
```

---

## 4. Stateful Goroutines (The Actor Pattern)

Instead of using `sync.Mutex` to protect shared state, Go lets you confine state inside a **single dedicated goroutine** that communicates via read/write request channels:

```go
package main

import (
	"fmt"
	"math/rand"
	"sync/atomic"
	"time"
)

type readOp struct {
	key  int
	resp chan int // Private channel to receive response
}

type writeOp struct {
	key  int
	val  int
	resp chan bool
}

func main() {
	var readOps uint64
	var writeOps uint64

	reads := make(chan readOp)
	writes := make(chan writeOp)

	// Sole owner of the state! Zero mutexes needed!
	go func() {
		state := make(map[int]int)
		for {
			select {
			case read := <-reads:
				read.resp <- state[read.key]
			case write := <-writes:
				state[write.key] = write.val
				write.resp <- true
			}
		}
	}()

	// 10 concurrent readers
	for r := 0; r < 10; r++ {
		go func() {
			for {
				read := readOp{key: rand.Intn(5), resp: make(chan int)}
				reads <- read
				<-read.resp
				atomic.AddUint64(&readOps, 1)
				time.Sleep(time.Millisecond)
			}
		}()
	}

	time.Sleep(500 * time.Millisecond)
	fmt.Printf("Read ops executed safely: %d\n", atomic.LoadUint64(&readOps))
}
```

---

## Across the Wiki

- [[Architecture/languages/golang/14-channels|Go Channels]] — Basic channel operations and select statements.
- [[Architecture/languages/golang/15-sync-and-atomic|Go Sync Package]] — Comparing stateful goroutines to `sync.Mutex`.
- [[Architecture/solution-architecture-concepts/performance/rate-limiting|Rate Limiting Architecture]] — System design rate limiting strategies (Token Bucket, Leaky Bucket).
