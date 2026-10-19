---
title: "Testing, Table-Driven Tests & Benchmarks in Go"
description: "Mastering Go's testing package — table-driven tests, subtests with t.Run, HTTP handler testing with httptest, and CPU benchmarks with b.N."
tags:
  - architecture
  - languages
  - golang
  - testing
  - benchmarks
date: 2026-10-19
aliases:
  - Architecture/languages/golang/testing-and-benchmarks
---

# Testing, Table-Driven Tests & Benchmarks in Go 🧪

Go includes a comprehensive, built-in testing framework right in the standard library through the **`testing`** package and the **`go test`** command.

---

## 1. Idiomatic Table-Driven Tests (`t.Run`)

The standard convention in the Go community is **Table-Driven Testing**: defining a slice of test cases and iterating over them with `t.Run()`:

```go
// calc_test.go
package calc_test

import (
	"testing"
)

func Add(a, b int) int {
	return a + b
}

func TestAdd(t *testing.T) {
	// Define the test case table
	tests := []struct {
		name     string
		a, b     int
		expected int
	}{
		{name: "positive numbers", a: 2, b: 3, expected: 5},
		{name: "with zero", a: 10, b: 0, expected: 10},
		{name: "negative numbers", a: -5, b: -3, expected: -8},
	}

	// Run each test as a subtest
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := Add(tc.a, tc.b)
			if result != tc.expected {
				t.Errorf("Add(%d, %d) = %d; want %d", tc.a, tc.b, result, tc.expected)
			}
		})
	}
}
```

```bash
# Run tests with verbose output:
go test -v ./...
```

---

## 2. Testing HTTP Handlers with `net/http/httptest`

You can test HTTP handlers directly without opening actual network ports using **`httptest.NewRecorder`**:

```go
package handler_test

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("healthy"))
}

func TestHealthCheckHandler(t *testing.T) {
	// 1. Create simulated request
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)

	// 2. Create ResponseRecorder to capture output
	rr := httptest.NewRecorder()

	// 3. Call handler directly
	HealthCheckHandler(rr, req)

	// 4. Assert response
	if rr.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", rr.Code)
	}

	if rr.Body.String() != "healthy" {
		t.Errorf("expected body 'healthy', got %s", rr.Body.String())
	}
}
```

---

## 3. Writing Benchmarks (`b.N`)

Go provides first-class support for benchmarking CPU performance and memory allocations:

```go
// strings_test.go
package main

import (
	"strings"
	"testing"
)

func BenchmarkStringConcat(b *testing.B) {
	// b.N is dynamically adjusted by Go until results are statistically stable
	for i := 0; i < b.N; i++ {
		var s strings.Builder
		for j := 0; j < 100; j++ {
			s.WriteString("test")
		}
		_ = s.String()
	}
}
```

```bash
# Run benchmarks with memory allocation metrics:
go test -bench=. -benchmem
# BenchmarkStringConcat-8   500000   2400 ns/op   512 B/op   1 allocs/op
```

---

## Across the Wiki

- [[Architecture/solution-architecture-concepts/software-engineering-concepts/testing/unit-testing|Unit Testing Concepts]] — Testing best practices.
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/testing/test-doubles-mocks-stubs-fakes|Test Doubles, Mocks & Stubs]] — Mocking dependencies in tests.
- [[Architecture/languages/golang/08-interfaces|Go Interfaces]] — Designing interfaces for testability.
