---
title: "Generics Explained: Reusable, Type-Safe Code"
description: "Why generics exist — eliminating code duplication without sacrificing type safety, type parameters, and everyday practical examples."
tags:
  - architecture
  - programming-concepts
  - generics
  - type-systems
date: 2026-10-19
---

# Generics Explained: Reusable, Type-Safe Code 🧬

When writing software in statically typed languages, you frequently need to write logic that works across multiple different data types—such as a list, a cache, a stack, or a sorting algorithm.

Before **Generics**, developers were stuck with a frustrating dilemma: **duplicate code** for every type, or **lose type safety** by using untyped placeholders (like `Object` in Java or `any` / `interface{}` in Go).

---

## 1. The Problem Generics Solve

Imagine you want a helper function that reverses a slice/array. Without generics in a typed language:

```go
// Option A: Write duplicate functions for every single type! 😫
func ReverseInts(s []int) []int { /* ... */ }
func ReverseStrings(s []string) []string { /* ... */ }
func ReverseUsers(s []User) []User { /* ... */ }

// Option B: Use 'any', but lose all type safety and require ugly casting! ⚠️
func ReverseAny(s []any) []any { /* ... */ }
```

With **Generics**, you write the function **once** and use a **Type Parameter** (`T`) as a placeholder that gets filled in with the concrete type when called:

```go
// ✅ With Generics: Written once, works for ANY type, completely type-safe!
func Reverse[T any](s []T) []T {
	result := make([]T, len(s))
	for i, v := range s {
		result[len(s)-1-i] = v
	}
	return result
}

func main() {
	numbers := Reverse([]int{1, 2, 3})         // Compiler knows result is []int!
	names   := Reverse([]string{"a", "b", "c"}) // Compiler knows result is []string!
}
```

---

## 2. Common Real-World Use Cases for Generics

### 1. Generic Data Structures (Collections)

Building reusable containers like stacks, queues, linked lists, or LRU caches:

```typescript
// Generic Stack in TypeScript
class Stack<T> {
  private items: T[] = [];

  push(item: T): void {
    this.items.push(item);
  }

  pop(): T | undefined {
    return this.items.pop();
  }
}

const stringStack = new Stack<string>();
stringStack.push("hello");
// stringStack.push(42); ❌ Compiler error: number is not string!
```

### 2. Generic HTTP API Responses

In microservices, API responses often share the same metadata wrapper (status, timestamp, error) around different data payloads:

```typescript
interface ApiResponse<T> {
  status: "success" | "error";
  data: T;
  timestamp: string;
}

// Reusable across all endpoints!
type UserResponse = ApiResponse<User>;
type OrderResponse = ApiResponse<Order[]>;
```

---

## 3. Type Constraints: Not _All_ Types Can Do Everything

Sometimes you don't want a generic function to accept _literally any_ type. You only want types that support a specific operation (like being compared with `<` or being converted to a string).

We restrict types using **Type Constraints**:

```go
package main

import "cmp"

// cmp.Ordered restricts T to types that support <, <=, >, >= (ints, floats, strings)
func Min[T cmp.Ordered](a, b T) T {
	if a < b {
		return a
	}
	return b
}

func main() {
	println(Min(10, 20))       // 10
	println(Min("apple", "banana")) // "apple"
}
```

---

## 4. Rule of Thumb: When Should You Use Generics?

Generics are powerful, but over-using them makes code harder to read.

### Good Uses for Generics:

- Common data structures (queues, caches, trees, linked lists).
- Generic utility functions operating on slices, maps, or streams (e.g., `Map`, `Filter`, `Reduce`, `Contains`).
- Generic API response / repository wrappers.

### When NOT to Use Generics:

- When a simple **interface** is sufficient.
- When the function only ever operates on one or two known types in your business logic.

---

## Across the Wiki

- [[Architecture/programming-concepts/type-systems-static-vs-dynamic|Type Systems: Static vs Dynamic]] — Foundational type concepts.
- [[Architecture/programming-concepts/composition-vs-inheritance-and-interfaces|Composition vs Inheritance & Interfaces]] — Combining interfaces with generics.
- [[Architecture/languages/golang/interfaces|Go Interfaces]] — How Go combines interfaces and type constraints.
