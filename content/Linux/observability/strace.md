---
title: strace
description: Linux strace — syscall tracing, debugging, -f, -e, -p, interpreting output
tags:
  - linux
  - observability
  - debugging
---

# strace

`strace` traces system calls (syscalls) and signals for a running process. It's the primary tool for debugging what a program is actually doing at the OS level — what files it opens, what network connections it makes, what it reads/writes, and where it hangs.

## How It Works

strace uses `ptrace()` to attach to a process and intercept every `syscall` entry and exit:

```
Process:    read(3, "hello\n", 100)
                 ↑
strace:    ← intercepts, logs it, lets it continue
```

## Basic Usage

```bash
# Trace a new command
strace ls /etc/passwd

# Trace a running process by PID
strace -p 1234

# Trace with timestamps
strace -t ls /etc/passwd
strace -tt ls /etc/passwd           # microsecond timestamps

# Show relative timestamps (time since start)
strace -r ls /etc/passwd

# Show syscall results (errors in red on terminals)
strace -e trace=read,write,open ls /etc/passwd
```

## Output Format

```
openat(AT_FDCWD, "/etc/passwd", O_RDONLY|O_CLOEXEC) = 3
read(3, "root:x:0:0:root:/root:/bin/bash\n"..., 1024) = 1024
close(3)                                = 0
```

Format: `syscall(args) = result`

- `= 3` means the syscall succeeded, returning fd 3
- `= -1 ENOENT (No such file)` means it failed with error ENOENT
- `-1 EACCES (Permission denied)` = access error

## Filtering by Syscall

```bash
# Only show specific syscalls
strace -e trace=open,openat,read,write ls /etc

# Trace file operations
strace -e trace=file ls /etc

# Trace network syscalls
strace -e trace=network, socket,connect,accept,send,recv ss -tlnp

# Trace memory mapping
strace -e trace=mmap,mprotect,madvise ls /etc

# Trace signals
strace -e trace=signal -e signal=SIGCHLD ps

# Trace process management
strace -e trace=process -e signal= SIGCHLD ls /etc

# Trace everything EXCEPT specific syscalls (noise reduction)
strace -e trace=!desc,signal ls /etc
```

## Following Forked Processes

```bash
# -f: follow forks (trace child processes too)
strace -f nginx

# -ff: separate files per process (PID in filename)
strace -ff -o /tmp/strace-out nginx

# Useful when debugging multi-process servers:
grep connect /tmp/strace-out.* | grep 10.0.0.1
```

## Showing Return Values and Errors

```bash
# -e trace=open -v: verbose (show flags, mode bits)
strace -e trace=openat -v ls /etc

# -x: show non-ASCII strings as hex
strace -x ls /etc

# -xx: show all pointer arguments in hex
strace -xx ls /etc
```

## Timing

```bash
# -c: count syscalls and time spent
strace -c ls /etc

# syscall         seconds   usecs/call     calls    errors syscall
# ----------- ----------- ----------- --------- --------- --------
# write              0.000        0.6        11           write
# mmap              0.000        1.2         7           mmap
# openat            0.000        1.8         5           openat
# fstat             0.000        0.8         5           fstat
# ...

# -C: normal output + count
strace -C ls /etc

# -T: show time spent in each syscall
strace -T ls /etc
# openat(..., "/etc/passwd", ...) = 3 <0.000182>
#                                              ^ time spent in syscall
```

## Common Debugging Use Cases

### Find why a command fails

```bash
strace ls /nonexistent 2>&1 | tail -5
# openat(AT_FDCWD, "/nonexistent", O_RDONLY|O_NONBLOCK|O_CLOEXEC) = -1 ENOENT (No such file or directory)
# Great, now you know the file doesn't exist
```

### Find what a program is trying to read

```bash
strace -e trace=open,openat,read -e abbrev=none cat /dev/urandom 2>&1 | grep -i "\.conf"
# openat(AT_FDCWD, "/etc/resolv.conf", ...) = 3
```

### Find where a program hangs

```bash
# Attach and wait for it to hang
strace -p 1234

# Show only syscalls (no lines):
strace -p 1234 -f

# With timestamps:
strace -tt -p 1234
# 12:00:01.234567 read(3, "...", 1024) = -1 ETIMEDOUT (Connection timed out)
# Now you know it's blocking on a read() call
```

### Find network connections

```bash
strace -e trace=connect,sendto,recvfrom -f -e network nginx 2>&1 | grep 10.0.0
```

## Output to File

```bash
strace -o /tmp/strace.log ls /etc

# Very large traces:
strace -ff -o /tmp/traceout nginx   # creates nginx.pid files
strace -ff -tt -T -o /tmp/traceout nginx
```

## /proc filesystem and strace

When you `strace -p PID`, the kernel uses `ptrace(PTRACE_SEIZE, PID)` to attach without stopping:

```
PTRACE_SEIZE: lightweight attach (doesn't pause the process)
PTRACE_SYSCALL: stop on next syscall entry/exit
```

The `/proc/sys/kernel/yama/ptrace_scope` setting can prevent non-root processes from using `ptrace`:

```
0 = classic ptrace permissions (any process can ptrace if it has same UID)
1 = restricted (only parent processes and processes with CAP_SYS_PTRACE)
2 = admin-only (only root or processes with CAP_SYS_PTRACE)
3 = no attach (ptrace disabled)
```

## Limitations

- **Overhead**: strace is slow (2-10x for simple commands). Don't use in production.
- **Not for malware analysis**: malware can detect and evade strace by blocking ptrace.
- **Not a profiler**: use `perf` for CPU profiling, `bpftrace` for deeper kernel tracing.

## Alternatives

| Tool      | What it does                          |
|-----------|---------------------------------------|
| `ltrace`  | Library calls (not syscalls)           |
| `perf`    | CPU profiling, hardware counters        |
| `bpftrace`| Dynamic kernel/userspace tracing        |
| `sysdig`  | Container-aware strace-like tool        |
| `wireshark` | Network protocol analysis             |
| `tcpdump` | Network packet capture (packet level)  |