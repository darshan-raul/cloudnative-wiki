---
title: "Go Modules, Packages & Standard Project Layout"
description: "How Go organizes code — go.mod and go.sum, exported vs unexported visibility, package organization, and standard cloud-native project layout."
tags:
  - architecture
  - languages
  - golang
  - modules
  - packages
date: 2026-10-19
aliases:
  - Architecture/languages/golang/modules-and-packages
---

# Go Modules, Packages & Standard Project Layout 📦

Go enforces a clean, predictable dependency and packaging model. There are no class-level private/protected keywords, no complex XML/Gradle build scripts, and no global package installation hell.

Understanding how **modules**, **packages**, and **visibility** work is the first step to building maintainable Go services.

---

## 1. What is a Module vs a Package?

- **Package:** A folder containing one or more `.go` files with the same `package name` declaration at the top. Packages are the basic unit of code organization.
- **Module:** A collection of related packages released and versioned together as a single unit, marked by a `go.mod` file at its root.

```
my-service/                  <-- Module Root
├── go.mod                   <-- Module definition & direct dependencies
├── go.sum                   <-- Cryptographic checksums of dependencies
├── cmd/
│   └── api/
│       └── main.go          <-- package main (Executable entry point)
└── internal/
    ├── user/
    │   ├── model.go         <-- package user
    │   └── service.go       <-- package user
    └── database/
        └── db.go            <-- package database
```

---

## 2. Managing Dependencies with `go.mod`

Create a new module with `go mod init`:

```bash
# 1. Initialize a new module (use a repository URL as the module path)
go mod init github.com/myorg/my-service

# 2. Add a dependency to your code and let Go automatically download it
go get github.com/google/uuid

# 3. Clean up unused dependencies and verify checksums
go mod tidy
```

### Anatomy of `go.mod`

```go
module github.com/myorg/my-service

go 1.24.0

require (
    github.com/google/uuid v1.6.0
    github.com/stretchr/testify v1.9.0 // indirect
)
```

- **`go.sum`:** Records the expected cryptographic SHA-256 hashes of the downloaded dependency code. Never edit `go.sum` manually; commit it to Git alongside `go.mod` to guarantee reproducible builds.

---

## 3. Visibility Rule: Capitalization Controls Export

Go does not have `public` or `private` keywords. Visibility is strictly determined by the **first letter of the identifier's name**:

- **Upper Case (`User`, `Save`, `MaxRetries`):** Exported (public) $\rightarrow$ Accessible by other packages.
- **Lower Case (`user`, `hashPassword`, `timeout`):** Unexported (private) $\rightarrow$ Accessible **only** within the declaring package.

```go
package auth

import "time"

// Session is exported (can be used by other packages like 'package main')
type Session struct {
	ID        string    // Exported field
	UserID    int64     // Exported field
	secretKey string    // Unexported field (private to 'package auth')
}

// GenerateToken is exported
func GenerateToken(userID int64) (*Session, error) {
	return &Session{
		ID:        "sess_123",
		UserID:    userID,
		secretKey: generateRandomBytes(), // calls unexported function
	}, nil
}

// generateRandomBytes is unexported (private helper)
func generateRandomBytes() string {
	return "super-secret-bytes"
}
```

---

## 4. Standard Cloud-Native Project Structure

Most modern Go projects (including Kubernetes, Docker, and Terraform) follow the standard directory layout:

| Directory       | Purpose                                                                                                                                   | Visibility Rule            |
| :-------------- | :---------------------------------------------------------------------------------------------------------------------------------------- | :------------------------- |
| **`cmd/`**      | Main entry points. Each subfolder produces a binary (e.g., `cmd/server/main.go`, `cmd/worker/main.go`).                                   | Public executables         |
| **`internal/`** | Private application and library code. The Go compiler **strictly prohibits** external modules from importing anything inside `internal/`. | Private to this repository |
| **`pkg/`**      | Public library code intentionally meant to be consumed by other projects. Use sparingly.                                                  | Publicly importable        |
| **`api/`**      | OpenAPI/Swagger specs, Protocol Buffer (`.proto`) files, or JSON schemas.                                                                 | Contracts                  |

---

## 5. The `init()` Function

Every package can define one or more parameterless `init()` functions that execute automatically before `main()` starts:

```go
package config

import "fmt"

var AppVersion string

func init() {
	// Runs automatically when 'config' is imported
	AppVersion = "v1.4.0"
	fmt.Println("Config package initialized:", AppVersion)
}
```

> [!WARNING]
> **Avoid Complex Logic in `init()`:** Keep `init()` functions minimal. Placing database connection logic or heavy network calls inside `init()` makes unit testing difficult and causes obscure panics during imports.

---

## Across the Wiki

- [[Architecture/programming-concepts/compiled-vs-interpreted|Compiled vs Interpreted Languages]] — How the Go compiler produces native machine binaries.
- [[Architecture/languages/golang/04-slices-and-maps|Slices & Maps]] — Working with Go's core data structures.
- [[Architecture/languages/golang/05-structs-and-embedding|Structs & Embedding]] — Building domain models and composition in Go.
