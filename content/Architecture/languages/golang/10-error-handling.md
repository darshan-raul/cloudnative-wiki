---
title: "Idiomatic Error Handling in Go: Wrapping, errors.Is & errors.As"
description: "Mastering error handling in Go — errors as values, sentinel errors, wrapping with fmt.Errorf, errors.Is and errors.As, and panic vs recover."
tags:
  - architecture
  - languages
  - golang
  - error-handling
  - errors
date: 2026-10-19
aliases:
  - Architecture/languages/golang/error-handling
---

# Idiomatic Error Handling in Go: Wrapping, `errors.Is` & `errors.As` ⚠️

Go handles errors differently from languages with exceptions (`try/catch`). In Go, **errors are normal values** returned explicitly from functions.

Since Go 1.13, Go provides standardized **Error Wrapping** (`%w`), **`errors.Is()`**, and **`errors.As()`**, allowing you to wrap errors with rich contextual messages while preserving the ability to inspect underlying error causes.

---

## 1. The Basics: Creating and Returning Errors

In Go, `error` is a simple built-in interface with a single method:

```go
type error interface {
    Error() string
}
```

```go
package main

import (
	"errors"
	"fmt"
)

// Sentinel Error (reusable package-level error)
var ErrUserNotFound = errors.New("user not found")

func findUser(id int64) (string, error) {
	if id <= 0 {
		return "", errors.New("invalid user ID: must be positive")
	}
	if id != 42 {
		return "", ErrUserNotFound
	}
	return "Alice", nil
}

func main() {
	user, err := findUser(99)
	if err != nil {
		fmt.Printf("Lookup failed: %v\n", err)
		return
	}
	fmt.Println("Found:", user)
}
```

---

## 2. Error Wrapping with `fmt.Errorf` and `%w`

When returning an error up the call stack, always add **context** describing what your function was trying to do. Use the **`%w`** verb to wrap the original error:

```go
func parseConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		// Wraps the underlying os.PathError with custom context!
		return nil, fmt.Errorf("parseConfig failed for %s: %w", path, err)
	}
	// ... unmarshal config ...
	return cfg, nil
}
```

If `os.ReadFile` fails, the output will look like:
`parseConfig failed for /etc/app.yaml: open /etc/app.yaml: no such file or directory`

---

## 3. Inspecting Wrapped Errors: `errors.Is()` and `errors.As()`

Because errors can be wrapped multiple times, you should **never compare errors with `==`** or parse error strings with `strings.Contains`.

### 1. `errors.Is()` (Checking for Specific Sentinel Errors)

`errors.Is(err, target)` unwraps the chain of errors to see if `target` exists anywhere inside:

```go
package main

import (
	"errors"
	"fmt"
	"io"
)

var ErrDatabaseDown = errors.New("database connection refused")

func queryOrders() error {
	// Simulated error wrapped inside another error
	return fmt.Errorf("service layer: %w", ErrDatabaseDown)
}

func main() {
	err := queryOrders()

	// ❌ Fragile check:
	// if err == ErrDatabaseDown { ... } // Fails because err is wrapped!

	// ✅ Idiomatic check: unwraps chain!
	if errors.Is(err, ErrDatabaseDown) {
		fmt.Println("Handling DB outage: retrying with backoff...")
	}
}
```

### 2. `errors.As()` (Extracting Specific Error Types)

When an error has structured fields (like an HTTP status code or path), `errors.As(err, &target)` unwraps the chain and populates the target variable:

```go
package main

import (
	"errors"
	"fmt"
	"os"
)

func main() {
	_, err := os.Open("/non-existent-file.txt")
	if err != nil {
		var pathErr *os.PathError
		// Unwraps and extracts *os.PathError if present in chain
		if errors.As(err, &pathErr) {
			fmt.Printf("Failed on path: %s (Op: %s)\n", pathErr.Path, pathErr.Op)
			return
		}
		fmt.Println("Generic error:", err)
	}
}
```

---

## 4. Panic and Recover: When to Use Them?

Go provides `panic` and `recover`, but they are **NOT** meant to be used as general exceptions:

- **Use Errors for Expected Failures:** Network timeouts, missing files, invalid input, database errors $\rightarrow$ return an `error`.
- **Use Panic ONLY for Unrecoverable Programmer Bugs:** A critical regex that failed to compile on startup (`regexp.MustCompile`), or unrecoverable invariant violations.

### Recovering from Panics in HTTP Middleware

If a handler crashes, an HTTP server shouldn't die. You can recover from panics in middleware:

```go
func RecoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("Panic recovered: %v", r)
				http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}
```

---

## Across the Wiki

- [[Architecture/programming-concepts/error-handling-patterns|Error Handling: Exceptions vs Values]] — Architectural comparison of error models.
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/api-error-codes|API Error Codes & RFC 7807]] — Translating Go errors into HTTP status codes.
- [[Architecture/languages/golang/08-interfaces|Go Interfaces]] — Understanding the `error` interface.
