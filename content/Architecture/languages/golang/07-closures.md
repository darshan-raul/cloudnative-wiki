---
title: "Closures, Lexical Scope & Defer in Go"
description: "How closures work in Go, variable capture mechanics, defer LIFO execution order, cleanup patterns, and Go 1.22 loop variable scoping."
tags:
  - architecture
  - languages
  - golang
  - closures
  - defer
date: 2026-10-19
aliases:
  - Architecture/languages/golang/closures
---

# Closures, Lexical Scope & Defer in Go 🎒

In Go, functions are **first-class citizens**: you can assign them to variables, pass them as arguments, return them from other functions, and capture variables from their outer scope (**Closures**).

Paired with Go's built-in **`defer`** statement, these features provide clean, guaranteed resource cleanup and modular architecture.

---

## 1. What is a Closure?

A **Closure** is an anonymous function that references variables from outside its body. The function can access and modify the referenced variables; the variables are bound to the function.

```go
package main

import "fmt"

// intSeq returns a closure that increments its own private counter
func intSeq() func() int {
	i := 0 // Captured in the closure's scope
	return func() int {
		i++
		return i
	}
}

func main() {
	// nextInt captures its own independent 'i'
	nextInt := intSeq()
	fmt.Println(nextInt()) // 1
	fmt.Println(nextInt()) // 2
	fmt.Println(nextInt()) // 3

	// A new call to intSeq creates a completely independent closure!
	newSeq := intSeq()
	fmt.Println(newSeq())  // 1
}
```

---

## 2. Real-World Use Case: Configurable HTTP Middleware

In Go web services, closures are the standard way to build HTTP middleware with configuration:

```go
package main

import (
	"fmt"
	"net/http"
	"time"
)

// WithRateLimit returns an HTTP middleware closure with configured limit
func WithRateLimit(maxPerSecond int) func(http.Handler) http.Handler {
	// Shared state across requests
	tokens := maxPerSecond

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if tokens <= 0 {
				http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
				return
			}
			tokens--
			next.ServeHTTP(w, r)
		})
	}
}
```

---

## 3. The `defer` Statement: Guaranteed Cleanup

`defer` schedules a function call to run **immediately before the surrounding function returns**, regardless of whether the function returns normally or panics.

### 1. Basic LIFO Execution Order

Deferred calls are executed in **Last-In, First-Out (LIFO)** order (like a stack):

```go
package main

import "fmt"

func main() {
	defer fmt.Println("1st defer (runs last)")
	defer fmt.Println("2nd defer")
	defer fmt.Println("3rd defer (runs first)")

	fmt.Println("Main execution finished")
}
// Output:
// Main execution finished
// 3rd defer (runs first)
// 2nd defer
// 1st defer (runs last)
```

### 2. The #1 Use Case: Releasing Resources

Always call `defer` immediately after successfully opening a resource (file, mutex lock, database row cursor, HTTP response body):

```go
func processFile(filename string) error {
	f, err := os.Open(filename)
	if err != nil {
		return err
	}
	defer f.Close() // Guaranteed to close, even if code below returns early or errors!

	data, err := io.ReadAll(f)
	if err != nil {
		return err
	}
	return handle(data)
}
```

### 3. Timing Function Execution with Defer

Because arguments to a deferred function are evaluated **immediately** when the `defer` line is encountered, closures allow elegant execution timing:

```go
func measureLatency() {
	start := time.Now()
	defer func() {
		fmt.Printf("Operation took: %v\n", time.Since(start))
	}()

	time.Sleep(50 * time.Millisecond) // Simulated work
}
```

---

## 4. Loop Variable Capture in Goroutines (The Go 1.22 Fix)

In Go versions prior to 1.22, loop variables were reused across iterations, leading to a notorious bug when spawning goroutines or closures inside loops:

```go
package main

import (
	"fmt"
	"sync"
)

func main() {
	var wg sync.WaitGroup
	items := []string{"A", "B", "C"}

	for _, item := range items {
		wg.Add(1)
		go func() {
			defer wg.Done()
			fmt.Println(item)
		}()
	}
	wg.Wait()
}
```

- **Go 1.21 and older:** Frequently printed `C, C, C` because all goroutines captured the single shared `item` pointer.
- **Go 1.22+:** The Go compiler creates a **new instance of the variable on every loop iteration**, so it safely prints `A`, `B`, and `C`!

---

## Across the Wiki

- [[Architecture/programming-concepts/scope-closures-and-callbacks|Scope, Closures & Callbacks]] — Language-agnostic closure concepts.
- [[Architecture/languages/golang/14-channels|Go Channels]] — Coordinating goroutines spawned with closures.
- [[Architecture/languages/golang/15-sync-and-atomic|Go Sync Package]] — Using `defer mu.Unlock()` with Mutexes.
