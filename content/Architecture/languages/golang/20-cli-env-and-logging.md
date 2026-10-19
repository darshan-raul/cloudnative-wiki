---
title: "CLI Arguments, Environment Variables, and Structured Logging in Go"
tags:
  - architecture/languages/golang
  - golang/cli
date: 2026-04-19
description: "Master command-line parsing, flag sets, subcommands, environment variable configuration, and high-performance structured logging with log/slog in Go."
aliases:
  - Architecture/languages/golang/cli-env-and-logging
---

# CLI Arguments, Environment Variables, and Structured Logging in Go

Building cloud-native microservices, Kubernetes operators, and CLI tools requires robust handling of startup flags, runtime environment variables, and machine-readable structured logging.

---

## 1. Command-Line Arguments (`os.Args`)

The `os.Args` slice holds all raw command-line arguments provided to the binary.

```go
package main

import (
	"fmt"
	"os"
)

func main() {
	// os.Args[0] is always the program path/binary name
	programName := os.Args[0]
	fmt.Println("Program invoked as:", programName)

	// Arguments passed after the program name
	argsWithoutProg := os.Args[1:]
	fmt.Printf("Total arguments provided: %d\n", len(argsWithoutProg))

	for i, arg := range argsWithoutProg {
		fmt.Printf("  Arg %d: %s\n", i+1, arg)
	}
}
```

---

## 2. Command-Line Flags (`flag`)

The standard `flag` package parses options formatted like `-port=8080`, `--port 8080`, or `-debug`.

```go
package main

import (
	"flag"
	"fmt"
)

func main() {
	// 1. Defining flags that return pointers
	hostPtr := flag.String("host", "127.0.0.1", "Bind address for HTTP server")
	portPtr := flag.Int("port", 8080, "Port for incoming connections")
	debugPtr := flag.Bool("debug", false, "Enable verbose debug logging")

	// 2. Binding a flag to an existing variable
	var maxWorkers int
	flag.IntVar(&maxWorkers, "workers", 4, "Number of concurrent worker goroutines")

	// 3. Parse flags from os.Args[1:]
	flag.Parse()

	fmt.Println("Host:       ", *hostPtr)
	fmt.Println("Port:       ", *portPtr)
	fmt.Println("Debug:      ", *debugPtr)
	fmt.Println("Max Workers:", maxWorkers)

	// Trailing positional arguments after flags
	trailingArgs := flag.Args()
	fmt.Println("Trailing positional arguments:", trailingArgs)
}
```

---

## 3. Subcommands with `flag.NewFlagSet`

Tools like `kubectl` or `git` rely on subcommands (e.g., `git clone`, `git commit`). You can build subcommand CLIs using `flag.NewFlagSet`.

```go
package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("expected 'deploy' or 'status' subcommands")
		os.Exit(1)
	}

	// Subcommand 1: deploy
	deployCmd := flag.NewFlagSet("deploy", flag.ExitOnError)
	deployEnv := deployCmd.String("env", "staging", "target deployment environment")
	deployReplicas := deployCmd.Int("replicas", 3, "desired replica count")

	// Subcommand 2: status
	statusCmd := flag.NewFlagSet("status", flag.ExitOnError)
	statusService := statusCmd.String("service", "payment-api", "service name to inspect")

	switch os.Args[1] {
	case "deploy":
		_ = deployCmd.Parse(os.Args[2:])
		fmt.Printf("Deploying to %s with %d replicas\n", *deployEnv, *deployReplicas)
	case "status":
		_ = statusCmd.Parse(os.Args[2:])
		fmt.Printf("Fetching status for service: %s\n", *statusService)
	default:
		fmt.Println("Unknown subcommand:", os.Args[1])
		os.Exit(1)
	}
}
```

---

## 4. Environment Variables (`os`)

The Twelve-Factor App methodology mandates storing configuration in the environment.

```go
package main

import (
	"fmt"
	"os"
	"strings"
)

func main() {
	// Set an environment variable in the current process
	_ = os.Setenv("APP_REGION", "us-east-1")

	// Simple retrieval (returns empty string if unset)
	region := os.Getenv("APP_REGION")
	fmt.Println("APP_REGION:", region)

	// Distinguish between unset and explicitly set to empty
	val, exists := os.LookupEnv("OPTIONAL_FEATURE_FLAG")
	if !exists {
		fmt.Println("OPTIONAL_FEATURE_FLAG is not set")
	} else {
		fmt.Printf("OPTIONAL_FEATURE_FLAG is set to: %q\n", val)
	}

	// Listing all environment variables (KEY=VALUE)
	fmt.Println("First 3 environment entries:")
	for i, env := range os.Environ() {
		if i >= 3 {
			break
		}
		pair := strings.SplitN(env, "=", 2)
		fmt.Printf("  %s = %s\n", pair[0], pair[1])
	}
}
```

---

## 5. Structured Logging (`log/slog`)

Introduced in Go 1.21, `log/slog` provides fast, zero-allocation structured logging with JSON and text formatters, contextual attributes, and hierarchical log levels.

```go
package main

import (
	"log/slog"
	"os"
)

func main() {
	// 1. Default text handler
	slog.Info("Service startup complete", "port", 8080, "protocol", "http")

	// 2. Production JSON handler writes machine-parsable JSON for Datadog / Elasticsearch
	jsonHandler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelDebug, // minimum level to emit
	})
	logger := slog.New(jsonHandler)

	// Logging with strongly-typed attributes
	logger.Info("User authentication succeeded",
		slog.String("user_id", "usr_99812"),
		slog.Int("attempts", 1),
		slog.Bool("mfa_enabled", true),
	)

	// Error logging with structured context
	logger.Error("Database connection failed",
		slog.String("cluster", "primary-db"),
		slog.Int("retry_count", 3),
		slog.String("error", "connection reset by peer"),
	)

	// 3. Child Loggers with Pre-baked Context (slog.With)
	requestLogger := logger.With(
		slog.String("request_id", "req-abcdef123"),
		slog.String("remote_addr", "10.0.4.15"),
	)

	requestLogger.Debug("Processing incoming payload")
	requestLogger.Info("Request completed successfully", slog.Int("status_code", 200))
}
```

### JSON Log Output Format

```json
{"time":"2026-10-19T07:15:00Z","level":"INFO","msg":"User authentication succeeded","user_id":"usr_99812","attempts":1,"mfa_enabled":true}
{"time":"2026-10-19T07:15:00Z","level":"ERROR","msg":"Database connection failed","cluster":"primary-db","retry_count":3,"error":"connection reset by peer"}
{"time":"2026-10-19T07:15:00Z","level":"INFO","msg":"Request completed successfully","request_id":"req-abcdef123","remote_addr":"10.0.4.15","status_code":200}
```

---

## Related Topics

- [[Architecture/languages/golang/21-os-processes-and-exec|OS Processes, Signals, and Exit]] — Spawning subprocesses and handling OS termination signals.
- [[Architecture/languages/golang/19-files-directories-and-embed|Files, Directories, and Embed]] — Configuration file loading and embedded assets.
- [[Architecture/languages/golang/23-http-and-graceful-shutdown|HTTP and Graceful Shutdown]] — Integrating logging with web servers and signals.
