---
title: "Type Assertions, Type Switches & any in Go"
description: "Extracting concrete types from interfaces safely with comma-ok assertions, handling multiple types with type switches, and working with modern any."
tags:
  - architecture
  - languages
  - golang
  - type-assertion
  - type-switch
date: 2026-10-19
aliases:
  - Architecture/languages/golang/type-assertion
---

# Type Assertions, Type Switches & `any` in Go 🔍

In Go, a variable of an interface type (such as `any` or `error`) can hold different concrete values at runtime. When you need to retrieve the underlying concrete value or check what type is stored inside, Go provides **Type Assertions** and **Type Switches**.

---

## 1. Type Assertions: `val := i.(ConcreteType)`

A **Type Assertion** extracts the underlying concrete value from an interface value:

### 1. Single-Value Assertion (Risky — Panics on Mismatch)

```go
var x any = "hello"

str := x.(string) // OK: str is "hello"

num := x.(int)    // 💥 PANIC: interface conversion: interface {} is string, not int
```

### 2. Double-Value Assertion (The Safe "Comma-Ok" Idiom)

Always use the two-value form in production code to test types without crashing:

```go
package main

import "fmt"

func process(val any) {
	// Comma-ok idiom: ok is true if assertion succeeded, false otherwise
	if s, ok := val.(string); ok {
		fmt.Printf("String length: %d (value: %s)\n", len(s), s)
		return
	}

	if n, ok := val.(int); ok {
		fmt.Printf("Doubled integer: %d\n", n*2)
		return
	}

	fmt.Println("Unknown or unhandled type!")
}

func main() {
	process("cloud-native") // String length: 12 (value: cloud-native)
	process(42)             // Doubled integer: 84
	process(3.14)           // Unknown or unhandled type!
}
```

---

## 2. Type Switches: Handling Multiple Types Cleanly

When handling multiple possible types, a **Type Switch** is much cleaner than chaining multiple `if/else` assertions:

```go
package main

import "fmt"

func inspect(x any) {
	// The type switch syntax assigns the unwrapped concrete value to 'v'
	switch v := x.(type) {
	case string:
		fmt.Printf("String of length %d: %q\n", len(v), v)
	case int, int64:
		fmt.Printf("Integer: %v\n", v)
	case bool:
		fmt.Printf("Boolean flag: %t\n", v)
	case []byte:
		fmt.Printf("Byte buffer: %d bytes\n", len(v))
	case nil:
		fmt.Println("Value is literal nil!")
	default:
		fmt.Printf("Unexpected type %T: %v\n", v, v)
	}
}

func main() {
	inspect("golang")
	inspect(100)
	inspect(true)
	inspect([]byte{0xDE, 0xAD})
	inspect(nil)
}
```

---

## 3. Real-World Use Case: Parsing JWT Claims or Generic JSON

In API authentication, JWT token claims are frequently parsed as `map[string]any`. You use type assertions to safely extract typed claims:

```go
package main

import "fmt"

func extractUserID(claims map[string]any) (string, error) {
	subRaw, ok := claims["sub"]
	if !ok {
		return "", fmt.Errorf("claim 'sub' missing from token")
	}

	sub, ok := subRaw.(string)
	if !ok {
		return "", fmt.Errorf("claim 'sub' must be a string, got %T", subRaw)
	}

	return sub, nil
}

func main() {
	validClaims := map[string]any{"sub": "usr_9981", "admin": true}
	userID, err := extractUserID(validClaims)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Println("Authenticated User ID:", userID)
}
```

---

## 4. `any` vs `interface{}`

Starting in **Go 1.18**, `any` was introduced as an official alias for `interface{}`:

```go
// Both lines are 100% identical in Go:
var a interface{} = "legacy syntax"
var b any         = "modern clean syntax"
```

> [!TIP]
> **Use `any` Sparingly:** While `any` can hold anything, using it everywhere throws away Go's compile-time type safety. Prefer specific interfaces (`io.Reader`) or [[Architecture/languages/golang/11-generics|Generics]] whenever possible.

---

## Across the Wiki

- [[Architecture/languages/golang/08-interfaces|Go Interfaces]] — How interfaces are created and satisfied.
- [[Architecture/languages/golang/11-generics|Go Generics]] — Writing type-safe reusable code without needing `any`.
- [[Architecture/languages/golang/25-reflect|Go Reflect]] — Inspecting arbitrary types dynamically when type switches aren't enough.
