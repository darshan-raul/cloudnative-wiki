---
title: "Variables, Constants, Control Flow & Enums in Go"
description: "Mastering Go fundamentals — values, variable declaration, constants, for loops (4 styles), if/else with short statements, switch, and enums with iota."
tags:
  - architecture
  - languages
  - golang
  - basics
  - control-flow
date: 2026-10-19
aliases:
  - Architecture/languages/golang/variables-constants-and-control-flow
---

# Variables, Constants, Control Flow & Enums in Go 🚦

Go was engineered for simplicity, readability, and minimalism. Unlike languages with dozens of keyword variations, Go has only **25 keywords** and a single loop construct (`for`).

---

## 1. Values, Variables & Constants

### Basic Values

Go has familiar primitive types: strings, integers (`int`, `int64`), floats (`float64`), and booleans (`bool`):

```go
package main

import "fmt"

func main() {
	// String concatenation
	fmt.Println("go" + "lang")

	// Arithmetic
	fmt.Println("7.0/3.0 =", 7.0/3.0)

	// Booleans
	fmt.Println(true && false)
	fmt.Println(!true)
}
```

### Declaring Variables (`var` vs `:=`)

In Go, variables are initialized with either `var` or the short declaration `:=`:

```go
package main

import "fmt"

func main() {
	// 1. var with explicit type
	var name string = "Alice"

	// 2. var with type inference
	var age = 30

	// 3. Short declaration operator ':=' (Inside functions only!)
	city := "San Francisco"

	// 4. Zero values: Variables declared without a value get initialized to ZERO
	var count int       // 0
	var price float64   // 0.0
	var active bool     // false
	var token string    // "" (empty string)

	fmt.Println(name, age, city, count, price, active, token)
}
```

### Constants & Untyped Literals

Constants are declared using the `const` keyword. In Go, numeric constants are high-precision **untyped** values until assigned to a variable:

```go
const Pi = 3.14159265359
const TimeoutSeconds = 30

// Typed constant
const MaxBufferSize int = 1024
```

---

## 2. Enums Using `iota`

Go does not have a dedicated `enum` keyword. Instead, idiomatic Go defines custom types and assigns sequential integer values using **`iota`**:

```go
package main

import "fmt"

type ServerState int

// iota starts at 0 and increments by 1 for each line in the const block
const (
	StateIdle ServerState = iota // 0
	StateConnected               // 1
	StateError                   // 2
	StateRetired                 // 3
)

// Implementing fmt.Stringer gives clean text representation
func (s ServerState) String() string {
	switch s {
	case StateIdle:
		return "idle"
	case StateConnected:
		return "connected"
	case StateError:
		return "error"
	case StateRetired:
		return "retired"
	default:
		return "unknown"
	}
}

func main() {
	current := StateConnected
	fmt.Printf("Server state: %s (numeric: %d)\n", current, current)
	// Output: Server state: connected (numeric: 1)
}
```

---

## 3. The `for` Loop: Go's Only Loop Construct

Go has no `while` or `do-while` loops. The `for` keyword handles all looping scenarios:

```go
package main

import "fmt"

func main() {
	// 1. Classic 3-component loop
	for i := 0; i < 3; i++ {
		fmt.Print(i, " ")
	}
	fmt.Println()

	// 2. While-style single condition loop
	count := 1
	for count <= 3 {
		fmt.Print(count, " ")
		count++
	}
	fmt.Println()

	// 3. Infinite loop with break and continue
	for {
		if count > 5 {
			break // exit loop
		}
		count++
	}

	// 4. Go 1.22+ integer range loop:
	for i := range 3 {
		fmt.Print(i, " ") // prints: 0 1 2
	}
	fmt.Println()
}
```

---

## 4. `if / else` with Short Statement Initialization

In Go, conditional `if` statements do not need parentheses. Furthermore, Go allows executing a **short statement before the condition**:

```go
package main

import (
	"fmt"
	"math/rand"
)

func main() {
	// Idiomatic pattern: execute a function, initialize a variable, and test it immediately!
	// 'num' only exists within the scope of this if/else block!
	if num := rand.Intn(100); num > 50 {
		fmt.Printf("High number: %d\n", num)
	} else if num == 50 {
		fmt.Println("Exactly fifty!")
	} else {
		fmt.Printf("Low number: %d\n", num)
	}
	// 'num' is out of scope here!
}
```

---

## 5. `switch`: Clean Branching Without `break`

In Go, `switch` cases **break automatically** (no manual `break` needed; use `fallthrough` if you explicitly want fallthrough):

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	// 1. Multiple expressions in a single case
	switch time.Now().Weekday() {
	case time.Saturday, time.Sunday:
		fmt.Println("It's the weekend! 🎉")
	default:
		fmt.Println("It's a weekday 💻")
	}

	// 2. Tagless switch (alternative to chained if/else)
	hour := time.Now().Hour()
	switch {
	case hour < 12:
		fmt.Println("Good morning!")
	case hour < 17:
		fmt.Println("Good afternoon!")
	default:
		fmt.Println("Good evening!")
	}
}
```

---

## Across the Wiki

- [[Architecture/languages/golang/04-slices-and-maps|Slices & Maps in Go]] — Looping over collections with `for i, v := range`.
- [[Architecture/languages/golang/02-functions-pointers-and-strings|Functions, Pointers & Strings]] — Function syntax and multiple return values.
- [[Architecture/languages/golang/09-type-assertion|Type Assertions & Type Switches]] — Switching on dynamic interface types.
