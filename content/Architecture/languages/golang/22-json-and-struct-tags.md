---
title: "JSON Serialization & Struct Tags in Go"
description: "Mastering JSON in Go — json.Marshal, json.Unmarshal, struct tags, omitempty, custom marshaling, and stream decoding for microservices."
tags:
  - architecture
  - languages
  - golang
  - json
  - serialization
date: 2026-10-19
aliases:
  - Architecture/languages/golang/json-and-struct-tags
---

# JSON Serialization & Struct Tags in Go 📦

Almost all backend Go microservices process JSON payloads. In Go, serialization between in-memory structs and JSON text is handled by the **`encoding/json`** standard library package using **Struct Tags**.

---

## 1. Struct Tags & `json.Marshal` / `json.Unmarshal`

Struct tags (written inside backticks) inform the JSON serializer how to map struct fields to JSON keys:

```go
package main

import (
	"encoding/json"
	"fmt"
	"time"
)

type User struct {
	ID        int64     `json:"id"`
	Username  string    `json:"username"`
	Email     string    `json:"email,omitempty"` // Omits field if empty string!
	Password  string    `json:"-"`               // Never serialize to JSON!
	CreatedAt time.Time `json:"created_at"`
}

func main() {
	// 1. Marshal (Struct -> JSON bytes)
	u := User{
		ID:        101,
		Username:  "darshan",
		Password:  "supersecret",
		CreatedAt: time.Now(),
	}

	data, err := json.MarshalIndent(u, "", "  ")
	if err != nil {
		panic(err)
	}
	fmt.Println(string(data))
	// Output: Password is excluded, Email is omitted because it's empty!

	// 2. Unmarshal (JSON bytes -> Struct)
	rawJSON := []byte(`{"id": 202, "username": "alex", "email": "alex@example.com"}`)
	var newUser User
	if err := json.Unmarshal(rawJSON, &newUser); err != nil {
		panic(err)
	}
	fmt.Printf("Parsed user: %+v\n", newUser)
}
```

---

## 2. Common JSON Struct Tag Options

| Tag                      | Behavior                                                                           |
| :----------------------- | :--------------------------------------------------------------------------------- |
| `json:"user_id"`         | Maps field to JSON key `"user_id"`                                                 |
| `json:"email,omitempty"` | Omits field from JSON output if it has its zero value (`""`, `0`, `nil`, `false`)  |
| `json:"-"`               | Completely ignores this field in both marshaling and unmarshaling                  |
| `json:"-,"`              | Maps field to a literal JSON key `"-"`                                             |
| `json:",string"`         | Encodes a numeric/boolean field as a JSON string (e.g., `42` $\rightarrow$ `"42"`) |

---

## 3. The `omitempty` Gotcha with Booleans and Zero Values

If a boolean field represents an explicit `false` (e.g., `IsActive: false`), adding `omitempty` will **completely drop the field from the JSON output** because `false` is the zero value!

```go
// ❌ GOTCHA: If IsActive is false, omitempty drops it!
type Settings struct {
	Notifications bool `json:"notifications,omitempty"`
}

// ✅ FIX: Use a pointer so you can distinguish between false vs missing (nil)
type SettingsFixed struct {
	Notifications *bool `json:"notifications,omitempty"`
}
```

---

## 4. Streaming JSON with `json.NewDecoder` (Memory Efficient)

When reading JSON request bodies in an HTTP server, **never read the entire body into memory with `io.ReadAll` first**. Stream it directly with `json.NewDecoder`:

```go
package main

import (
	"encoding/json"
	"net/http"
)

type CreateUserRequest struct {
	Username string `json:"username"`
	Email    string `json:"email"`
}

func handleCreateUser(w http.ResponseWriter, r *http.Request) {
	// 1. Enforce max body size to protect against large memory DoS attacks!
	r.Body = http.MaxBytesReader(w, r.Body, 1048576) // Max 1 MB

	var req CreateUserRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields() // Reject unexpected JSON fields!

	if err := dec.Decode(&req); err != nil {
		http.Error(w, "Malformed JSON: "+err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"status": "created"})
}
```

---

## 5. Custom JSON Serialization (`json.Marshaler`)

Implement `json.Marshaler` or `json.Unmarshaler` when you need custom date formats or encrypted values:

```go
type DateOnly time.Time

func (d DateOnly) MarshalJSON() ([]byte, error) {
	formatted := fmt.Sprintf("%q", time.Time(d).Format("2006-01-02"))
	return []byte(formatted), nil
}
```

---

## 5. XML Serialization (`encoding/xml`)

The `encoding/xml` package works similarly to `encoding/json`, using struct tags like `xml:"name,attr"`, `xml:",chardata"`, and nested paths.

```go
package main

import (
	"encoding/xml"
	"fmt"
)

type Plant struct {
	XMLName xml.Name `xml:"plant"`
	Id      int      `xml:"id,attr"`
	Name    string   `xml:"name"`
	Origin  []string `xml:"origin>country"`
}

func main() {
	coffee := &Plant{
		Id:     27,
		Name:   "Arabica Coffee",
		Origin: []string{"Ethiopia", "Colombia"},
	}

	// Marshaling struct to XML with indentation
	out, err := xml.MarshalIndent(coffee, "", "  ")
	if err != nil {
		panic(err)
	}
	fmt.Println(xml.Header + string(out))

	// Unmarshaling XML back into a Go struct
	var parsed Plant
	if err := xml.Unmarshal(out, &parsed); err != nil {
		panic(err)
	}
	fmt.Printf("Parsed Plant: ID=%d, Name=%q, Origins=%v\n", parsed.Id, parsed.Name, parsed.Origin)
}
```

---

## Across the Wiki

- [[Architecture/programming-concepts/serialization-and-encoding-basics|Serialization Basics]] — Text formats (JSON) vs binary formats (Protobuf).
- [[Architecture/languages/golang/24-validators|Go Struct Validation]] — Validating unmarshaled JSON payloads.
- [[Architecture/languages/golang/25-reflect|Go Reflection]] — How the JSON package reads struct tags at runtime.
