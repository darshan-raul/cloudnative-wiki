---
title: "Composition vs Inheritance & Interfaces as Contracts"
description: "Why modern software architecture favors composition over inheritance ('has-a' vs 'is-a'), and how interfaces act as clean testable contracts."
tags:
  - architecture
  - programming-concepts
  - oop
  - interfaces
  - design-patterns
date: 2026-10-19
---

# Composition vs Inheritance & Interfaces as Contracts 🧱

One of the most famous pieces of advice in the _Gang of Four_ design patterns book is:

> _"Favor object composition over class inheritance."_

Understanding why inheritance often leads to brittle systems—and why modern languages like **Go** and **Rust** completely omitted class inheritance in favor of **composition and interfaces**—is a fundamental milestone in software design.

---

## 1. Inheritance: The "Is-A" Relationship

In classic Object-Oriented Programming, **Inheritance** lets a child class inherit methods and fields from a parent class:

```
          Vehicle (startEngine, stopEngine)
            ▲
            │ (Inherits)
          Car (startEngine, stopEngine, openSunroof)
            ▲
            │ (Inherits)
      ElectricCar (???) ── "Wait, electric cars don't have engines!"
```

### The Problem: The Fragile Base Class & Gorilla-Banana Problem

As systems grow, deep inheritance trees become rigid and brittle:

1. **The Gorilla-Banana Problem:** _"You wanted a banana, but what you got was a gorilla holding the banana and the entire jungle."_ Subclasses inherit fields and behaviors they don't want or need.
2. **Coupling:** Changing a single method in the base class can silently break dozens of distant subclasses across the repository.

---

## 2. Composition: The "Has-A" Relationship (Lego Bricks)

Instead of saying what an object **is** (a child of another class), **Composition** builds complex objects by assembling smaller, focused components that the object **has**:

```
┌──────────────────────────────────────────────┐
│                  ElectricCar                 │
│                                              │
│  [ ElectricMotor ]     [ BatteryPack ]       │
│  ├── start()           ├── charge()          │
│                                              │
│  [ GPSNavigation ]     [ SoundSystem ]       │
└──────────────────────────────────────────────┘
```

```go
// Clean composition in Go (no inheritance!)
type Battery struct {
	CapacityKWh int
}

func (b *Battery) Charge() {
	println("Charging battery...")
}

type ElectricCar struct {
	Model   string
	Battery Battery // Has-A Battery!
}

func main() {
	tesla := ElectricCar{
		Model:   "Model Y",
		Battery: Battery{CapacityKWh: 75},
	}
	tesla.Battery.Charge()
}
```

### Why Composition Wins in Production

- **Swapability:** You can easily swap out `Battery` for a `MockBattery` in unit tests.
- **Flexibility:** You can combine behaviors without being forced into an unnatural parent-child hierarchy.

---

## 3. Interfaces as Contracts

An **Interface** is simply a **contract**: it specifies _what_ actions must be supported, without dictating _how_ they are implemented.

Think of a standard electrical wall outlet:

- The outlet defines an interface: two prongs delivering 120V AC.
- A lamp, a laptop charger, and a toaster can all plug into the same outlet because they all adhere to the same interface.

```go
// The Contract: Anything that knows how to Save an order is a StorageEngine!
type StorageEngine interface {
	Save(orderID string, data []byte) error
}

// 1. Production implementation: Saves to PostgreSQL
type PostgresStore struct { /* db connection */ }
func (p *PostgresStore) Save(orderID string, data []byte) error {
	// ... writes SQL insert ...
	return nil
}

// 2. Unit test implementation: Saves in-memory (No database needed!)
type FakeStore struct {
	SavedOrders map[string][]byte
}
func (f *FakeStore) Save(orderID string, data []byte) error {
	f.SavedOrders[orderID] = data
	return nil
}
```

### The Power of Consumer-Driven Interfaces

In Go, interfaces are satisfied **implicitly** (structural typing). You don't have to write `class PostgresStore implements StorageEngine`. If the struct has the `Save()` method, it satisfies the interface automatically!

This makes writing clean unit tests and replacing dependencies (like swapping an S3 client for local disk storage) trivial.

---

## Across the Wiki

- [[Architecture/languages/golang/interfaces|Go Interfaces Deep Dive]] — Small interfaces, composition, and avoiding interface pollution.
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/testing/test-doubles-mocks-stubs-fakes|Test Doubles, Mocks & Stubs]] — How interfaces enable robust unit testing.
- [[Architecture/solution-architecture-concepts/foundations/high-cohesion-loose-coupling|High Cohesion & Loose Coupling]] — Architectural benefits of decoupled components.
