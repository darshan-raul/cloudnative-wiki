---
title: Monitoring
description: Linux monitoring — top, htop, vmstat, iostat, sar, mpstat, pidstat, dstat, ioping
tags:
  - linux
  - observability
---

# Monitoring

Linux has a rich set of tools for observing system resource usage — CPU, memory, disk I/O, network, and per-process stats. These tools read from `/proc/` (primarily) and `/sys/`.

## top — Process CPU Monitor

```bash
top                    # default
top -c                 # show full command lines
top -p 1234           # monitor specific PID
top -u darshan        # only this user
top -b -n 5          # batch mode (for logging), 5 iterations
```

### top Fields (default order)

```
PID   USER  PR  NI  VIRT  RES  SHR  S  %CPU %MEM   TIME+  COMMAND
1234  nginx  20   0  123M  45M  12M  S   2.0  0.5   0:23.41  nginx: worker
```

### Interactive Commands in top

| Key   | Action                               |
|-------|--------------------------------------|
| `k`   | Kill process (enter PID, signal)    |
| `r`   | Renice (change priority)              |
| `1`   | Toggle per-CPU view                 |
| `c`   | Show full command line               |
| `M`   | Sort by %MEM                        |
| `P`   | Sort by %CPU (default)              |
| `T`   | Sort by TIME+                       |
| `t`   | Toggle CPU bar                      |
| `m`   | Toggle MEM bar                      |
| `f`   | Add/remove columns                 |
| `W`   | Save top config to ~/.toprc          |
| `q`   | Quit                                |

## htop — Better top

```bash
htop
htop -p 1234,5678    # monitor specific PIDs
htop -u darshan       # filter by user
```

htop has color-coded bars, mouse support, and tree view (`t`).

## vmstat — Virtual Memory Stats

```bash
vmstat                      # one-time snapshot
vmstat 1                   # every 1 second
vmstat 1 10                 # every 1 second, 10 times
vmstat -s                  # detailed memory statistics
vmstat -d                  # disk I/O statistics
```

### Output Explained

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  0      0 2048000 123456 789012    0    0     0     0    10   50  5  2 93  0  0
```

- `r`: runnable processes (running + waiting)
- `b`: blocked processes (uninterruptible sleep, usually I/O)
- `swpd/si/so`: swap used, swap-in, swap-out (KB/s)
- `bi/bo`: blocks in/out (disk I/O, blocks/s)
- `us/sy/id/wa/st`: CPU time breakdown (user/system/idle/wait/steal)

**High `wa` (wait)**: I/O bottleneck.
**High `sy` (system)**: kernel overhead, syscalls.
**High `st` (steal)**: in VMs, other VMs consuming CPU.

## iostat — Disk I/O Stats

```bash
iostat -xz                   # per-device breakdown, extended
iostat 1 5                   # every 1s, 5 times
iostat -d                    # just disk I/O
iostat -p sda              # per-partition
iostat -h                  # human-readable numbers
```

### Output

```
Device  r/s  w/s  rkB/s  wkB/s  rrqm/s  wrqm/s  %rrqm %wrqm  r_await w_await aqu-sz  rareq-sz wareq-sz
sda     10.5   3.2   120.5    45.2     0.1     0.2    0.9    5.9    0.5    2.1    0.1     11.5     14.1
```

- `r/s, w/s`: reads/writes per second
- `rkB/s, wkB/s`: KB read/written per second
- `r_await, w_await`: average wait time (ms)
- `aqu-sz`: average queue length (should be < 2 for HDDs, higher for SSDs)
- `%util`: device utilization (100% = saturated)

## mpstat — Per-CPU Stats

```bash
mpstat -P ALL 1 5          # all CPUs, 1s interval, 5 times
mpstat 1                    # average across all CPUs
```

```
Linux 5.15.0 (host)    06/06/2025  _x86_64_  (4 CPU)
12:00:00 AM  CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
12:00:01 AM  all    5.00    0.00    2.00    0.50    0.00    0.25    0.00    0.00    0.00   92.25
```

Useful for seeing if one core is pinned vs overall load.

## pidstat — Per-Process Stats

```bash
pidstat 1 5                 # every 1s, 5 times (all processes)
pidstat -p 1234 1 5        # specific process
pidstat -u -p 1234          # CPU stats for PID
pidstat -r -p 1234          # memory stats
pidstat -d -p 1234          # disk I/O
pidstat -w                  # context switches
pidstat -t                  # also show threads
```

## sar — System Activity Reporter

`sar` reads from `/var/log/sa/` (created by the `sysstat` package):

```bash
# Install sysstat to enable sar:
#   apt install sysstat  /  pacman -S sysstat

