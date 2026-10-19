---
title: "Files, Directories, and Embed in Go"
tags:
  - architecture/languages/golang
  - golang/io
date: 2026-04-19
description: "Master file I/O, buffered reading/writing, line filters, path manipulation, directory traversal, temporary files, and compiling static assets with go:embed in Go."
aliases:
  - Architecture/languages/golang/files-directories-and-embed
---

# Files, Directories, and Embed in Go

Handling files and filesystems is central to backend development, CLI utilities, and containerized microservices. Go provides clean abstractions across the `os`, `io`, `bufio`, `path/filepath`, and `embed` packages.

---

## 1. Reading Files

Go offers three main approaches to reading files: one-shot reads, streaming chunk reads, and buffered readers.

```go
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
)

func main() {
	filePath := "/tmp/example.txt"
	_ = os.WriteFile(filePath, []byte("Line 1: Go Systems\nLine 2: Cloud Native\n"), 0644)
	defer os.Remove(filePath)

	// 1. One-shot read: Reads entire file into memory (good for small configs)
	data, err := os.ReadFile(filePath)
	if err != nil {
		panic(err)
	}
	fmt.Printf("ReadFile (%d bytes):\n%s\n", len(data), string(data))

	// 2. Open file for chunk-by-chunk or seekable streaming
	file, err := os.Open(filePath)
	if err != nil {
		panic(err)
	}
	defer file.Close()

	chunk := make([]byte, 8)
	n, err := file.Read(chunk)
	fmt.Printf("Read %d bytes into chunk: %q\n", n, string(chunk[:n]))

	// 3. Buffered reader (avoids excessive syscalls)
	_, _ = file.Seek(0, io.SeekStart) // rewind to start
	reader := bufio.NewReader(file)
	peeked, _ := reader.Peek(6)
	fmt.Printf("Peeked first 6 bytes: %q\n", string(peeked))
}
```

---

## 2. Writing Files

For writing, Go provides `os.WriteFile`, granular file creation with flags, and buffered writers.

```go
package main

import (
	"bufio"
	"fmt"
	"os"
)

func main() {
	path := "/tmp/write_demo.txt"
	defer os.Remove(path)

	// 1. One-shot atomic-style write
	err := os.WriteFile(path, []byte("initial line\n"), 0644)
	if err != nil {
		panic(err)
	}

	// 2. Open with flags for appending (os.O_APPEND|os.O_CREATE|os.O_WRONLY)
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		panic(err)
	}
	defer f.Close()

	if _, err := f.WriteString("appended line 2\n"); err != nil {
		panic(err)
	}

	// 3. Buffered Writer (flushes batched memory blocks to disk)
	bufWriter := bufio.NewWriter(f)
	_, _ = bufWriter.WriteString("buffered line 3\n")
	_, _ = bufWriter.WriteString("buffered line 4\n")
	_ = bufWriter.Flush() // Explicit flush ensures everything hits the OS page cache

	content, _ := os.ReadFile(path)
	fmt.Println("File contents:\n" + string(content))
}
```

---

## 3. Line Filters and Scanners

A line filter is a common pattern for processing incoming text streams (e.g., parsing log files line-by-line without loading gigantic files into memory).

```go
package main

import (
	"bufio"
	"fmt"
	"strings"
)

func main() {
	rawLogs := "INFO: server listening on :8080\nWARN: high memory utilization\nERROR: database timeout\n"

	// bufio.Scanner breaks input into tokens (lines by default)
	scanner := bufio.NewScanner(strings.NewReader(rawLogs))

	lineCount := 0
	for scanner.Scan() {
		line := scanner.Text()
		lineCount++
		// Filter or transform lines
		if strings.HasPrefix(line, "ERROR") {
			fmt.Printf("[Alert Line %d] %s\n", lineCount, line)
		}
	}

	if err := scanner.Err(); err != nil {
		fmt.Printf("Error scanning input: %v\n", err)
	}
}
```

---

## 4. File Paths (`path/filepath`)

Use `path/filepath` instead of string concatenation to guarantee cross-platform compatibility across Linux, macOS, and Windows.

