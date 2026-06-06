---
title: Signals
description: Linux signals — SIGTERM, SIGKILL, SIGCHLD, SIGSEGV, signal handling, signal propagation, process lifecycle
tags:
  - linux
  - processes
---

# Signals

Signals are the Linux kernel's mechanism for **asynchronous notification** of events to processes. They're the way the system says "something happened, handle it." Every process that dies gets a signal — the difference between graceful shutdown and violent termination is which signal was used.

## Signal Basics

A signal is a **software interrupt** delivered to a process. The kernel delivers it by modifying the process's execution context (registers, program counter). When a signal arrives, the process either:
1. Runs the **default handler** (kernel-provided)
2. Runs a **custom handler** (user-provided `signal()` or `sigaction()`)
3. **Ignores** it

## The Big Three: SIGTERM, SIGKILL, SIGCHLD

### SIGTERM (15) — Graceful Termination

```bash
kill 1234          # defaults to SIGTERM
kill -TERM 1234
kill -15 1234
```

SIGTERM says "please stop when you're ready." The process:
1. Receives SIGTERM
2. Has a chance to clean up (close DB connections, flush buffers, save state)
3. Exits with code 0 (or whatever `exit()` returns)

**The process must not ignore SIGTERM** (default action is terminate, but it can be caught/ignored).

This is what `systemctl stop nginx` sends. And what Kubernetes sends first during pod termination.

### SIGKILL (9) — Forced Termination

```bash
kill -9 1234
kill -KILL 1234
```

SIGKILL cannot be caught, blocked, or ignored. The kernel immediately terminates the process — no cleanup runs, no handlers execute. SIGKILL is the "拔出电源" of signals.

Use when SIGTERM doesn't work (process is stuck, zombie, or ignoring SIGTERM).

### SIGCHLD (20/17) — Child Death Notification

```bash
# SIGCLD (System V) = SIGCHLD (BSD) = 20 (some systems)
```

When a child process exits, the kernel sends SIGCHLD to its parent. The parent **must** call `wait()` or `waitpid()` to reap the child's exit status — otherwise the child becomes a zombie (Z state).

```bash
# Parent process reading /proc to find zombies:
ps aux | grep Z
# Z    defunct

# Parent's responsibility:
wait();    # blocks until one child exits
waitpid(-1, &status, 0);  # wait for any child
```

## Common Signals and Their Default Actions

| Signal    | Num | Default Action | Purpose                              |
|-----------|-----|---------------|--------------------------------------|
| SIGHUP    | 1   | Terminate     | Terminal hangup (modem/dialup era)   |
| SIGINT    | 2   | Terminate     | Ctrl+C interrupt                     |
| SIGQUIT   | 3   | Core dump     | Ctrl+\ (quit and dump core)         |
| SIGILL    | 4   | Core dump     | Illegal instruction                  |
| SIGABRT   | 6   | Core dump     | `abort()` called                     |
| SIGFPE    | 8   | Core dump     | Floating point exception             |
| SIGKILL   | 9   | Terminate     | **Uncatchable** — forced kill        |
| SIGUSR1   | 10  | Terminate     | User-defined (custom use)            |
| SIGSEGV   | 11  | Core dump     | Segmentation fault (bad memory access)|
| SIGUSR2   | 12  | Terminate     | User-defined (custom use)           |
| SIGPIPE   | 13  | Terminate     | Write to pipe with no readers       |
| SIGALRM   | 14  | Terminate     | `alarm()` timer expired              |
| SIGTERM   | 15  | Terminate     | Polite termination request           |
| SIGSTKFLT | 16  | Terminate     | Stack fault (obsolete)               |
| SIGCHLD   | 17  | Ignore        | Child stopped/exited                 |
| SIGCONT   | 18  | Continue      | Continue if stopped                 |
| SIGSTOP   | 19  | Stop          | **Uncatchable** — pause process      |
| SIGTSTP   | 20  | Stop          | Ctrl+Z suspend                       |
| SIGTTIN   | 21  | Stop          | Background process reads tty         |
| SIGTTOU   | 22  | Stop          | Background process writes tty        |

## Signal Handling in Shell Scripts

```bash
# Trap: catch a signal and run a handler
trap 'cleanup; exit' SIGTERM SIGINT

cleanup() {
    echo "Caught signal, shutting down gracefully..."
    rm -f /tmp/lock
    # flush buffers, close DB, etc.
}

# Ignore a signal temporarily
trap '' SIGTERM
# ... critical section ...
trap SIGTERM  # restore default handling

# See all traps set
trap -p
```

## Process States and Signals

```
Running (R) ────────────────────────────────────────────► Running
                ↑                                          ↓
              SIGCONT                                  SIGSTOP/SIGTSTP
                ↑                                          ↓
Stopped (T) ◄─────────────────────────────────────────── Stopped
                ↓
              exit() or kill() → Zombie (Z) → parent wait() → Reaped
```

A stopped process (SIGSTOP/SIGTSTP) can be resumed with SIGCONT.

## SIGPIPE: The Silent Killer

When you write to a pipe and the reader closes their end:

```bash
# Without ignoring SIGPIPE:
python3 -c "import sys; [print(i) for i in range(100000)]" | head -1
# Gets killed by SIGPIPE when head closes the pipe after 1 line

# With SIGPIPE ignored:
trap '' PIPE
python3 -c "import sys; [print(i) for i in range(100000)]" | head -1
# Completes normally (write fails with EPIPE instead of killing process)
```

## Zombies and SIGCHLD

A zombie process has exited but hasn't been reaped:

```bash
# Create a zombie:
# 1. Fork a child
# 2. Child exits immediately
# 3. Parent does NOT call wait()
# 4. Child becomes zombie until parent exits or calls wait()

ps aux | grep Z
# darshan 12345  0.0  0.0      0     0 Z   ?  12:00   0:00 [python3] <defunct>
```

Zombies are reaped when the parent dies or calls `wait()`. To kill a zombie, you must kill its parent.

## Kubernetes Pod Termination = SIGTERM + Grace Period

```
┌──────────────────────────────────────────────────────────┐
│ Pod running: nginx PID 1                                 │
│                                                          │
│ K8s sends SIGTERM to PID 1                              │
│   nginx: stop accepting new connections                  │
│   nginx: finish existing connections (30s grace)          │
│   nginx: close logs, flush buffers                       │
│   nginx: exit(0)                                         │
│                                                          │
│ If not gone after grace period:                          │
│   K8s sends SIGKILL                                      │
│   Process dies immediately                               │
└──────────────────────────────────────────────────────────┘
```

The `terminationGracePeriodSeconds` in K8s controls how long to wait between SIGTERM and SIGKILL. Default: 30 seconds.

## Checking Pending and Blocked Signals

```bash
# See pending signals for a process
cat /proc/$$/status | grep -i sig
# SigPnd: 0000000000000000   (pending signals)
# SigBlk: 0000000000000000   (blocked signals)
# SigIgn: 0000000000001000   (ignored: SIGPIPE=13=0x1000)
# SigCgt: 0000000000000000   (caught signals)

# Send a signal to all processes in a process group
kill -TERM -$(pgrep -f myapp)   # negative PID = process group

# Send to all processes with a specific signal
killall -TERM nginx
```