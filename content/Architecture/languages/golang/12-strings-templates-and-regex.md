---
title: "Strings, Formatting, Text Templates & Regular Expressions in Go"
description: "Mastering text manipulation in Go — strings package functions, fmt verbs, text/template engine, and regexp pattern matching."
tags:
  - architecture
  - languages
  - golang
  - strings
  - templates
  - regex
date: 2026-10-19
aliases:
  - Architecture/languages/golang/strings-templates-and-regex
---

# Strings, Formatting, Text Templates & Regular Expressions in Go 📝

Text and string processing is fundamental to configuration templating, log parsing, code generation, and API responses. Go provides rich text manipulation tools across the `strings`, `fmt`, `text/template`, and `regexp` packages.

---

## 1. The `strings` Package Functions

The standard library `strings` package provides high-performance, allocation-conscious string operations:

```go
package main

import (
	"fmt"
	"strings"
)

func main() {
	s := "cloud-native-kubernetes"

	fmt.Println("Contains 'native':", strings.Contains(s, "native")) // true
	fmt.Println("HasPrefix 'cloud':", strings.HasPrefix(s, "cloud")) // true
	fmt.Println("Count of '-':", strings.Count(s, "-"))             // 2
	fmt.Println("ToUpper:", strings.ToUpper(s))

	// Splitting and Joining
	parts := strings.Split(s, "-")
	fmt.Printf("Split: %q\n", parts) // ["cloud" "native" "kubernetes"]
	fmt.Println("Joined:", strings.Join(parts, "/")) // cloud/native/kubernetes

	// Replacing
	fmt.Println("Replaced:", strings.ReplaceAll(s, "kubernetes", "k8s"))
}
```

---

## 2. String Formatting Verbs (`fmt.Printf`)

Go's `fmt` package uses printf-style verbs. The most important verbs for Go developers are:

| Verb       | Meaning                            | Example Output for `User{Name: "Alice", Age: 30}` |
| :--------- | :--------------------------------- | :------------------------------------------------ |
| **`%v`**   | Default value representation       | `{Alice 30}`                                      |
| **`%+v`**  | Struct field names included        | `{Name:Alice Age:30}`                             |
| **`%#v`**  | Go syntax representation           | `main.User{Name:"Alice", Age:30}`                 |
| **`%T`**   | Type of the value                  | `main.User`                                       |
| **`%t`**   | Boolean (`true`/`false`)           | `true`                                            |
| **`%d`**   | Base-10 integer                    | `42`                                              |
| **`%.2f`** | Floating-point with 2 decimals     | `3.14`                                            |
| **`%q`**   | Double-quoted string with escaping | `"hello\nworld"`                                  |
| **`%p`**   | Pointer address                    | `0xc000014070`                                    |

---

## 3. Text & HTML Templates (`text/template`)

The `text/template` package parses templates and applies them to data structures (the same templating engine used by **Helm charts** and **Docker CLI formatting**):

```go
package main

import (
	"os"
	"text/template"
)

type Deployment struct {
	Name     string
	Replicas int
	Envs     []string
}

func main() {
	tmplText := `
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Name }}
spec:
  replicas: {{ .Replicas }}
  env:
  {{- range .Envs }}
    - name: {{ . }}
  {{- end }}
`

	tmpl, err := template.New("k8s").Parse(tmplText)
	if err != nil {
		panic(err)
	}

	dep := Deployment{
		Name:     "payment-service",
		Replicas: 3,
		Envs:     []string{"PORT", "DB_URL", "LOG_LEVEL"},
	}

	// Render directly to standard output or an HTTP response writer!
	tmpl.Execute(os.Stdout, dep)
}
```

---

## 4. Regular Expressions (`regexp`)

Go's `regexp` package implements the RE2 regular expression engine, which guarantees **$\mathcal{O}(N)$ linear-time execution** (preventing catastrophic backtracking ReDoS security vulnerabilities):

```go
package main

import (
	"fmt"
	"regexp"
)

func main() {
	// MustCompile panics if the regex pattern is invalid (ideal for package-level vars)
	re := regexp.MustCompile(`^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$`)

	fmt.Println("Match valid email:", re.MatchString("alex@example.com")) // true
	fmt.Println("Match invalid email:", re.MatchString("invalid-email@"))  // false

	// Finding submatches with capture groups
	extractRe := regexp.MustCompile(`([a-zA-Z]+): (\d+)`)
	line := "Order: 1042, User: 998"

	matches := extractRe.FindAllStringSubmatch(line, -1)
	for _, m := range matches {
		fmt.Printf("Key: %s, Value: %s\n", m[1], m[2])
	}
}
```

---

## Across the Wiki

- [[Architecture/languages/golang/02-functions-pointers-and-strings|Functions, Pointers & Strings]] — UTF-8 strings vs runes.
- [[Architecture/languages/golang/22-json-and-struct-tags|JSON Serialization & Struct Tags]] — JSON marshaling vs templates.
- [[DevOps/devsecops/stage1-code/05-static-analysis-sast|SAST & ReDoS Protection]] — Why RE2's linear time prevents denial-of-service attacks.
