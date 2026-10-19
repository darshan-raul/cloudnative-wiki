---
title: "OS Processes, Exec, Signals, and Exit in Go"
tags:
  - architecture/languages/golang
  - golang/os
date: 2026-04-19
description: "Master subprocess execution, process replacement with syscall.Exec, OS signal trapping with signal.Notify and signal.NotifyContext, and exit codes in Go."
aliases:
  - Architecture/languages/golang/os-processes-and-exec
---

# OS Processes, Exec, Signals, and Exit in Go

Systems software and container workloads constantly interface with the host operating system: launching child processes, piping data between subprocesses, reacting to orchestration termination signals (like Kubernetes `SIGTERM`), and cleanly terminating.

---

## 1. Spawning Processes (`os/exec`)

The `os/exec` package runs external commands. It inspects `PATH`, sets up stdin/stdout/stderr pipes, and captures exit codes.

### Basic Command Execution and Output

```go
package main

import (
	"context"
	"fmt"
	"os/exec"
	"time"
)

func main() {
	// 1. Simple command execution capturing stdout
	cmd := exec.Command("echo", "hello", "from", "os/exec")
	out, err := cmd.Output()
	if err != nil {
		panic(err)
	}
	fmt.Printf("Output: %s", string(out))

	// 2. Running command with timeout via context
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	// If the command does not complete within 2 seconds, context cancels and kills the process
	pingCmd := exec.CommandContext(ctx, "sleep", "1")
	if err := pingCmd.Run(); err != nil {
		fmt.Printf("Command failed or timed out: %v\n", err)
	} else {
		fmt.Println("Sleep completed within timeout")
	}
}
```

### Piping Data into and out of Subprocesses

```go
package main

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
)

func main() {
	// Grep command reading from an in-memory buffer
	cmd := exec.Command("grep", "cloud")

	cmd.Stdin = strings.NewReader("microservice architecture\ncloud-native platform\nmonolith app\n")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		panic(err)
	}

	fmt.Println("Filtered output:")
	fmt.Print(stdout.String())
}
```

---

## 2. Replacing the Current Process (`syscall.Exec`)

In Unix-like systems, sometimes you do not want a child process; you want the current Go program to **replace itself** with another executable image (retaining PID). Go provides `syscall.Exec` for this purpose.

```go
package main

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"
)

func main() {
	// Find binary path
	binary, err := exec.LookPath("ls")
	if err != nil {
		panic(err)
	}

	// Arguments: argv[0] is typically program name
	args := []string{"ls", "-la", "/tmp"}

	// Environment variables to forward
	env := os.Environ()

	fmt.Println("Replacing current Go process with 'ls -la /tmp'...")

	// syscall.Exec NEVER returns on success.
	// The current process memory is completely overwritten.
	execErr := syscall.Exec(binary, args, env)
	if execErr != nil {
		// Only reached if exec fails (e.g. file not found or permission denied)
		panic(execErr)
	}
}
```

---

## 3. Signal Handling (`os/signal`)

Kubernetes and container runtimes send `SIGTERM` when shutting down pods, followed by `SIGKILL` after a grace period. Go programs must trap `SIGTERM` and `SIGINT` (Ctrl+C) to finish ongoing requests before quitting.

### Idiomatic Signal Handling with `signal.NotifyContext`

```go
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	// signal.NotifyContext returns a context that is marked Done when any of the specified signals arrive
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	fmt.Println("Worker running. Press Ctrl+C or send SIGTERM to stop...")

	select {
	case <-ctx.Done():
		fmt.Println("\nShutdown signal received! Cleaning up resources...")
		// Perform graceful drain
		time.Sleep(500 * time.Millisecond)
		fmt.Println("Drained all connections cleanly.")
	}
}
```

---

## 4. Program Exit (`os.Exit`)

`os.Exit` terminates the program immediately with the specified integer status code (0 for success, non-zero for error).

> [!WARNING]
> **Defers do NOT run on `os.Exit`!**  
> When `os.Exit()` is called, deferred functions are bypassed completely. Always allow `main()` to return naturally when possible, or perform cleanup before invoking `os.Exit`.

```go
package main

import (
	"fmt"
	"os"
)

func main() {
	// This deferred function will NEVER execute due to os.Exit below!
	defer fmt.Println("This defer will NOT be printed!")

	fmt.Println("Starting validation check...")

	isValid := false
	if !isValid {
		fmt.Println("Fatal validation error: exiting with code 2")
		os.Exit(2)
	}

	fmt.Println("Validation passed!")
}
```

---

## Related Topics

- [[Architecture/languages/golang/20-cli-env-and-logging|CLI, Environment, and Logging]] — Arguments, flags, and slog.
- [[Architecture/languages/golang/23-http-and-graceful-shutdown|HTTP and Graceful Shutdown]] — Graceful server drain with contexts and signals.
- [[Architecture/languages/golang/19-files-directories-and-embed|Files, Directories, and Embed]] — File operations and temp paths.
