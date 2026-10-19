---
title: "Time, Numbers, URLs, and Cryptography in Go"
tags:
  - architecture/languages/golang
  - golang/standard-library
date: 2026-04-19
description: "Master time manipulation, monotonic clocks, epoch timestamps, random number generation, string conversions, URL parsing, SHA-256 hashing, and Base64 encoding in Go."
aliases:
  - Architecture/languages/golang/time-numbers-urls-and-crypto
---

# Time, Numbers, URLs, and Cryptography in Go

Go's standard library provides high-performance, battle-tested packages for working with temporal data, numerical parsing, networking primitives, and cryptographic digests. This guide covers the essential tools used daily across backend and cloud systems.

---

## 1. Time, Monotonic Clocks, and Epoch

Go's `time.Time` values carry both a wall clock (for calendar readings) and an internal monotonic clock reading (for measuring durations unaffected by system clock jumps or NTP adjustments).

### Operations, Durations, and Unix Epochs

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	now := time.Now()
	fmt.Println("Current time:", now)

	// Constructing custom time (Year, Month, Day, Hour, Min, Sec, Nsec, Location)
	past := time.Date(2024, time.January, 15, 10, 30, 0, 0, time.UTC)
	diff := now.Sub(past)
	fmt.Printf("Elapsed hours since past date: %.1f hours\n", diff.Hours())

	// Arithmetic with Add and AddDate
	future := now.Add(48 * time.Hour)
	fmt.Println("48 hours from now:", future.Format(time.RFC3339))

	// Unix Epoch (seconds, milliseconds, nanoseconds)
	secs := now.Unix()
	nanos := now.UnixNano()
	millis := now.UnixMilli()
	fmt.Printf("Epoch secs: %d, millis: %d, nanos: %d\n", secs, millis, nanos)

	// Reconstructing time from Unix epoch
	reconstructed := time.Unix(secs, 0)
	fmt.Println("Reconstructed UTC:", reconstructed.UTC())
}
```

---

## 2. Time Formatting and Parsing

Unlike languages that use strftime directives (`%Y-%m-%d`), Go uses a reference layout timestamp:

> **Reference Date:** `Mon Jan 2 15:04:05 MST 2006`  
> (Mnemonic: `1 2 3 4 5 6 -700` corresponding to month, day, hour, minute, second, year, timezone)

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	t := time.Now().UTC()

	// Predefined layouts
	fmt.Println("RFC3339:", t.Format(time.RFC3339))
	fmt.Println("RFC1123:", t.Format(time.RFC1123))

	// Custom layouts using reference numbers
	customLayout := "2006-01-02 15:04:05"
	formatted := t.Format(customLayout)
	fmt.Println("Formatted custom:", formatted)

	// Parsing strings back into time.Time
	input := "2026-10-15 08:30:00"
	parsed, err := time.Parse(customLayout, input)
	if err != nil {
		panic(err)
	}
	fmt.Println("Parsed time:", parsed)

	// Parsing with explicit location/timezone
	loc, _ := time.LoadLocation("America/New_York")
	parsedInLoc, _ := time.ParseInLocation(customLayout, input, loc)
	fmt.Println("Parsed in NY:", parsedInLoc)
}
```

---

## 3. Random Numbers: Pseudo-Random vs. Cryptographic

Go provides two packages for randomness:

1. `math/rand/v2` (Go 1.22+) for high-speed simulation, jitter, and shuffle (not cryptographically secure).
2. `crypto/rand` for tokens, secret keys, salts, and nonces.

```go
package main

import (
	crand "crypto/rand"
	"encoding/hex"
	"fmt"
	mrand "math/rand/v2"
)

func main() {
	// 1. Pseudo-random via math/rand/v2 (auto-seeded, concurrency-safe global generator)
	fmt.Println("Random int [0, 100):", mrand.IntN(100))
	fmt.Println("Random float64 [0.0, 1.0):", mrand.Float64())

	// Shuffling a slice
	items := []string{"apple", "banana", "cherry", "date"}
	mrand.Shuffle(len(items), func(i, j int) {
		items[i], items[j] = items[j], items[i]
	})
	fmt.Println("Shuffled slice:", items)

	// 2. Cryptographically secure random tokens via crypto/rand
	tokenBytes := make([]byte, 16) // 128-bit entropy
	if _, err := crand.Read(tokenBytes); err != nil {
		panic(err)
	}
	tokenHex := hex.EncodeToString(tokenBytes)
	fmt.Printf("Secure random hex token (32 chars): %s\n", tokenHex)
}
```

---

## 4. Number Parsing (`strconv`)

Converting strings to numbers and numbers to strings is handled by `strconv`.

