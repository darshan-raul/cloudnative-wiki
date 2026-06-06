---
title: Linux Observability
description: Linux observability — journalctl, log management, monitoring (top, vmstat, iostat, sar), strace, system performance analysis
tags:
  - linux
  - observability
---

# Linux Observability

When something breaks — a service won't start, CPU is at 100%, a container is running out of memory — these tools are how you find out what the system is actually doing.

## Logging

**[[journalctl|journalctl]]** — The interface to systemd's journal. Filtering by unit (`-u nginx`), boot ID (`-b`), priority (`-p err`), and time (`--since "1 hour ago"`). JSON output for scripting. Boot-time analysis with `--list-boots`. `journald.conf` settings: `Storage=`, `Compress=`, `SystemMaxUse=`, `ForwardToSyslog=`. Vacuuming old logs with `--vacuum-time` and `--vacuum-size`.

**[[log-management|Log Management]]** — The `/var/log/` directory structure: `syslog`/`messages` (all syslog events), `auth.log`/`secure` (authentication), `kern.log` (kernel), `daemon.log` (background services), `dmesg` (boot-time kernel ring buffer). Binary logs: `last`, `lastlog`, `faillog`, `btmp` — and why they're binary. `logrotate` configuration: daily/weekly/monthly rotation, compression, `notifempty`, `missingok`, the `postrotate` script for signaling services to reload their logs.

## Monitoring

**[[monitoring|Monitoring Tools]]** — Live and historical system metrics.

- `top` / `htop` — per-process CPU and memory, sortable, signal-sendable, reniceable
- `vmstat` — overall system view: run queue length, swap in/out, block I/O, CPU breakdown (us/sy/id/wa)
- `iostat` — per-disk I/O: reads/writes per second, kilobytes per second, await time, utilization %
- `sar` — historical metrics from `/var/log/sa/` (sysstat). `sar -q` (queue length), `sar -r` (memory), `sar -n DEV` (network), `sar -b` (I/O). Useful for explaining to a manager why the server was slow three days ago
- `pidstat` — per-process I/O and CPU stats
- `dstat` — combined vmstat/iostat/netstat with color output
- `ioping` — disk latency testing

## Tracing and Debugging

**[[strace|strace]]** — The syscall tracer. Attach to a running process (`-p PID`) or start a command under strace (`strace -f -e trace=network,file cmd`). Reading the output: every line is a syscall with its arguments and return value. `-o` to write to file, `-c` for a summary count of which syscalls were called. Using strace to debug why a command fails, what files it opens, what network connections it makes.