```go
package main

import (
	"fmt"
	"path/filepath"
)

func main() {
	// Join cleanly normalizes separators
	p := filepath.Join("var", "log", "nginx", "access.log")
	fmt.Println("Joined path:", p)

	// Base, Dir, and Ext
	fmt.Println("Dir: ", filepath.Dir(p))  // var/log/nginx
	fmt.Println("Base:", filepath.Base(p)) // access.log
	fmt.Println("Ext: ", filepath.Ext(p))  // .log

	// Check if path is absolute
	fmt.Println("IsAbs:", filepath.IsAbs(p)) // false

	// Clean removes redundant dots and slashes
	messy := "a/b/../c/./d/"
	fmt.Println("Cleaned:", filepath.Clean(messy)) // a/c/d

	// Relative path calculation
	rel, _ := filepath.Rel("var/log", p)
	fmt.Println("Rel to var/log:", rel) // nginx/access.log
}
```

---

## 5. Directories and Recursive Traversal

```go
package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

func main() {
	baseDir, err := os.MkdirTemp("", "k8s-manifests-*")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(baseDir) // recursive cleanup

	// Create nested directories
	subDir := filepath.Join(baseDir, "deploy", "overlays")
	if err := os.MkdirAll(subDir, 0755); err != nil {
		panic(err)
	}

	// Create dummy files
	_ = os.WriteFile(filepath.Join(baseDir, "kustomization.yaml"), []byte("resources: []"), 0644)
	_ = os.WriteFile(filepath.Join(subDir, "prod.yaml"), []byte("env: prod"), 0644)

	// Read immediate directory entries (fast, non-recursive)
	entries, _ := os.ReadDir(baseDir)
	fmt.Println("Top-level directory entries:")
	for _, entry := range entries {
		fmt.Printf(" - %s (isDir: %t)\n", entry.Name(), entry.IsDir())
	}

	// Recursive traversal with WalkDir (efficient, passes DirEntry)
	fmt.Println("\nRecursive WalkDir:")
	err = filepath.WalkDir(baseDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(baseDir, path)
		fmt.Printf("Walked: %s (dir: %t)\n", rel, d.IsDir())
		return nil
	})
	if err != nil {
		panic(err)
	}
}
```

---

## 6. Temporary Files and Directories

Temporary resources are vital for testing, caching, and building atomic file replacements.

```go
package main

import (
	"fmt"
	"os"
)

func main() {
	// os.CreateTemp accepts directory ("" uses system default /tmp) and a pattern
	tmpFile, err := os.CreateTemp("", "worker-job-*.tmp")
	if err != nil {
		panic(err)
	}
	// Always schedule cleanup
	defer os.Remove(tmpFile.Name())
	defer tmpFile.Close()

	fmt.Println("Created temp file:", tmpFile.Name())

	_, _ = tmpFile.WriteString("intermediate calculation")

	// Temporary directory
	tmpDir, err := os.MkdirTemp("", "worker-bundle-*")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(tmpDir)

	fmt.Println("Created temp directory:", tmpDir)
}
```

---

## 7. The `embed` Directive (`//go:embed`)

Go 1.16 introduced the `embed` directive, allowing static assets (HTML, SQL schemas, configuration files, images) to be baked directly into the compiled executable binary at build time.

```go
package main

import (
	"embed"
	"fmt"
)

// Single file embedded as string or []byte
//go:embed sample_config.txt
var embeddedConfig string

// Multiple files or folder trees embedded as embed.FS
//go:embed static/*
var staticFS embed.FS

func main() {
	// 1. Reading single embedded string
	fmt.Println("Embedded single file content:", embeddedConfig)

	// 2. Reading from embedded filesystem (implements io/fs.FS)
	files, err := staticFS.ReadDir("static")
	if err == nil {
		for _, file := range files {
			fmt.Printf("Embedded file: %s (size: %d)\n", file.Name(), file.Type())
		}
	}

	// Read file contents directly from embed.FS
	data, err := staticFS.ReadFile("static/index.html")
	if err == nil {
		fmt.Printf("index.html body: %s\n", string(data))
	}
}
```

> [!TIP]
> `embed.FS` is read-only and thread-safe. You can pass it directly to `http.FileServer(http.FS(staticFS))` to serve frontend single-page apps (SPAs) directly from a zero-dependency Go single binary!

---

## Related Topics

- [[Architecture/languages/golang/12-strings-templates-and-regex|Strings, Templates, and Regex]] — Text rendering and templating.
- [[Architecture/languages/golang/18-time-numbers-urls-and-crypto|Time, Numbers, URLs, and Crypto]] — Hashes, Base64, and string parsing.
- [[Architecture/languages/golang/20-cli-env-and-logging|CLI, Environment, and Logging]] — Building full-featured command-line programs.
