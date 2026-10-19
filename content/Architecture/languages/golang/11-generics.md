---
title: "Generics in Go: Type Parameters, Constraints & Collections"
description: "Mastering Go generics — type parameters [T any], type constraints with cmp.Ordered, generic data structures, and slice/map utilities."
tags:
  - architecture
  - languages
  - golang
  - generics
  - type-systems
date: 2026-10-19
aliases:
  - Architecture/languages/golang/generics
---

# Generics in Go: Type Parameters, Constraints & Collections 🧬

Introduced in **Go 1.18**, **Generics** enable you to write reusable functions and data structures that work across multiple types while preserving full compile-time type safety.

---

## 1. Generic Functions: The Type Parameter Syntax

Type parameters are declared inside square brackets `[T any]` after the function name:

```go
package main

import "fmt"

// Map applies a transform function to every element in a slice
func Map[T any, R any](items []T, transform func(T) R) []R {
	result := make([]R, len(items))
	for i, item := range items {
		result[i] = transform(item)
	}
	return result
}

func main() {
	numbers := []int{1, 2, 3, 4}

	// 1. Transform int to string
	strings := Map(numbers, func(n int) string {
		return fmt.Sprintf("#%d", n)
	})
	fmt.Println("Strings:", strings) // [#1 #2 #3 #4]

	// 2. Transform int to bool
	isEven := Map(numbers, func(n int) bool {
		return n%2 == 0
	})
	fmt.Println("IsEven:", isEven) // [false true false true]
}
```

---

## 2. Type Constraints: Restricting Types

If you use `any`, you can only perform operations valid for all types (like assignment and printing). If you want to compare values using `<` or `==`, you need **Constraints**:

### 1. `comparable` (Built-in for `==` and `!=`)

Used whenever you need to compare values or use `T` as a map key:

```go
// Contains checks if an item exists in a slice
func Contains[T comparable](slice []T, target T) bool {
	for _, item := range slice {
		if item == target {
			return true
		}
	}
	return false
}
```

### 2. `cmp.Ordered` (For `<`, `<=`, `>`, `>=`)

Provided by the standard library package `cmp` (Go 1.21+):

```go
package main

import (
	"cmp"
	"fmt"
)

// Min returns the smaller of two ordered values
func Min[T cmp.Ordered](a, b T) T {
	if a < b {
		return a
	}
	return b
}

func main() {
	fmt.Println(Min(10, 20))           // 10 (int)
	fmt.Println(Min(3.14, 2.71))       // 2.71 (float64)
	fmt.Println(Min("zebra", "apple")) // "apple" (string)
}
```

---

## 3. Generic Data Structures: A Thread-Safe Set

Generics allow building reusable collections without using `map[string]struct{}` everywhere:

```go
package main

import (
	"fmt"
	"sync"
)

// Set is a generic thread-safe collection of unique items
type Set[T comparable] struct {
	mu    sync.RWMutex
	items map[T]struct{}
}

func NewSet[T comparable]() *Set[T] {
	return &Set[T]{
		items: make(map[T]struct{}),
	}
}

func (s *Set[T]) Add(val T) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items[val] = struct{}{}
}

func (s *Set[T]) Has(val T) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	_, exists := s.items[val]
	return exists
}

func main() {
	intSet := NewSet[int]()
	intSet.Add(42)
	fmt.Println("Has 42:", intSet.Has(42)) // true
	fmt.Println("Has 99:", intSet.Has(99)) // false

	stringSet := NewSet[string]()
	stringSet.Add("kubernetes")
	fmt.Println("Has k8s:", stringSet.Has("kubernetes")) // true
}
```

---

## 4. Custom Constraints with Union Syntax (`|` and `~`)

You can create your own constraints using interface union syntax:

```go
package mathutil

// Number accepts any standard int or float, plus custom types derived from them (~)
type Number interface {
	~int | ~int32 | ~int64 | ~float32 | ~float64
}

func Sum[T Number](vals []T) T {
	var total T
	for _, v := range vals {
		total += v
	}
	return total
}
```

The tilde **`~int`** means: _"any type whose underlying type is `int`"_ (e.g., `type UserID int`).

---

## 5. Generic Sorting (`slices.Sort` and `slices.SortFunc`)

Go 1.21 replaced legacy `sort.Interface` boilerplate with the type-safe generic `slices` package.

```go
package main

import (
	"cmp"
	"fmt"
	"slices"
)

type Employee struct {
	Name string
	Age  int
}

func main() {
	// 1. Natural sorting on ordered types
	numbers := []int{50, 10, 40, 20}
	slices.Sort(numbers)
	fmt.Println("Sorted numbers:", numbers) // [10 20 40 50]

	// 2. Custom sorting using slices.SortFunc and cmp.Compare
	team := []Employee{
		{"Alice", 34},
		{"Bob", 23},
		{"Charlie", 29},
	}

	// Sort by age ascending
	slices.SortFunc(team, func(a, b Employee) int {
		return cmp.Compare(a.Age, b.Age)
	})
	fmt.Printf("Sorted by age: %+v\n", team)

	// Binary search on sorted slice
	idx, found := slices.BinarySearch(numbers, 20)
	fmt.Printf("BinarySearch 20: found=%t at index=%d\n", found, idx)
}
```

---

## 6. Range over Function Iterators (`iter.Seq` in Go 1.23+)

Go 1.23 introduced native compiler support for ranging over function iterators (`iter.Seq[V]` and `iter.Seq2[K, V]`).

```go
package main

import (
	"fmt"
	"iter"
)

// Backward returns an iterator yielding items in reverse order
func Backward[E any](s []E) iter.Seq2[int, E] {
	return func(yield func(int, E) bool) {
		for i := len(s) - 1; i >= 0; i-- {
			if !yield(i, s[i]) {
				return // early exit if loop breaks
			}
		}
	}
}

func main() {
	names := []string{"zero", "one", "two", "three"}

	// Native 'for ... range' over a custom iterator function
	for idx, val := range Backward(names) {
		fmt.Printf("Index %d: %s\n", idx, val)
		if idx == 2 {
			break // yield returns false, terminating Backward cleanly
		}
	}
}
```

---

## Across the Wiki

- [[Architecture/programming-concepts/generics-basics|Generics Basics]] — Language-independent concepts and comparisons.
- [[Architecture/languages/golang/04-slices-and-maps|Slices & Maps]] — Standard Go collection types.
- [[Architecture/languages/golang/09-type-assertion|Type Assertions]] — When to use generics vs interfaces.
