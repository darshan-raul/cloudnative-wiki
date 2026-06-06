---
title: sysctl
description: Linux sysctl — kernel parameter tuning, /proc/sys, /etc/sysctl.conf, networking, memory, filesystem
tags:
  - linux
  - security
---

# sysctl

`sysctl` reads and writes kernel parameters at runtime. These parameters live in `/proc/sys/` and control everything from network behavior to memory management to security settings. Changes made with `sysctl` are lost on reboot unless saved to `/etc/sysctl.conf` or `/etc/sysctl.d/`.

## Basic Usage

```bash
# Read a parameter
sysctl net.ipv4.ip_forward
# net.ipv4.ip_forward = 0

# Write a parameter (temporary — lost on reboot)
sysctl -w net.ipv4.ip_forward=1

# Load settings from config file
sysctl -p /etc/sysctl.conf
sysctl -p /etc/sysctl.d/99-network.conf

# Load all config files in /etc/sysctl.d/
sysctl --system

# Show all current settings
sysctl -a
```

## Network Tuning

### IP Forwarding (Router)

```bash
# Enable forwarding (required for NAT, routing, containers)
sysctl -w net.ipv4.ip_forward=1
# Permanent: /etc/sysctl.d/99-router.conf
# net.ipv4.ip_forward=1
```

### TCP Tuning

```bash
# TCP keepalive (detect dead connections faster)
sysctl -w net.ipv4.tcp_keepalive_time=600
sysctl -w net.ipv4.tcp_keepalive_intvl=60
sysctl -w net.ipv4.tcp_keepalive_probes=3

# TCP backlog (listen() queue)
sysctl -w net.core.somaxconn=1024
sysctl -w net.ipv4.tcp_max_syn_backlog=1024

# TCP memory
sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"
sysctl -w net.ipv4.tcp_wmem="4096 87380 16777216"

# TCP congestion control
sysctl -w net.ipv4.tcp_congestion_control=cubic
# Available: cubic, bbr, reno
```

### SYN Flood Protection

```bash
# Enable SYN cookies (prevents SYN flood DoS)
sysctl -w net.ipv4.tcp_syncookies=1
sysctl -w net.ipv4.tcp_syncookies=2 # strict mode
```

### ICMP (Ping)

```bash
# Ignore broadcast/ping
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1
sysctl -w net.ipv4.icmp_echo_ignore_all=1   # ignore all pings (hardens against ping floods)
```

### Reverse Path Filtering (Anti-spoofing)

```bash
# Strict RPF (check source IP against incoming interface routing)
sysctl -w net.ipv4.conf.default.rp_filter=1
sysctl -w net.ipv4.conf.all.rp_filter=1

# Values: 0=off, 1=strict, 2=loose
```

## Memory and VM Tuning

```bash
# Swappiness (aggressive paging to swap)
sysctl -w vm.swappiness=60
#0 = never swap (risky OOM), 100 = aggressive swap
# Default:60

# Writeback (how often pdflush writes dirty pages)
sysctl -w vm.dirty_ratio=15 # % of RAM before process must write
sysctl -w vm.dirty_background_ratio=5  # % before background flush starts

# Overcommit memory
sysctl -w vm.overcommit_memory=1 # 0=heuristic, 1=always allow, 2=never overcommit
sysctl -w vm.overcommit_ratio=50   # % of RAM that can be overcommitted

# Huge pages
sysctl -w vm.nr_hugepages=1024     # 1024 × 2MB =2GB huge pages

# Max shmem (shared memory)
sysctl -w kernel.shmmax=68719476736
sysctl -w kernel.shmall=4180288
```

## Filesystem Tuning

```bash
# Inotify (file watching limits)
sysctl -w fs.inotify.max_user_watches=524288   # more watches (for inotify-based tools)
sysctl -w fs.inotify.max_user_instances=1024

# File descriptors
sysctl -w fs.file-max=2097152
sysctl -w fs.nr_open=2097152

# Hard link limits
sysctl -w fs.inotify.max_queued_events=16384
```

## Security Hardening

```bash
# ASLR (Address Space Layout Randomization)
sysctl -w kernel.randomize_va_space=2 # 0=off, 1=stack only, 2=all (default=2)

# Kernel pointer printing (hide kernel pointers in logs)
sysctl -w kernel.kptr_restrict=1        # 0=everyone, 1=normal users, 2=root only

# Core dumps
sysctl -w kernel.core_pattern=core # naming pattern for core dumps
sysctl -w kernel.core_uses_pid=1         # include PID in core dump filename
sysctl -w fs.suid_dumpable=0            # 0=suid procs can't dump, 2=can dump as root

# Sysrq (Magic SysRq key)
sysctl -w kernel.sysrq=0               # 0=disabled, 1=full, >1=subset
```

## Process and PID Limits

```bash
# Max threads
sysctl -w kernel.threads-max=6291456

# Max PID
sysctl -w kernel.pid_max=4194304       # default: 32768 (grows dynamically)

# Max lockable memory (for mlock, mlockall)
sysctl -w vm.max_map_count=65530
```

## /etc/sysctl.conf Structure

```bash
# /etc/sysctl.conf — main config file
# Format: key = value

# Network
net.ipv4.ip_forward=1
net.ipv4.tcp_syncookies=1
net.core.somaxconn=1024

# Memory
vm.swappiness=10
vm.max_map_count=65530

# Security
kernel.randomize_va_space=2
kernel.kptr_restrict=1
```

## /etc/sysctl.d/ (Modular Config)

```bash
# Drop config files here — processed in order
ls /etc/sysctl.d/
# 00-debian.conf99-custom.conf

# Create custom tuning:
# /etc/sysctl.d/99-network.conf
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 87380 16777216
```

## Showing Non-Default Settings

```bash
# Show only non-default (customized) settings
sysctl -a -b /tmp/current_sysctl.bin # binary dump
# Compare with defaults from /usr/share/sysctl.d/
```

## Docker and sysctl

Docker sets sysctl values per-container:

```bash
# Set at container run time
docker run --sysctl net.ipv4.ip_forward=1 nginx
docker run --sysctl net.core.somaxconn=1024 nginx

# Kubernetes pod spec:
spec:
  securityContext:
    sysctls:
    - name: net.ipv4.ip_forward
      value: "1"
    - name: net.core.somaxconn
      value: "1024"
```

Note: Some sysctls are **namespaced** (can be set per container) and some are **non-namespaced** (host-wide). Namespaced sysctls: `net.ipv4.*`, `net.core.somaxconn`, `fs.mqueue.*`, etc. Non-namespaced: `kernel.*`, `vm.*`, `net.*` (except a few).