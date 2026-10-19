---
title: "Interfaces in Go: Implicit Satisfaction & Composition"
description: "How interfaces work in Go — implicit satisfaction, small single-method interfaces, standard library patterns (io.Reader), composition, and the nil interface trap."
tags:
  - architecture
  - languages
  - golang
  - interfaces
  - oop
date: 2026-10-19
aliases:
  - Architecture/languages/golang/interfaces
---

# Interfaces in Go: Implicit Satisfaction & Composition 🧩

Interfaces in Go are different from almost every other mainstream language. There is **no `implements` keyword**. If a concrete type defines the methods declared by an interface, it satisfies that interface **implicitly and automatically**.

This simple design choice decouples packages, makes unit testing effortless, and avoids rigid inheritance trees.

---

## 1. Defining and Implementing an Interface

An **Interface** specifies a set of method signatures. Any type that implements those methods satisfies the interface:

```go
package main

import "fmt"

// 1. Define the Interface
type Greeter interface {
	Greet() string
}

// 2. Concrete Type Human
type Human struct {
	Name string
}

func (h Human) Greet() string {
	return "Hello, my name is " + h.Name
}

// 3. Concrete Type Robot
type Robot struct {
	Model string
}

func (r Robot) Greet() string {
	return "BEEP BOOP: Unit " + r.Model + " online"
}

// Polymorphic function accepting ANY Greeter!
func PrintGreeting(g Greeter) {
	fmt.Println(g.Greet())
}

func main() {
	h := Human{Name: "Alice"}
	r := Robot{Model: "RX-78"}

	// Both satisfy Greeter implicitly!
	PrintGreeting(h) // Hello, my name is Alice
	PrintGreeting(r) // BEEP BOOP: Unit RX-78 online
}
```

---

## 2. Idiomatic Go: Keep Interfaces Small

The Go standard library favors small, focused interfaces—often with **only a single method**:

- `io.Reader`: `Read(p []byte) (n int, err error)`
- `io.Writer`: `Write(p []byte) (n int, err error)`
- `fmt.Stringer`: `String() string`
- `error`: `Error() string`

> _"The bigger the interface, the weaker the abstraction."_ — Rob Pike

Because `io.Reader` has only one method, an HTTP request body, an in-memory buffer (`bytes.Buffer`), a file (`os.File`), a TLS socket, and a gzip decompressor all satisfy `io.Reader`. Any function written to accept `io.Reader` can process data from all of them!

---

## 3. Interface Composition (Embedding Interfaces)

Just like structs, interfaces can embed other interfaces to form composite contracts:

```go
package storage

import "io"

// ReadWriter embeds Reader and Writer
type ReadWriter interface {
	io.Reader
	io.Writer
}

// ReadWriteCloser embeds ReadWriter and Closer
type ReadWriteCloser interface {
	ReadWriter
	io.Closer
}
```

---

## 4. Dependency Injection for Testing (The Real Superpower)

In Go, **the consumer defines the interface, not the producer**. This makes mocking external dependencies in unit tests trivial:

```go
package user

// 1. The service defines the MINIMAL contract it needs from the database:
type UserRepository interface {
	GetEmailByID(userID int64) (string, error)
}

type NotificationService struct {
	repo UserRepository // Injected dependency
}

func NewNotificationService(repo UserRepository) *NotificationService {
	return &NotificationService{repo: repo}
}

func (s *NotificationService) Notify(userID int64) error {
	email, err := s.repo.GetEmailByID(userID)
	if err != nil {
		return err
	}
	println("Sending email to:", email)
	return nil
}
```

In your unit test, you don't need a running database or complex mocking library—just pass a simple mock struct that satisfies `UserRepository`!

---

## 5. Structs Having Extra Methods than Interface

If a struct implements _more_ methods than defined in an interface, you can still call the interface methods directly. To access the extra methods, use a **[[Architecture/languages/golang/09-type-assertion|Type Assertion]]**:

```go
type Speaker interface {
	Speak() string
}

type Dog struct {
	Name string
}

func (d Dog) Speak() string { return "Woof!" }
func (d Dog) WagTail()      { println(d.Name, "is wagging tail!") }

func Play(s Speaker) {
	println(s.Speak())

	// To call WagTail(), assert back to concrete type Dog:
	if dog, ok := s.(Dog); ok {
		dog.WagTail()
	}
}
```

---

## 6. The Famous "Nil Interface" Gotcha

In Go, an interface value is a pair: **`(Type, Value)`**. An interface is only `nil` if **BOTH** its Type and Value are `nil`!

```go
package main

import "fmt"

type CustomError struct{}

func (c *CustomError) Error() string { return "custom error" }

func getError(fail bool) error {
	var err *CustomError = nil
	if fail {
		err = &CustomError{}
	}
	return err // ⚠️ WARNING: Returns an interface where Type=*CustomError, Value=nil!
}

func main() {
	err := getError(false)
	// Even though the pointer is nil, the interface is NOT nil!
	if err != nil {
		fmt.Println("⚠️ Bug: err is not nil!", err) // This prints!
	}
}

// ✅ FIX: Return explicit 'nil' rather than an uninitialized typed pointer
func getErrorFixed(fail bool) error {
	if fail {
		return &CustomError{}
	}
	return nil // Explicit nil interface
}
```

---

## Across the Wiki

- [[Architecture/languages/golang/09-type-assertion|Type Assertions & Type Switches]] — Safely extracting concrete values from interfaces.
- [[Architecture/languages/golang/05-structs-and-embedding|Structs & Embedding]] — Creating structs that satisfy interfaces.
- [[Architecture/programming-concepts/composition-vs-inheritance-and-interfaces|Composition vs Inheritance]] — Foundational interface concepts.
