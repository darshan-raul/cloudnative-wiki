---
title: "Methods in Go: Value vs Pointer Receivers"
description: "Defining methods on structs in Go, value receivers vs pointer receivers, nil receiver safety, and when to use each approach."
tags:
  - architecture
  - languages
  - golang
  - methods
  - pointers
date: 2026-10-19
aliases:
  - Architecture/languages/golang/methods
---

# Methods in Go: Value vs Pointer Receivers 🎯

In Go, you don't define classes. Instead, you attach functions directly to types using **Receivers**. A function with a receiver is called a **Method**.

There are two kinds of receivers in Go: **Value Receivers** and **Pointer Receivers**. Choosing the right receiver is essential for data integrity, performance, and avoiding unintended copies.

---

## 1. Syntax Comparison

```go
package main

import "fmt"

type Counter struct {
	Count int
}

// 1. Value Receiver: operates on a COPY of the struct
func (c Counter) ReadValue() int {
	return c.Count
}

// 2. Pointer Receiver: operates directly on the ORIGINAL struct in memory
func (c *Counter) Increment() {
	c.Count++
}

func main() {
	c := Counter{Count: 10}

	c.Increment() // c is modified!
	fmt.Println("After Increment:", c.ReadValue()) // Output: 11
}
```

---

## 2. When to Use Which: The Decision Matrix

| Dimension                  | Pointer Receiver `(s *MyStruct)`                                        | Value Receiver `(s MyStruct)`                          |
| :------------------------- | :---------------------------------------------------------------------- | :----------------------------------------------------- |
| **Mutates Data?**          | **YES:** Modifies the caller's struct fields                            | **NO:** Changes are lost when method returns           |
| **Performance**            | Fast (passes an 8-byte pointer; no data copying)                        | Copies the entire struct bytes onto the call stack     |
| **Concurrency**            | Shared memory: requires locking (`sync.Mutex`) if accessed concurrently | Safe from concurrent mutation (each caller has a copy) |
| **Nil Safety**             | Can be called on a `nil` pointer (needs nil check!)                     | Cannot be called on a nil pointer                      |
| **Interface Satisfaction** | Value `T` might **not** satisfy interface if method is on `*T`!         | Both `T` and `*T` satisfy the interface                |

---

## 3. Practical Example: Account Balance & Scale

```go
package main

import "fmt"

type Account struct {
	Owner   string
	Balance float64
}

// Value receiver: Read-only calculation, does not mutate balance
func (a Account) Statement() string {
	return fmt.Sprintf("Account [%s] has balance: $%.2f", a.Owner, a.Balance)
}

// Pointer receiver: Mutates the account's balance directly
func (a *Account) Deposit(amount float64) error {
	if amount <= 0 {
		return fmt.Errorf("deposit amount must be positive, got %.2f", amount)
	}
	a.Balance += amount
	return nil
}

func main() {
	acc := &Account{Owner: "Alice", Balance: 100.0}

	fmt.Println(acc.Statement()) // Account [Alice] has balance: $100.00
	_ = acc.Deposit(50.0)
	fmt.Println(acc.Statement()) // Account [Alice] has balance: $150.00
}
```

---

## 4. Nil Receiver Methods (A Go Superpower)

In languages like Java or C++, calling a method on a `null` object immediately crashes with a `NullPointerException`.

In Go, **methods on pointer receivers CAN be called on a `nil` pointer**, and the method can handle `nil` gracefully!

```go
package main

import "fmt"

type Node struct {
	Value int
	Next  *Node
}

// Safe even when node is nil!
func (n *Node) GetValue() int {
	if n == nil {
		return 0 // Safe default, no panic!
	}
	return n.Value
}

func main() {
	var head *Node = nil
	// Calling method on nil pointer works cleanly in Go:
	fmt.Println("Head value:", head.GetValue()) // Output: 0
}
```

---

## 5. Golden Rules for Go Methods

1. **If any method modifies the struct $\rightarrow$ Use pointer receivers for all methods** on that struct to maintain consistency.
2. **If the struct is large (e.g., contains many fields or large arrays) $\rightarrow$ Use pointer receivers** to avoid the CPU cost of copying bytes on every call.
3. **If the struct is a small, immutable value type (like `time.Time` or `struct{ X, Y int }`) $\rightarrow$ Use value receivers**.

---

## Across the Wiki

- [[Architecture/languages/golang/05-structs-and-embedding|Structs & Embedding]] — Defining structs and composition.
- [[Architecture/languages/golang/08-interfaces|Go Interfaces]] — How method receiver types affect interface satisfaction.
- [[Architecture/programming-concepts/value-vs-reference-and-pointers|Value vs Reference]] — Memory mechanics of pointer dereferencing.
