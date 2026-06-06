---
title: Process Management
description: Linux process management — ps, top, htop, kill, signals, pstree, daemon patterns, zombie processes
tags:
  - linux
  - processes
---

# Process Management

A process is a running instance of a program. Every process has a PID, a parent (PPID), its own address space, file descriptors, and state. Understanding process lifecycle — how processes are created, communicate, terminate, and are reaped — is foundational to Linux system administration.

## Viewing Processes

### ps

```bash
# All processes, BSD syntax (default view)
ps aux

# Full-format (Linux-specific)
ps -ef --forest        # show parent-child tree
ps -eo pid,ppid,user,stat,%cpu,%mem,cmd --sort=-%cpu

# Specific process
ps -ef | grep nginx

# Top consumers
ps aux --sort=-%mem | head

# Thread view
ps -eLf --sort=-%cpu | head
```

Output columns: `USER` (owner), `PID`, `%CPU`, `%MEM`, `VSZ` (virtual memory), `RSS` (resident set), `TTY` (terminal, `?` = daemon), `STAT` (state), `START`, `TIME` (CPU time), `COMMAND`.

### Process States (STAT column)

| State | Meaning                                   |
|-------|------------------------------------------|
| R     | Running or runnable                       |
| S     | Interruptible sleep (waiting for event)  |
| D     | Uninterruptible sleep (I/O)              |
| T     | Stopped (SIGSTOP/Ctrl+Z)                |
| Z     | Zombie (dead, not reaped)               |
| X     | Dead (shouldn't see this)               |
| I     | Idle kernel thread                       |

State modifiers: `s` (session leader), `+` (foreground process group), `l` (multi-threaded).

### top and htop

```bash
top -c                  # full command line
top -p $(pgrep -d, nginx)  # monitor specific PIDs
htop                   # interactive (requires install)
```

htop shows per-thread CPU, memory bars, tree view (`t`), and lets you send signals interactively (`k`).

## Process Lifecycle

```
Fork:     parent fork() → child (copy of parent's memory)
          ↓
Exec:     child execve() → new program loaded
          ↓
Run:      scheduled by kernel (TICK → context switch)
          ↓
Wait:     parent wait() → reap child's exit status
          ↓
Exit:     child exit() → becomes zombie (Z)
          ↓
Reaped:   parent reads status → kernel frees PCB
```

### Creating Processes

```c
// The fork-exec pattern
pid_t pid = fork();

if (pid == 0) {
    // Child
    execve("/bin/ls", argv, envp);  // replace with new program
    // If execve returns, it failed
    perror("execve");
    exit(1);
} else if (pid > 0) {
    // Parent
    int status;
    waitpid(pid, &status, 0);  // reap child
}
```

In shell: `ls` → the shell `fork()`s a child → child `execve("ls", ...)` → parent `waitpid()`s on it.

### Daemon Processes

A daemon is a background process, usually started at boot, that provides system services:

```c
// Creating a daemon (the standard pattern)
if (fork() != 0) exit(0);           // detach from parent
setsid();                            // new session, no controlling terminal
if (fork() != 0) exit(0);           // prevent acquiring a terminal again
chdir("/");                          // prevent blocking unmounts
umask(0);                            // predictable file mode
close(0); close(1); close(2);       // close stdio FDs
open("/dev/null", O_RDWR);          // stdin from null
dup2(0, 1); dup2(0, 2);            // stdout/stderr → null
// Now daemonize complete, run main loop
```

Key properties of a daemon:
- Parent is PID 1 (or init)
- No controlling terminal (`setsid()`)
- Not a session leader (second fork prevents this)
- File descriptors 0/1/2 redirected to `/dev/null`

## Sending Signals

```bash
kill -TERM 1234     # graceful termination (default)
kill -KILL 1234     # forced kill (cannot be caught)
kill -STOP 1234     # pause (SIGSTOP)
kill -CONT 1234     # resume (SIGCONT)
kill -HUP 1234      # reload config (many daemons re-read config on SIGHUP)
killall nginx       # kill all processes named nginx
pkill -f nginx      # kill by command pattern
```

**SIGTERM first, SIGKILL second.** Only use SIGKILL when SIGTERM doesn't work.

## Process Trees

```bash
pstree                  # show process tree
pstree -p 1           # show tree rooted at PID 1
pstree -a             # show arguments

# Manual tree
ps -ef --forest | head -50
```

```
systemd (PID 1)
└── dockerd (1234)
    └── containerd-shim (2345)
        └── runc (3456)
            └── nginx (4567, PID 1 inside container)
                ├── nginx (worker, PID 2 inside)
                └── nginx (worker, PID 3 inside)
```

## Zombie Processes

A zombie (`Z` state) has exited but hasn't been reaped:

```bash
ps aux | grep Z
# USER  PID  STAT COMMAND
# darshan 5678 Z   [defunct]

# Find the zombie and its parent:
ps -ef | grep 5678
# darshan 5678 5677 Z   defunct_process
# darshan 5677     S   parent_process
```

**You can't kill a zombie** (it's already dead). You must kill the parent. If the parent won't die, you must restart it.

Zombies that persist usually indicate a **parent that's ignoring SIGCHLD** or a bug where `wait()` isn't being called.

## Background Processes and Job Control

```bash
# Run in background
long_running_task &
# or
nohup command > /dev/null 2>&1 &
disown %1              # remove from shell's job table

# Bring to foreground
fg %1

# List jobs
jobs
# [1]+  Running    long_running_task &
# [2]-  Stopped    vim

# Resume stopped job in background
bg %2
```

## /proc and Processes

```bash
/proc/<pid>/          # process information
/proc/<pid>/cmdline  # command line (null-separated)
/proc/<pid>/environ  # environment variables
/proc/<pid>/fd/      # open file descriptors (symlinks)
/proc/<pid>/maps     # memory maps
/proc/<pid>/status   # human-readable process state
/proc/<pid>/stack    # kernel stack trace
/proc/<pid>/wchan    # kernel function process is sleeping in
/proc/self/          # symlink to current process's info
```

## Key Commands Quick Reference

```bash
ps -ef                        # all processes, full format
ps aux                        # all processes, BSD format
ps -ef --forest               # tree view
top / htop                    # interactive CPU/memory
pstree -a                     # process tree
pgrep nginx                   # find PIDs by name
pkill -f pattern              # kill by pattern
kill PID                      # SIGTERM
kill -9 PID                   # SIGKILL
killall nginx                 # kill all nginx
lsof -p PID                   # files opened by PID
lsof -i :80                   # process using port 80
fuser 80/tcp                  # process using port 80
strace -p PID                 # trace syscalls
watch -n 1 'ps -eo pid,stat,cmd --sort=-cpu | head'  # live top
```