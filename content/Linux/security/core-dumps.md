---
title: Core Dumps
description: Linux core dumps — /proc/sys/kernel/core_pattern, ulimit, systemd-coredump, gdb analysis
tags:
  - linux
  - security
  - debugging
---

# Core Dumps

A core dump is a **snapshot of a process's memory** written when it crashes (or is killed with a signal). It's used for post-mortem debugging — load it into gdb to see exactly where the crash happened.

## Enabling Core Dumps

```bash
# Check current status
ulimit -c           # 0 = disabled
cat /proc/sys/kernel/core_pattern
# |/usr/share/apport/apport ...

# Enable for current session
ulimit -c unlimited

# Permanent: /etc/security/limits.conf
# *    soft    core    unlimited
# *    hard    core    unlimited
```

## core_pattern

The `core_pattern` in `/proc/sys/kernel/` controls where dumps go:

```bash
# Default Ubuntu (apport):
cat /proc/sys/kernel/core_pattern
# |/usr/share/apport/apport %p %s %c %d %P %E

# Core in working directory with PID:
echo "core.%p.%s.%t" > /proc/sys/kernel/core_pattern
# Result: core.12345.11.1717600000

# Absolute path (system-wide):
echo "/var/crash/core.%p.%s.%t" > /proc/sys/kernel/core_pattern

# Just "core" (in process's cwd):
echo "core" > /proc/sys/kernel/core_pattern

#sysctl permanent: /etc/sysctl.conf
# kernel.core_pattern = core.%p.%s.%t
```

The `|` prefix means **pipe** — the core is piped to a program (apport, systemd-coredump) instead of written to a file.

## systemd-coredump

Modern systems (systemd 237+) use `systemd-coredump` to capture cores:

```bash
# Check if active:
systemctl status systemd-coredump

# View cores:
coredumpctl list
coredumpctl info <PID>

# Retrieve and debug:
coredumpctl -o core dump <PID>
gdb /path/to/binary core

# Or directly:
coredumpctl gdb <PID>

# Configuration:
/etc/systemd/coredump.conf
# [Coredump]
# Storage=external    # save to /var/lib/systemd/coredump/
# Compress=yes
# ProcessSizeMax=2G
# ExternalSizeMax=2G
```

## Analyzing a Core Dump

```bash
# Load into gdb
gdb /usr/bin/nginx /var/crash/core.1234
(gdb) bt              # backtrace — show where it crashed
(gdb) bt full         # full backtrace with locals
(gdb) info threads    # show all threads
(gdb) frame 3         # switch to frame 3
(gdb) print variable  # print variable value

# Quick check with file(1)
file core.12345
# core.12345: ELF 64-bit LSB core, x86-64, ...

# With crash (for kernel cores):
crash vmlinux vmcore
```

## SUID Programs and Core Dumps

When a SUID program crashes, core dumps are **disabled by default** to prevent leaking privileges:

```bash
# /proc/sys/fs/suid_dumpable controls SUID core dumps:
# 0 = no core dumps (default)
# 1 = core dumps as file owner (not recommended)
# 2 = core dumps as the user that dumped (full debugging)
echo 2 > /proc/sys/fs/suid_dumpable
```

```bash
# sysctl:
# fs.suid_dumpable = 2
```

## Preventing Core Dumps in Production

```bash
# Disable completely:
echo 0 > /proc/sys/kernel/core_pattern
# or:
echo "|/bin/false" > /proc/sys/kernel/core_pattern

# In /etc/security/limits.conf:
*  hard  core  0

# In /etc/sysctl.conf:
kernel.core_pattern = |/bin/false

# Application-level (in code):
#include <sys/resource.h>
struct rlimit rl = {0, 0};
setrlimit(RLIMIT_CORE, &rl);
```

## systemd Service Core Dumps

```bash
# For a systemd service, add to the [Service] section:
[Service]
LimitCORE=0         # 0 = unlimited, or specific size like 1G
```

## Quick Reference

```bash
# 1. Check if cores are being generated:
ls -la /proc/sys/kernel/core_pattern
ulimit -c

# 2. Enable:
ulimit -c unlimited
echo "core.%p.%s.%t" > /proc/sys/kernel/core_pattern

# 3. Reproduce crash:
#   Your program segfaults, core appears

# 4. Find it:
find / -name "core.*" -type f 2>/dev/null
# or
coredumpctl list

# 5. Debug:
gdb -ex "bt" -ex "quit" /path/to/binary /path/to/core
```