```go
package main

import (
	"fmt"
	"strconv"
)

func main() {
	// Parse Float (bitSize: 64 or 32)
	f, err := strconv.ParseFloat("3.1415926535", 64)
	if err != nil {
		panic(err)
	}
	fmt.Printf("Parsed float: %.4f\n", f)

	// Parse Int (base 0 auto-detects 0x hex, 0b binary, 0 octal, or base 10)
	i, err := strconv.ParseInt("0x2A", 0, 64)
	if err != nil {
		panic(err)
	}
	fmt.Println("Parsed hex integer:", i) // 42

	// Fast ASCII to Int (base 10 shorthand)
	num, _ := strconv.Atoi("1024")
	fmt.Println("Atoi:", num)

	// Format conversions (Int to String)
	strVal := strconv.Itoa(999)
	fmt.Println("Itoa:", strVal)

	// Format Int with base
	binStr := strconv.FormatInt(255, 2)
	fmt.Println("255 in binary:", binStr)

	// Parse Boolean
	b, _ := strconv.ParseBool("true") // accepts 1, t, T, TRUE, true, etc.
	fmt.Println("ParseBool:", b)
}
```

---

## 5. URL Parsing (`net/url`)

The `net/url` package breaks URIs into protocol, user authentication, host, path, query parameters, and fragments.

```go
package main

import (
	"fmt"
	"net/url"
)

func main() {
	raw := "postgres://admin:secret123@db.internal.net:5432/production?sslmode=disable&pool=20#metrics"

	u, err := url.Parse(raw)
	if err != nil {
		panic(err)
	}

	fmt.Println("Scheme:  ", u.Scheme)
	fmt.Println("Host:    ", u.Host)
	fmt.Println("Hostname:", u.Hostname())
	fmt.Println("Port:    ", u.Port())
	fmt.Println("Path:    ", u.Path)
	fmt.Println("Fragment:", u.Fragment)

	// User info
	if u.User != nil {
		fmt.Println("Username:", u.User.Username())
		pass, _ := u.User.Password()
		fmt.Println("Password:", pass)
	}

	// Query parameters
	queryParams, _ := url.ParseQuery(u.RawQuery)
	fmt.Println("sslmode:", queryParams.Get("sslmode"))
	fmt.Println("pool:   ", queryParams.Get("pool"))

	// Constructing / Modifying URLs
	queryParams.Set("pool", "50")
	queryParams.Add("timeout", "30s")
	u.RawQuery = queryParams.Encode()
	fmt.Println("Updated URL:", u.String())
}
```

---

## 6. SHA-256 Hashes and Cryptographic Digests

Cryptographic hashes compute deterministic fixed-size checksums from arbitrary byte payloads.

```go
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
)

func main() {
	input := "cloud-native microservice architecture payload"

	// One-shot hashing
	sum := sha256.Sum256([]byte(input))
	hexDigest := hex.EncodeToString(sum[:])
	fmt.Println("SHA-256:", hexDigest)

	// Streaming hash via io.Writer (ideal for large streams/files)
	hasher := sha256.New()
	hasher.Write([]byte("chunk 1: headers; "))
	hasher.Write([]byte("chunk 2: body data"))
	streamSum := hasher.Sum(nil)
	fmt.Printf("Streaming SHA-256: %x\n", streamSum)
}
```

---

## 7. Base64 Encoding and Decoding

Go supports both standard Base64 (with `+` and `/`) and URL-safe Base64 (using `-` and `_`).

```go
package main

import (
	"encoding/base64"
	"fmt"
)

func main() {
	raw := []byte("https://api.example.com/oauth/callback?code=xyz&token=abc")

	// Standard encoding
	stdEncoded := base64.StdEncoding.EncodeToString(raw)
	fmt.Println("Std Base64: ", stdEncoded)

	// URL-Safe encoding (safe for query strings and URL paths)
	urlEncoded := base64.URLEncoding.EncodeToString(raw)
	fmt.Println("URL Base64: ", urlEncoded)

	// Decoding
	decodedBytes, err := base64.URLEncoding.DecodeString(urlEncoded)
	if err != nil {
		panic(err)
	}
	fmt.Println("Decoded:    ", string(decodedBytes))
}
```

---

## Related Topics

- [[Architecture/languages/golang/12-strings-templates-and-regex|Strings, Templates, and Regex]] — String manipulation and pattern matching.
- [[Architecture/languages/golang/19-files-directories-and-embed|Files, Directories, and Embed]] — Reading, writing, and embedding system resources.
- [[Architecture/languages/golang/22-json-and-struct-tags|JSON and Struct Tags]] — Structured serialization.
