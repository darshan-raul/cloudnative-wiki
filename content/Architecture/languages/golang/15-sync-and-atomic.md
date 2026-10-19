---
title: "The Go sync Package: Mutex, RWMutex, WaitGroup & errgroup"
description: "Mastering Go's sync package — Mutex and RWMutex for shared state, WaitGroup for coordination, sync.Once, sync.Pool, and errgroup.Group for concurrent error handling."
tags:
  - architecture
  - languages
  - golang
  - concurrency
  - sync
date: 2026-10-19
aliases:
  - Architecture/languages/golang/concurrency/sync
---

# The Go `sync` Package: Mutex, RWMutex, WaitGroup & errgroup 🔒

While channels handle communication between goroutines, the **`sync` package** provides low-level synchronization primitives for managing shared memory, waiting for concurrent tasks, and coordinating single-time initialization.

---

## 1. `sync.Mutex`: Mutual Exclusion

A **`sync.Mutex`** ensures that only one goroutine can access a critical section of code at any given time:

```go
package main

import (
	"fmt"
	"sync"
)

type SafeCounter struct {
	mu    sync.Mutex
	count int
}

func (c *SafeCounter) Increment() {
	c.mu.Lock()
	defer c.mu.Unlock() // Always unlock with defer!
	c.count++
}

func (c *SafeCounter) Value() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.count
}

func main() {
	counter := &SafeCounter{}
	var wg sync.WaitGroup

	// Launch 1,000 goroutines to increment concurrently
	for i := 0; i < 1000; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			counter.Increment()
		}()
	}

	wg.Wait()
	fmt.Println("Final Count:", counter.Value()) // Guaranteed 1000 with zero data races!
}
```

---

## 2. `sync.RWMutex`: Reader/Writer Lock

When you have a data structure that is **read frequently but written to rarely** (like an in-memory cache), a standard `Mutex` creates unnecessary contention.

A **`sync.RWMutex`** allows **unlimited concurrent readers** (`RLock()`), but grants **exclusive access to a single writer** (`Lock()`):

```go
package main

import (
	"sync"
)

type Cache struct {
	mu    sync.RWMutex
	items map[string]string
}

func (c *Cache) Get(key string) (string, bool) {
	c.mu.RLock()         // Multiple goroutines can read simultaneously!
	defer c.mu.RUnlock()
	val, ok := c.items[key]
	return val, ok
}

func (c *Cache) Set(key, val string) {
	c.mu.Lock()          // Exclusive lock: no other readers or writers allowed
	defer c.mu.Unlock()
	c.items[key] = val
}
```

---

## 3. `sync.WaitGroup`: Waiting for Concurrent Tasks

A **`sync.WaitGroup`** waits for a collection of goroutines to finish:

- `wg.Add(n)`: Increments the counter by $n$.
- `wg.Done()`: Decrements the counter by 1 (typically called via `defer wg.Done()`).
- `wg.Wait()`: Blocks until the counter reaches 0.

```go
package main

import (
	"fmt"
	"net/http"
	"sync"
)

func checkURL(url string, wg *sync.WaitGroup) {
	defer wg.Done() // Decrement counter when finished

	resp, err := http.Get(url)
	if err != nil {
		fmt.Printf("❌ %s is down: %v\n", url, err)
		return
	}
	defer resp.Body.Close()
	fmt.Printf("✅ %s returned %d\n", url, resp.StatusCode)
}

func main() {
	urls := []string{
		"https://golang.org",
		"https://google.com",
		"https://github.com",
	}

	var wg sync.WaitGroup

	for _, u := range urls {
		wg.Add(1)
		go checkURL(u, &wg)
	}

	wg.Wait() // Blocks until all 3 URLs have responded!
	fmt.Println("All health checks complete.")
}
```

---

## 4. `sync.Once`: Thread-Safe Singleton Initialization

`sync.Once` guarantees that a piece of code is executed **exactly once**, even if thousands of goroutines call it concurrently:

```go
package main

import (
	"fmt"
	"sync"
)

type DatabaseConnection struct{}

var (
	dbInstance *DatabaseConnection
	once       sync.Once
)

func GetDatabase() *DatabaseConnection {
	once.Do(func() {
		fmt.Println("Initializing database connection pool...")
		dbInstance = &DatabaseConnection{}
	})
	return dbInstance
}
```

---

## 5. `errgroup.Group`: Concurrent Tasks with Error Propagation

In real-world backend services, tasks running in goroutines can return errors. The extended standard library package **`golang.org/x/sync/errgroup`** manages a group of goroutines and captures the first error:

```go
package main

import (
	"context"
	"fmt"
	"net/http"

	"golang.org/x/sync/errgroup"
)

func main() {
	// Group cancels the context as soon as ANY sub-task returns an error!
	g, ctx := errgroup.WithContext(context.Background())

	urls := []string{"https://golang.org", "https://invalid-domain-404-xyz.com"}

	for _, url := range urls {
		u := url // capture loop variable
		g.Go(func() error {
			// If ctx is canceled by another task failing, we can abort early
			req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
			_, err := http.DefaultClient.Do(req)
			return err
		})
	}

	// Wait blocks until all goroutines finish or the first error occurs
	if err := g.Wait(); err != nil {
		fmt.Printf("At least one request failed: %v\n", err)
	}
}
```

---

## 6. `sync/atomic`: Lock-Free Atomic Counters

For low-level counters, sequence generators, and flags, `sync/atomic` uses CPU-level atomic instructions instead of OS mutex locks, delivering unmatched performance.

Go 1.19+ provides typed atomic types like `atomic.Uint64`, `atomic.Int64`, `atomic.Bool`, and `atomic.Pointer[T]`:

```go
package main

import (
	"fmt"
	"sync"
	"sync/atomic"
)

func main() {
	// Typed atomic counter (zero value is ready to use)
	var ops atomic.Uint64

	var wg sync.WaitGroup

	// Launch 50 goroutines incrementing the counter 1,000 times each
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for c := 0; c < 1000; c++ {
				ops.Add(1)
			}
		}()
	}

	wg.Wait()

	// Safe atomic read
	fmt.Println("Total atomic operations:", ops.Load()) // exactly 50,000

	// Compare-and-Swap (CAS)
	swapped := ops.CompareAndSwap(50000, 0)
	fmt.Printf("Reset counter via CAS: %t (new value: %d)\n", swapped, ops.Load())
}
```

---

## Across the Wiki

- [[Architecture/languages/golang/14-channels|Go Channels]] — Communicating by message passing vs sharing memory.
- [[Architecture/languages/golang/13-concurrency-architecture|Go Concurrency Philosophy]] — Channels vs Mutexes decision matrix.
- [[Architecture/languages/golang/17-context|Go Context Package]] — Combining `context` with `errgroup`.
