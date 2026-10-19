---
title: "Arrays, Slices & Maps in Go"
description: "Mastering Go's core data structures — fixed arrays vs dynamic slices, slice memory headers, sub-slicing gotchas, and maps with the comma-ok idiom."
tags:
  - architecture
  - languages
  - golang
  - slices
  - maps
  - data-structures
date: 2026-10-19
aliases:
  - Architecture/languages/golang/slices-and-maps
---

# Arrays, Slices & Maps in Go 📊

In Go, almost all collections are built using two fundamental types: **Slices** (dynamic, flexible lists) and **Maps** (hash tables for key-value lookups).

---

## 1. Arrays vs Slices: What's the Difference?

- **Array:** Has a fixed length specified at compile time. In Go, an array's length is part of its type (`[3]int` and `[4]int` are completely incompatible types!). Arrays are rarely used directly in application code.
- **Slice:** A lightweight, dynamically sized view over an underlying array. Slices are used 99% of the time.

```go
package main

import "fmt"

func main() {
	// Fixed Array (Length is part of the type)
	var arr [3]string = [3]string{"Alpha", "Beta", "Gamma"}

	// Slice (No length inside brackets)
	var s []string = []string{"Alpha", "Beta", "Gamma"}

	fmt.Printf("Array type: %T, Slice type: %T\n", arr, s)
	// Output: Array type: [3]string, Slice type: []string
}
```

---

## 2. Working with Slices: `make`, `len`, `cap`, and `append`

A slice is a 24-byte header containing three fields: a **pointer** to the backing array, a **length (`len`)**, and a **capacity (`cap`)**.

```go
package main

import "fmt"

func main() {
	// 1. Create a slice with make(type, len, cap)
	// Pre-allocating capacity avoids expensive reallocations when appending!
	scores := make([]int, 0, 5) // len=0, cap=5

	// 2. Append elements
	scores = append(scores, 95)
	scores = append(scores, 88, 72)

	fmt.Printf("len=%d, cap=%d, values=%v\n", len(scores), cap(scores), scores)
	// Output: len=3, cap=5, values=[95 88 72]

	// 3. Slicing an existing slice [start:end] (end index is exclusive)
	topTwo := scores[0:2]
	fmt.Println("Top two:", topTwo) // [95 88]
}
```

### The Sub-Slicing Gotcha (Shared Backing Array)

Sub-slicing a slice (`s[1:3]`) **does not make a copy** of the data—it creates a new slice header pointing to the **same underlying array**:

```go
package main

import "fmt"

func main() {
	original := []int{10, 20, 30}
	sub := original[0:2] // [10, 20]

	// ⚠️ Modifying sub mutates the original slice!
	sub[0] = 999
	fmt.Println("Original:", original) // Output: [999, 20, 30]

	// ✅ Fix: Use copy() or slices.Clone() to create an independent copy
	independent := make([]int, len(original))
	copy(independent, original)
	independent[1] = 888
	fmt.Println("Original untouched:", original) // [999, 20, 30]
}
```

---

## 3. Maps: Key-Value Hash Tables

Maps in Go are reference types that store unordered key-value pairs with $\mathcal{O}(1)$ average lookup time.

### Creating and Using Maps

```go
package main

import "fmt"

func main() {
	// 1. Initialize map with make(map[KeyType]ValueType)
	userRoles := make(map[string]string)

	// 2. Insert or update keys
	userRoles["alice"] = "admin"
	userRoles["bob"] = "viewer"

	// 3. Look up a key with the "comma-ok" idiom
	// Never check for empty string; check the boolean 'ok'!
	role, ok := userRoles["charlie"]
	if !ok {
		fmt.Println("User charlie does not exist in map!")
	} else {
		fmt.Println("Charlie's role:", role)
	}

	// 4. Delete a key
	delete(userRoles, "bob")

	// 5. Iterate over a map
	for user, r := range userRoles {
		fmt.Printf("%s -> %s\n", user, r)
	}
}
```

### Crucial Map Rules & Gotchas

1. **Nil Map Assignment Panic:**
   ```go
   var m map[string]int // m is nil!
   // m["key"] = 10     // 💥 PANIC: assignment to entry in nil map!
   m = make(map[string]int) // ✅ Always initialize with make() or a literal {}
   m["key"] = 10
   ```
2. **Maps are Not Safe for Concurrent Writes:** If two goroutines write to the same map simultaneously, Go crashes with `fatal error: concurrent map writes`. For concurrent lookups/writes, protect the map with `sync.RWMutex` (see [[Architecture/languages/golang/15-sync-and-atomic|Go sync package]]).

---

## Across the Wiki

- [[Architecture/programming-concepts/value-vs-reference-and-pointers|Value vs Reference & Pointers]] — Deep dive into slice headers and heap arrays.
- [[Architecture/languages/golang/06-methods|Go Methods]] — Passing structs containing slices and maps to methods.
- [[Architecture/languages/golang/15-sync-and-atomic|Go Sync Package]] — Protecting maps in concurrent goroutines with `sync.RWMutex`.
