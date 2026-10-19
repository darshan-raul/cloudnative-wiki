---
title: "HTTP Servers, Middleware & Graceful Shutdown in Go"
description: "Building production HTTP services in Go — Go 1.22 routing patterns, middleware chaining, timeouts, and zero-downtime graceful shutdown with os/signal."
tags:
  - architecture
  - languages
  - golang
  - http
  - production
  - server
date: 2026-10-19
aliases:
  - Architecture/languages/golang/http-and-graceful-shutdown
---

# HTTP Servers, Middleware & Graceful Shutdown in Go 🚀

Go's built-in **`net/http`** package is battle-tested, high-performance, and powers production services at companies like Cloudflare, Google, and Netflix.

Building a production-ready HTTP microservice requires three core components: **clean routing**, **middleware chaining**, and **graceful shutdown**.

---

## 1. Modern Go 1.22+ Routing (`http.ServeMux`)

Starting in Go 1.22, the standard library's `http.ServeMux` natively supports **HTTP method matching** and **path parameters**:

```go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	mux := http.NewServeMux()

	// Method + Path matching natively supported!
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Path parameter matching with {id}
	mux.HandleFunc("GET /users/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id") // Extract path parameter directly!
		fmt.Fprintf(w, "User details for ID: %s\n", id)
	})

	mux.HandleFunc("POST /users", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
		w.Write([]byte("User created"))
	})

	http.ListenAndServe(":8080", mux)
}
```

---

## 2. Writing Reusable HTTP Middleware

In Go, middleware is simply a function that takes an `http.Handler` and returns a wrapped `http.Handler`:

```go
package main

import (
	"log"
	"net/http"
	"time"
)

// LoggingMiddleware logs request duration and path
func LoggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Call the next handler in the chain
		next.ServeHTTP(w, r)

		log.Printf("%s %s completed in %v", r.Method, r.URL.Path, time.Since(start))
	})
}
```

---

## 3. Mandatory Production Timeouts

Never use raw `http.ListenAndServe(":8080", nil)` without configuring server timeouts! A hanging client connection can exhaust file descriptors and crash the server:

```go
srv := &http.Server{
    Addr:         ":8080",
    Handler:      mux,
    ReadTimeout:  5 * time.Second,  // Max time to read request headers and body
    WriteTimeout: 10 * time.Second, // Max time to write response
    IdleTimeout:  120 * time.Second,// Keep-alive connection idle duration
}
```

---

## 4. Zero-Downtime Graceful Shutdown (`os/signal`)

In Kubernetes or cloud environments, when a Pod is terminated, the kernel sends a **`SIGTERM`** signal. The server must **stop accepting new requests**, finish servicing in-flight requests, close database connections, and exit cleanly before Kubernetes sends `SIGKILL`:

```go
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /orders", func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(2 * time.Second) // Simulate work
		w.Write([]byte("Order processed"))
	})

	srv := &http.Server{
		Addr:    ":8080",
		Handler: mux,
	}

	// 1. Listen for SIGINT (Ctrl+C) and SIGTERM (Kubernetes termination)
	stopCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// 2. Start server in a background goroutine
	go func() {
		log.Printf("Server listening on %s\n", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// 3. Block until termination signal is received
	<-stopCtx.Done()
	log.Println("Shutdown signal received, shutting down gracefully...")

	// 4. Give active in-flight requests up to 10 seconds to finish
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited cleanly.")
}
```

---

## 4. Production HTTP Client

Never use `http.DefaultClient` in production because it has no default timeout, which can cause connection leaks and goroutine starvation under slow networks. Always configure timeouts and drain the response body:

```go
package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"
)

func main() {
	// Configure production client with timeouts
	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	// Create request with context for cancellation
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://httpbin.org/get", nil)
	if err != nil {
		panic(err)
	}
	req.Header.Set("User-Agent", "Go-CloudNative-Client/1.0")
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		panic(err)
	}
	// CRITICAL: Always close and drain the body to enable HTTP/1.1 or HTTP/2 keep-alive connection reuse!
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		panic(err)
	}

	fmt.Printf("HTTP Status: %d\n", resp.StatusCode)
	fmt.Printf("Response Body Length: %d bytes\n", len(body))
}
```

---

## 5. Low-Level TCP Socket Server (`net.Listen`)

For raw network protocols, proxies, or high-throughput telemetry streams, Go provides socket listeners via `net`:

```go
package main

import (
	"bufio"
	"fmt"
	"net"
	"strings"
)

func handleConnection(conn net.Conn) {
	defer conn.Close()
	remoteAddr := conn.RemoteAddr().String()
	fmt.Printf("Accepted client connection from %s\n", remoteAddr)

	scanner := bufio.NewScanner(conn)
	for scanner.Scan() {
		text := scanner.Text()
		if strings.TrimSpace(text) == "QUIT" {
			_, _ = conn.Write([]byte("BYE\n"))
			break
		}
		// Echo in uppercase
		reply := strings.ToUpper(text) + "\n"
		_, _ = conn.Write([]byte(reply))
	}
	fmt.Printf("Closed client connection from %s\n", remoteAddr)
}

func main() {
	listener, err := net.Listen("tcp", "127.0.0.1:9099")
	if err != nil {
		panic(err)
	}
	defer listener.Close()

	fmt.Println("Echo TCP server listening on 127.0.0.1:9099...")

	for {
		conn, err := listener.Accept()
		if err != nil {
			fmt.Printf("Accept error: %v\n", err)
			break
		}
		// Handle each incoming TCP connection in its own lightweight goroutine
		go handleConnection(conn)
	}
}
```

---

## Across the Wiki

- [[Architecture/languages/golang/17-context|Go Context Package]] — Propagating cancellation to HTTP handlers.
- [[Architecture/solution-architecture-concepts/reliability/resilience|Resilience & Circuit Breakers]] — Building robust client and server systems.
- [[Kubernetes/concepts/L03-workloads/01-pods|Kubernetes Pods]] — How K8s manages `SIGTERM` and pre-stop lifecycle hooks.
