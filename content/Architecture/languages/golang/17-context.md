---
title: "The Go context Package: Cancellation, Timeouts & Deadlines"
description: "Mastering the Go context package — context.Background vs TODO, propagation across goroutine trees, WithCancel, WithTimeout, WithValue, and HTTP tracing."
tags:
  - architecture
  - languages
  - golang
  - context
  - concurrency
date: 2026-10-19
aliases:
  - Architecture/languages/golang/context
---

# The Go context Package: Cancellation, Timeouts & Deadlines ⏱️

In Go backend microservices, a single incoming HTTP request often triggers a cascade of downstream actions: querying PostgreSQL, calling an authentication microservice, and reading a Redis cache.

If the user closes their browser tab or a database hangs, **you must cancel all in-flight downstream operations** so they don't leak CPU cores and database connections. The **`context` package** is Go's standard mechanism for propagating cancellation signals, deadlines, and request-scoped metadata across API boundaries.

---

## 1. The Context Interface

The `context.Context` interface defines four methods:

```go
type Context interface {
    Deadline() (deadline time.Time, ok bool)
    Done() <-chan struct{} // Closed when work should be canceled
    Err() error            // context.Canceled or context.DeadlineExceeded
    Value(key any) any     // Request-scoped metadata
}
```

- **`context.Background()`**: The root of the context tree. Used in `main()`, top-level HTTP requests, or background jobs.
- **`context.TODO()`**: A placeholder used during development when you aren't sure which context to pass yet. Never leave `context.TODO()` in production code.

---

## 2. Setting Timeouts with `context.WithTimeout`

Always set timeouts on external network and database calls to prevent hanging requests from exhausting thread pools:

```go
package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"
)

func fetchUserOrders(ctx context.Context, userID string) ([]byte, error) {
	// Create derived context with a 2-second timeout
	ctxTimeout, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel() // Always cancel to release timer resources!

	req, err := http.NewRequestWithContext(ctxTimeout, "GET", "https://api.example.com/orders/"+userID, nil)
	if err != nil {
		return nil, err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		// If timeout occurred, err will wrap context.DeadlineExceeded
		return nil, fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	return io.ReadAll(resp.Body)
}
```

---

## 3. Manual Cancellation with `context.WithCancel`

When one worker finishes a search or an error occurs, cancel the context to immediately abort all sibling goroutines:

```go
package main

import (
	"context"
	"fmt"
	"time"
)

func searchEngine(ctx context.Context, name string, ch chan<- string) {
	select {
	case <-time.After(500 * time.Millisecond):
		ch <- fmt.Sprintf("Result from %s", name)
	case <-ctx.Done():
		// Canceled! Clean up and exit immediately to avoid goroutine leak
		fmt.Printf("Search on %s canceled: %v\n", name, ctx.Err())
	}
}

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	results := make(chan string)

	go searchEngine(ctx, "Google", results)
	go searchEngine(ctx, "Bing", results)

	// Wait for the first result to arrive
	firstResult := <-results
	fmt.Println("Fastest result:", firstResult)

	// Cancel the context! The other search engine immediately halts!
	cancel()
	time.Sleep(100 * time.Millisecond) // Let output flush
}
```

---

## 4. Request-Scoped Metadata with `context.WithValue`

Use `context.WithValue` to pass request-scoped data (like an authentication token, request ID, or tenant ID) through HTTP middleware layers.

> [!CAUTION]
> **Use Custom Types for Context Keys:** To prevent key collisions between different packages, always define an unexported custom type for context keys:

```go
package middleware

import (
	"context"
	"net/http"
)

// Unexported custom key type prevents collisions with other packages
type contextKey string

const requestIDKey = contextKey("requestID")

func RequestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqID := r.Header.Get("X-Request-ID")
		if reqID == "" {
			reqID = "req_generated_123"
		}

		// Store in context and pass downstream
		ctx := context.WithValue(r.Context(), requestIDKey, reqID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// Helper to retrieve the value downstream
func GetRequestID(ctx context.Context) (string, bool) {
	val, ok := ctx.Value(requestIDKey).(string)
	return val, ok
}
```

---

## 5. Golden Rules for Go Context

1. **Pass `ctx context.Context` as the very first parameter** of functions that perform I/O (`func DoSomething(ctx context.Context, arg string) error`).
2. **Never store a Context inside a struct.** Pass it explicitly through function parameters.
3. **Always call the `cancel()` function** returned by `WithTimeout` or `WithCancel` (conventionally via `defer cancel()`) to avoid timer and memory leaks.
4. **Contexts are immutable.** Adding a timeout or value creates a new child context; canceling a parent context automatically cancels all its children.

---

## Across the Wiki

- [[Architecture/languages/golang/14-channels|Go Channels]] — Using `<-ctx.Done()` inside `select` blocks.
- [[Architecture/languages/golang/13-concurrency-architecture|Go Concurrency Architecture]] — Concurrency management.
- [[Architecture/languages/golang/23-http-and-graceful-shutdown|HTTP & Graceful Shutdown]] — Attaching contexts to HTTP requests and server shutdown.
