---
title: "Structs, Constructors & Composition via Embedding"
description: "Defining structs in Go, the constructor pattern, functional options for clean configuration, and composition via struct embedding."
tags:
  - architecture
  - languages
  - golang
  - structs
  - oop
  - composition
date: 2026-10-19
aliases:
  - Architecture/languages/golang/structs-and-embedding
---

# Structs, Constructors & Composition via Embedding 🏗️

Go is not a classical Object-Oriented language: **there are no `class` keywords and no class inheritance trees**.

Instead, Go models data using **Structs** and achieves reuse and modularity using **Composition via Struct Embedding**.

---

## 1. Defining Structs & Basic Instantiation

A **Struct** is a typed collection of fields:

```go
package main

import "fmt"

type User struct {
	ID        int64
	Username  string
	Email     string
	IsActive  bool
}

func main() {
	// 1. Struct literal with named fields (Best Practice)
	u1 := User{
		ID:       101,
		Username: "darshan",
		Email:    "darshan@example.com",
		IsActive: true,
	}

	// 2. Pointer to struct with new() or address-of &
	u2 := &User{ID: 102, Username: "alex"}

	fmt.Println(u1.Username)
	fmt.Println(u2.ID) // Go automatically dereferences pointers for struct field access!
}
```

---

## 2. Constructor Functions (`New...`)

Because Go does not have built-in class constructors, idiomatic Go uses a constructor function (conventionally named `New` or `New<Type>`) to validate inputs and set sensible defaults:

```go
package server

import (
	"errors"
	"time"
)

type Config struct {
	Port    int
	Timeout time.Duration
}

type Server struct {
	cfg Config
}

// NewServer validates arguments and returns a pointer to an initialized Server
func NewServer(port int) (*Server, error) {
	if port <= 0 || port > 65535 {
		return nil, errors.New("port must be between 1 and 65535")
	}

	return &Server{
		cfg: Config{
			Port:    port,
			Timeout: 30 * time.Second, // Default timeout
		},
	}, nil
}
```

---

## 3. The Functional Options Pattern (For Complex Configs)

When initializing services with many optional settings, avoid huge constructor parameter lists with the **Functional Options Pattern**:

```go
package main

import (
	"fmt"
	"time"
)

type Server struct {
	host    string
	port    int
	timeout time.Duration
	tls     bool
}

// Option is a function that modifies a Server
type Option func(*Server)

func WithTimeout(t time.Duration) Option {
	return func(s *Server) {
		s.timeout = t
	}
}

func WithTLS(enabled bool) Option {
	return func(s *Server) {
		s.tls = enabled
	}
}

func New(host string, port int, opts ...Option) *Server {
	srv := &Server{
		host:    host,
		port:    port,
		timeout: 10 * time.Second, // default
		tls:     false,             // default
	}

	for _, opt := range opts {
		opt(srv) // Apply each option
	}
	return srv
}

func main() {
	// Clean, flexible instantiation!
	s := New("0.0.0.0", 8080, WithTimeout(5*time.Second), WithTLS(true))
	fmt.Printf("%+v\n", s)
}
```

---

## 4. Composition via Struct Embedding (No Inheritance!)

Instead of subclassing, Go lets you **embed** one struct directly into another. The outer struct automatically gains all the fields and methods of the inner struct (**method promotion**):

```go
package main

import "fmt"

type Logger struct{}

func (l Logger) Log(msg string) {
	fmt.Println("[LOG]:", msg)
}

type Database struct {
	DSN string
}

func (db Database) Query(sql string) {
	fmt.Printf("Executing SQL '%s' on %s\n", sql, db.DSN)
}

// Service embeds both Logger and Database!
type OrderService struct {
	Logger   // Embedded anonymous field
	Database // Embedded anonymous field
	TaxRate  float64
}

func main() {
	svc := OrderService{
		Database: Database{DSN: "postgres://localhost:5432/orders"},
		TaxRate:  0.08,
	}

	// Methods from Logger and Database are promoted directly to OrderService!
	svc.Log("Starting OrderService")
	svc.Query("SELECT * FROM orders WHERE status = 'pending'")
}
```

If the outer struct defines a method with the same name, it overrides the embedded method while still allowing you to access the original via `svc.Logger.Log()`.

---

## Across the Wiki

- [[Architecture/programming-concepts/composition-vs-inheritance-and-interfaces|Composition vs Inheritance]] — The conceptual advantages of composition.
- [[Architecture/languages/golang/06-methods|Go Methods]] — Defining pointer and value receiver methods on structs.
- [[Architecture/languages/golang/08-interfaces|Go Interfaces]] — Writing interfaces satisfied by structs.
