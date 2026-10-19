---
title: "Struct & Request Payload Validation in Go"
description: "Validating API request bodies in Go using go-playground/validator — struct tags, custom validation rules, and returning clean HTTP error responses."
tags:
  - architecture
  - languages
  - golang
  - validation
  - api
date: 2026-10-19
aliases:
  - Architecture/languages/golang/validators
---

# Struct & Request Payload Validation in Go ✅

When microservices receive untrusted user input from HTTP requests, validating that required fields exist, emails are valid, and numbers fall within allowed bounds is critical before processing business logic.

In Go, the industry-standard validation library is **`github.com/go-playground/validator/v10`**, which validates struct fields using declarative tags.

---

## 1. Defining Validation Tags

You define validation constraints alongside your JSON tags:

```go
package main

import (
	"fmt"
	"github.com/go-playground/validator/v10"
)

type RegisterUserRequest struct {
	Username string   `json:"username" validate:"required,min=3,max=32"`
	Email    string   `json:"email"    validate:"required,email"`
	Age      int      `json:"age"      validate:"required,gte=18,lte=120"`
	Roles    []string `json:"roles"    validate:"required,min=1,dive,oneof=admin editor viewer"`
}

var validate = validator.New()

func main() {
	// 1. Valid Request
	valid := RegisterUserRequest{
		Username: "darshan",
		Email:    "darshan@example.com",
		Age:      28,
		Roles:    []string{"admin", "editor"},
	}
	if err := validate.Struct(valid); err == nil {
		fmt.Println("✅ Valid request passed!")
	}

	// 2. Invalid Request
	invalid := RegisterUserRequest{
		Username: "a",               // Too short (min=3)
		Email:    "not-an-email",    // Invalid email
		Age:      15,                // Underage (gte=18)
		Roles:    []string{"hacker"}, // Not one of allowed roles
	}

	if err := validate.Struct(invalid); err != nil {
		for _, err := range err.(validator.ValidationErrors) {
			fmt.Printf("Field '%s' failed tag '%s' (value: '%v')\n",
				err.Field(), err.Tag(), err.Value())
		}
	}
}
```

---

## 2. Common Validation Tags

| Tag          | Meaning                                          | Example                        |
| :----------- | :----------------------------------------------- | :----------------------------- |
| `required`   | Field cannot be zero-value or empty              | `validate:"required"`          |
| `email`      | Valid email address format                       | `validate:"email"`             |
| `min`, `max` | Minimum/maximum string length or numeric value   | `validate:"min=5,max=255"`     |
| `gte`, `lte` | Greater than or equal to / Less than or equal to | `validate:"gte=0,lte=100"`     |
| `oneof`      | Value must be one of the listed options          | `validate:"oneof=usd eur gbp"` |
| `uuid`       | Must be a valid UUID string                      | `validate:"uuid4"`             |
| `dive`       | Validates elements _inside_ a slice or map       | `validate:"dive,min=1"`        |

---

## 3. Formatting Clean HTTP 400 Validation Responses

Don't return raw validator errors to frontend users. Map them into clean, structured JSON errors:

```go
package main

import (
	"encoding/json"
	"net/http"
	"github.com/go-playground/validator/v10"
)

type FieldError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

func formatValidationErrors(err error) []FieldError {
	var fieldErrors []FieldError
	if valErrors, ok := err.(validator.ValidationErrors); ok {
		for _, e := range valErrors {
			msg := fmt.Sprintf("Failed on constraint: %s", e.Tag())
			fieldErrors = append(fieldErrors, FieldError{
				Field:   e.Field(),
				Message: msg,
			})
		}
	}
	return fieldErrors
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	var req RegisterUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if err := validate.Struct(req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]any{
			"error":   "Validation failed",
			"details": formatValidationErrors(err),
		})
		return
	}

	w.WriteHeader(http.StatusOK)
}
```

---

## Across the Wiki

- [[Architecture/languages/golang/22-json-and-struct-tags|JSON Serialization & Struct Tags]] — Unmarshaling incoming JSON payloads.
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/api-error-codes|API Error Codes & RFC 7807]] — Standard problem details format for HTTP errors.
- [[Architecture/languages/golang/23-http-and-graceful-shutdown|HTTP Servers & Middleware]] — Wiring validation into HTTP handlers.