# Enable data collection:
systemctl enable sysstat
systemctl start sysstat

# CPU
sar -u 1 3                  # every 1s, 3 times
sar -u -s 09:00:00 -e 17:00:00  # during work hours

# Memory
sar -r 1 3

# I/O
sar -b 1 3                  # disk I/O
sar -d 1 3                  # per-device

# Network
sar -n DEV 1 3             # network interfaces
sar -n TCP 1 3             # TCP stats (connect, accept, retransmit)
sar -n UDP 1 3             # UDP stats

# Swap
sar -S 1 3
```

Historical data is in `/var/log/sa/saDD` (binary). Use `sadf` to export.

## free — Memory

```bash
free -h                     # human-readable
free -m                     # megabytes
free -w                     # wide (separate columns)
```

```
              total        used        free      shared  buff/cache   available
Mem:           31Gi       8.2Gi        12Gi       200Mi        11Gi        22Gi
Swap:         8.0Gi          0B       8.0Gi
```

**available** is what a process can actually use (includes reclaimable cache). **free** is truly unused RAM. **buff/cache** is file metadata and page cache (reclaimable).

## df and du — Disk Usage

```bash
df -h                      # human-readable, all filesystems
df -h -x tmpfs -x devtmpfs  # exclude pseudo filesystems
df -i                      # inode usage (important on /var, /tmp)

du -sh *                   # human, total per directory entry
du -sh /var/log            # specific directory
du -ah --max-depth=1 /home # all files, one level deep
du -sh /*                  # top-level (all filesystems)
```

## Special /proc Files

```bash
# CPU info
cat /proc/cpuinfo | grep -E "model name|cpu cores|siblings" | sort | uniq

# Memory
cat /proc/meminfo          # detailed memory (MemTotal, MemAvailable, etc.)
cat /proc/vmstat           # VM statistics

# Load average (same as uptime)
cat /proc/loadavg
# 0.52 0.58 0.59 1/1234 5678
#  ^1min  ^5min  ^15min  ^running/total  ^last PID

# Uptime
cat /proc/uptime
# 123456.78 123400.00
#  ^total uptime   ^idle time

# Interrupts
cat /proc/interrupts       # hardware IRQs per CPU
cat /proc/softirqs         # softirqs per CPU (network, timer, etc.)
```

## dstat — All-in-One

```bash
dstat -cdngy              # cpu, disk, net, page, system, y作息
dstat --cpu --mem --io    # specific
dstat 1 10                # every 1s, 10 times
dstat --list              # all available plugins
```

## ioping — Disk Latency

```bash
# Measure disk latency
ioping /dev/sda1          # interactive
ioping -c 10 /dev/sda1   # 10 requests
ioping -i 0.1 -c 100 .   # 100 requests at 0.1s interval in current dir
```

## Quick Troubleshooting Checklist

```bash
# CPU bottleneck?
top / htop               # which process?
vmstat 1                  # high us/sy?
mpstat -P ALL 1           # per-CPU balance?

# Memory pressure?
free -h
vmstat 1                  # high si/so (swap)?
cat /proc/meminfo | grep -E "Available|Cached|Active"
dmesg | grep -i oom       # OOM killer invocations?

# Disk I/O bottleneck?
iostat -xz 1              # high util%? high aqu-sz?
iotop -a                  # which process doing I/O? (needs root)

# Network?
sar -n DEV 1              # packets/second per interface
ss -s                     # socket summary
netstat -i                # interface errors
```