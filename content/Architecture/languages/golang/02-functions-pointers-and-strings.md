---
title: "Functions, Pointers & UTF-8 Strings in Go"
description: "Mastering Go functions, multiple return values, variadic parameters, recursion, pointers in Go, and UTF-8 strings vs runes."
tags:
  - architecture
  - languages
  - golang
  - functions
  - pointers
  - strings
date: 2026-10-19
aliases:
  - Architecture/languages/golang/functions-pointers-and-strings
---

# Functions, Pointers & UTF-8 Strings in Go 🧵

Functions and pointers are central to Go. Understanding how Go handles **multiple return values**, **pointers**, and **UTF-8 runes** prevents subtle bugs in string parsing and memory mutation.

---

## 1. Functions & Multiple Return Values

In Go, functions are explicitly typed and frequently return multiple values (most commonly `(result, error)`):

```go
package main

import (
	"errors"
	"fmt"
)

// Consecutive parameters of the same type can be grouped: (a, b int)
func divide(a, b int) (int, int, error) {
	if b == 0 {
		return 0, 0, errors.New("cannot divide by zero")
	}
	quotient := a / b
	remainder := a % b
	return quotient, remainder, nil
}

func main() {
	q, r, err := divide(10, 3)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Printf("10 / 3 = %d (remainder %d)\n", q, r)

	// Blank identifier '_' to discard unwanted return values
	onlyQuotient, _, _ := divide(20, 4)
	fmt.Println("Quotient only:", onlyQuotient)
}
```

---

## 2. Variadic Functions (`...T`)

A **variadic function** accepts any number of trailing arguments of a specified type:

```go
package main

import "fmt"

func sum(nums ...int) int {
	total := 0
	// 'nums' behaves like a slice []int inside the function
	for _, n := range nums {
		total += n
	}
	return total
}

func main() {
	fmt.Println(sum(1, 2))       // 3
	fmt.Println(sum(1, 2, 3, 4)) // 10

	// Unpack an existing slice into a variadic call using '...'
	scores := []int{10, 20, 30}
	fmt.Println(sum(scores...))  // 60
}
```

---

## 3. Recursion in Go

Recursive functions call themselves until reaching a **base case**:

```go
package main

import "fmt"

// Standard recursive factorial
func factorial(n int) int {
	if n <= 1 {
		return 1 // Base case
	}
	return n * factorial(n-1)
}

func main() {
	fmt.Println("5! =", factorial(5)) // 120

	// Anonymous recursive closure (must be declared first!)
	var fib func(n int) int
	fib = func(n int) int {
		if n < 2 {
			return n
		}
		return fib(n-1) + fib(n-2)
	}

	fmt.Println("fib(7) =", fib(7)) // 13
}
```

---

## 4. Pointers in Go: `&` and `*`

Go has pointers, but **no pointer arithmetic** (you cannot do `ptr++` like in C/C++, making Go memory-safe).

- `&x` $\rightarrow$ Evaluates to the memory address of `x`.
- `*ptr` $\rightarrow$ Dereferences the pointer (reads or modifies the value at that address).

```go
package main

import "fmt"

func zeroval(ival int) {
	ival = 0 // Modifies local copy
}

func zeroptr(iptr *int) {
	*iptr = 0 // Modifies original value in memory!
}

func main() {
	i := 1
	fmt.Println("Initial:", i) // 1

	zeroval(i)
	fmt.Println("After zeroval:", i) // 1 (unchanged!)

	zeroptr(&i)
	fmt.Println("After zeroptr:", i) // 0 (mutated!)
	fmt.Println("Address of i:", &i) // e.g. 0xc000014070
}
```

---

## 5. Strings and Runes: UTF-8 in Go

In Go, a **`string` is an immutable sequence of bytes** encoded in UTF-8. A **`rune`** is Go's term for a single Unicode code point (an alias for `int32`).

```go
package main

import (
	"fmt"
	"unicode/utf8"
)

func main() {
	// The word "Hello" in Thai: 5 Unicode characters, but 18 UTF-8 bytes!
	const s = "สวัสดี"

	// 1. len(s) returns BYTE length, NOT character length!
	fmt.Println("Byte count len(s):", len(s)) // 18 bytes

	// 2. utf8.RuneCountInString returns actual character count:
	fmt.Println("Rune count:", utf8.RuneCountInString(s)) // 6 runes

	// 3. Ranging over a string decodes runes automatically:
	for byteIndex, runeValue := range "Go🚀" {
		fmt.Printf("character %c starts at byte index %d\n", runeValue, byteIndex)
	}
	// Output:
	// character G starts at byte index 0
	// character o starts at byte index 1
	// character 🚀 starts at byte index 2 (Takes 4 bytes! Next char would be at index 6)
}
```

---

## Across the Wiki

- [[Architecture/languages/golang/06-methods|Go Methods]] — Passing pointers as method receivers.
- [[Architecture/programming-concepts/value-vs-reference-and-pointers|Value vs Reference]] — Language-agnostic memory mechanics.
- [[Architecture/languages/golang/04-slices-and-maps|Slices & Maps]] — Slicing byte arrays and strings.
