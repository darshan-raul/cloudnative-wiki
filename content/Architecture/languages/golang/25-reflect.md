---
title: "Reflection in Go: Runtime Type & Value Introspection"
description: "How Go's reflect package works — reflect.Type, reflect.Value, inspecting struct tags, dynamic invocation, and performance trade-offs."
tags:
  - architecture
  - languages
  - golang
  - reflect
  - metaprogramming
date: 2026-10-19
aliases:
  - Architecture/languages/golang/reflect
---

# Reflection in Go: Runtime Type & Value Introspection 🪞

Go is a statically typed language, but it provides the **`reflect`** package to inspect and manipulate types and values dynamically at runtime.

Reflection powers tools like `encoding/json`, database ORMs (`gorm`, `sqlx`), and template engines. However, because reflection bypasses compile-time type safety and has significant CPU overhead, it should be used judiciously.

---

## 1. The Two Pillars: `reflect.Type` and `reflect.Value`

Every variable in Go has a compile-time **Type** and a runtime **Value**:

```go
package main

import (
	"fmt"
	"reflect"
)

func main() {
	x := 42

	// 1. reflect.TypeOf: Inspects the TYPE (Type and Kind)
	t := reflect.TypeOf(x)
	fmt.Println("Type:", t.Name()) // int
	fmt.Println("Kind:", t.Kind()) // int (Kind is the underlying primitive family)

	// 2. reflect.ValueOf: Inspects and reads the VALUE
	v := reflect.ValueOf(x)
	fmt.Println("Value:", v.Int()) // 42
}
```

---

## 2. Inspecting Struct Fields and Tags

The most common real-world use of reflection is inspecting struct fields and reading custom struct tags:

```go
package main

import (
	"fmt"
	"reflect"
)

type DatabaseModel struct {
	ID        int64  `db:"id" primary_key:"true"`
	Username  string `db:"username" max_length:"50"`
	IsAdmin   bool   `db:"is_admin"`
}

func inspectStructTags(val any) {
	t := reflect.TypeOf(val)

	// If a pointer was passed, get the underlying struct type
	if t.Kind() == reflect.Pointer {
		t = t.Elem()
	}

	fmt.Printf("Inspecting Struct: %s (Fields: %d)\n", t.Name(), t.NumField())

	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		dbColumn := field.Tag.Get("db")
		isPK := field.Tag.Get("primary_key")

		fmt.Printf("  Field: %-10s | Type: %-8s | DB Column: %-10s | PK: %s\n",
			field.Name, field.Type, dbColumn, isPK)
	}
}

func main() {
	m := DatabaseModel{ID: 1, Username: "alice"}
	inspectStructTags(m)
}
```

---

## 3. Modifying Values via Reflection (`Elem()` & `CanSet()`)

To modify a value through reflection, you must pass a **pointer** to `reflect.ValueOf()` and call **`.Elem()`** to reach the settable variable:

```go
package main

import (
	"fmt"
	"reflect"
)

func main() {
	x := 10

	// ❌ Passing value directly: Cannot set!
	// v := reflect.ValueOf(x)
	// v.SetInt(20) // Panics: reflect: reflect.Value.SetInt using unaddressable value

	// ✅ Passing pointer:
	v := reflect.ValueOf(&x).Elem()
	if v.CanSet() {
		v.SetInt(20)
	}

	fmt.Println("New value of x:", x) // Output: 20
}
```

---

## 4. When NOT to Use Reflection

1. **When an Interface or Generics will do:** Interfaces provide clean polymorphism with zero reflection overhead.
2. **In High-Throughput Request Paths:** Reflection is ~10x–50x slower than direct field access because it involves runtime pointer chasing and dynamic heap allocations.
3. **When Compile-Time Safety Matters:** Reflection errors (like misspelling a struct field name) panic at runtime instead of being caught by the compiler.

---

## Across the Wiki

- [[Architecture/languages/golang/22-json-and-struct-tags|JSON & Struct Tags]] — Real-world application of reflection.
- [[Architecture/languages/golang/08-interfaces|Go Interfaces]] — Static polymorphism without reflection.
- [[Architecture/languages/golang/09-type-assertion|Type Assertions & Type Switches]] — Fast type extraction without reflection.
