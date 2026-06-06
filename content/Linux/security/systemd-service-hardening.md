---
title: systemd Service Hardening
description: Hardening systemd services — ProtectSystem, ReadOnlyPaths, NoNewPrivileges, PrivateTmp, SystemCallFilter, AmbientCapabilities, and CIS-style service security
tags:
  - linux
  - security
  - systemd
  - cis
---

# systemd Service Hardening

Hardening a systemd service means locking down what the service process can do — what files it can read/write, what syscalls it can make, whether it can escalate privileges, and what network access it has. These are the `[Service]` unit directives that form the backbone of container-like isolation for any service.

## Minimal Hardened Service Template

```ini
[Unit]
Description=My Hardened Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/mydaemon --config /etc/mydaemon/config.yaml

# --- Hardening directives ---
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadOnlyPaths=/
ReadWritePaths=/var/run/mydaemon /var/log/mydaemon
PrivateTmp=true
PrivateDevices=true
PrivateUsers=true
ProtectHostname=true
ProtectClock=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
LockPersonality=true
MemoryDenyWriteExecute=false
RestrictRealtime=true
RestrictSUIDSGID=true
RemoveIPC=true
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
RestrictNamespaces=true
RestrictAddressFamilies=inet inet6
LimitNOFILE=65536
LimitNPROC=512
LimitCORE=0

[Install]
WantedBy=multi-user.target
```

## Directive Reference

### Privilege Escalation

```ini
# Prevent the process or its children from gaining new privileges
# via setuid/setgid binaries or file capabilities
NoNewPrivileges=true

# Run as a non-root user (must create the user first)
User=mydaemon
Group=mydaemon
```

### Filesystem Isolation

```ini
# ProtectSystem: mount parts of the filesystem read-only
# Options (cumulative):
#   true     → /usr and /boot read-only
#   full     → /usr, /boot, /etc read-only (you must add ReadWritePaths for /etc modifications)
#   strict   → entire filesystem read-only (nothing writable except ReadWritePaths)
ProtectSystem=strict

# ProtectHome: hide user's home directories from this service
#   read-only → /home visible but read-only
#   true      → /home, /root, /run/user hidden entirely
#   tmpfs     → mount tmpfs over /run/user/<uid> (empty homes)
ProtectHome=read-only

# Additional paths the service can write to (in addition to /tmp, /var/tmp by default)
ReadWritePaths=/var/run/mydaemon /var/log/mydaemon /var/data

# Root directory is always read-only with ProtectSystem=strict
# Add exceptions here:
ReadWritePaths=/var/lib/mydaemon /var/log

# Completely hide a path from the service's view
InaccessiblePaths=/proc/sys/kernel/debug /sys/fs/cgroup/systemd
```

### Process Isolation

```ini
# PrivateTmp: give the service its own /tmp and /var/tmp
# Prevents IPC via POSIX shared memory, prevents seeing other processes' tmp files
PrivateTmp=true

# PrivateDevices: give the service only /dev/null, /dev/zero, /dev/urandom
# Hides real hardware devices (no access to /dev/sda, etc.)
PrivateDevices=true

# PrivateUsers: run as UID/GID that doesn't overlap with host users
# Service sees "nobody" (65534) instead of real UID
PrivateUsers=true

# Does NOT set User= — still runs as root but in isolated user namespace
```

### System State Protection

```ini
# Prevent changes to system hostname (unshared UTS namespace)
ProtectHostname=true

# Prevent clock modification
ProtectClock=true

# Prevent access to /proc/sys, /sys, /proc/keys, etc.
ProtectKernelTunables=true

# Prevent loading/unloading kernel modules
ProtectKernelModules=true

# Prevent reading kernel log buffer
ProtectKernelLogs=true

# Prevent personality changes (prevents setarch/uname --uname=2)
LockPersonality=true

# Prevent memory writes that are also executable (Meltdown mitigation)
MemoryDenyWriteExecute=true

# Prevent real-time scheduling (prevents latency attacks via FIFO/RR scheduling)
RestrictRealtime=true

# Prevent setuid/setgid binaries from being executed
RestrictSUIDSGID=true

# Remove IPC objects when service stops (System V and POSIX shm)
RemoveIPC=true
```

### Syscall Filtering

```ini
# Allow only system-service syscalls (blocks risky ones like mount, mknod)
SystemCallFilter=@system-service

# @system-service includes ~250 safe syscalls for services
# Other presets:
#   @basic-io        → basic I/O syscalls
#   @clock           → time-related syscalls
#   @cpu-emulation   → qemu-specific
#   @debug           → debugger syscalls (BLOCK these for most services)
#   @file-system     → filesystem syscalls
#   @io-event        → epoll, poll, select
#   @ipc             → IPC syscalls
#   @network-io      → basic network I/O
#   @process         → process management
#   @raw-io          → raw I/O, mount, mknod (BLOCK for most)
#   @setuid          → setuid/setgid syscalls
#   @signal          → signal handling
#   @timer           → timer syscalls

# Return EPERM instead of killing the process (default is SIGSYS)
SystemCallErrorNumber=EPERM

# Deny specific syscalls:
SystemCallFilter=~@clock @debug @module @mount @obsolete @raw-io @reboot

# Log denied syscalls (good for finding what your service actually needs)
SystemCallLog=trace
```

### Network Isolation

```ini
# Restrict which address families the service can use
# inet  = IPv4
# inet6 = IPv6
# unix  = AF_UNIX sockets (local IPC)
# netlink = kernel netlink sockets
RestrictAddressFamilies=inet inet6
# To block all networking:
RestrictAddressFamilies=unix

# If you need AF_UNIX only (local IPC):
RestrictAddressFamilies=unix
```

### Resource Limits

```ini
# Limit number of file descriptors
LimitNOFILE=65536

# Limit number of processes
LimitNPROC=512

# Limit CPU time (unit: seconds)
LimitCPU=3600

# Disable core dumps (prevents reading process memory from core file)
LimitCORE=0

# Other limits:
LimitAS=67108864      # Address space limit (64M)
LimitRSS=67108864      # Physical memory (64M)
LimitNOFILE=65536      # Open files
LimitNPROC=512         # Processes
LimitLOCKS=1024        # File locks
LimitSIGPENDING=512    # Queued signals
```

### Namespace Isolation

```ini
# Restrict namespace access:
#   user     → prevent user namespace creation
#   pid      → prevent PID namespace creation
#   network  → prevent network namespace creation
#   mount    → prevent mount namespace creation
#   uts      → prevent UTS namespace creation
#   ipc      → prevent IPC namespace creation
#   cgroup   → prevent cgroup namespace creation
RestrictNamespaces=true

# Restrict PID namespace (if you need your service as PID 1):
# (Usually you want this OFF — let systemd manage PID 1)
# RestrictNamespaces=true blocks new PID namespaces unless you specifically allow
```

### User/Group Identity

```ini
# Run as specific user (creates unprivileged identity on host)
User=myapp
Group=myapp

# DynamicUser=yes — create a transient user/group for the service
# No need to create system users — service gets a unique UID/GID at runtime
DynamicUser=yes

# Supplementary groups
SupplementaryGroups=myapp-group
```

## CIS Benchmark Patterns

CIS (Center for Internet Security) benchmarks recommend these for all systemd services:

```ini
[Service]
# CIS: No privileged services unless necessary
User=nobody

# CIS: Limit core dumps
LimitCORE=0

# CIS: No new privileges
NoNewPrivileges=true

# CIS: Filesystem restrictions
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/
ReadWritePaths=/var/run /var/log /tmp /var/tmp

# CIS: Restrict networking
RestrictAddressFamilies=inet inet6

# CIS: Restrict syscalls
SystemCallFilter=@system-service

# CIS: No realtime scheduling
RestrictRealtime=true

# CIS: No setuid binaries
RestrictSUIDSGID=true

# CIS: Remove IPC
RemoveIPC=true

# CIS: No tmpfs unless needed
PrivateTmp=true
```

## Debugging Hardened Services

```bash
# Start with full debug output:
SYSTEMD_LOG_LEVEL=debug systemctl status myservice

# See what syscalls a service needs (before locking down):
# Run the binary under strace to see syscalls:
strace -f -e trace=open,openat,read,write,execve -o /tmp/trace.log /usr/bin/mydaemon

# Or use systemd's built-in syscall auditing:
# Add to service:
Environment=SYSTEMD_LOG_LEVEL=debug

# Common failure modes:
# 1. Permission denied on /var/log or /run
#    → Add ReadWritePaths=/var/log/myapp
# 2. Cannot create threads
#    → Raise LimitNPROC or remove RestrictNamespaces=user
# 3. Cannot resolve DNS
#    → Don't use RestrictAddressFamilies=inet (remove it or add unix)
# 4. Cannot read config from /etc
#    → ProtectSystem=full blocks /etc writes, not reads
#    → If you need /etc writable: use ProtectSystem=Boot reads
# 5. fopen("/dev/null") fails
#    → PrivateDevices=true restricts /dev/ — if you need specific devices, add:
DeviceAllow=/dev/null rw
DeviceAllow=/dev/urandom r
```

## Checking a Service's Security Posture

```bash
# View the effective security settings of a running service:
systemd-analyze security myservice
# Shows a 0-10 score for each hardening directive
# Red items = not configured, Green = hardened

# Full systemd-analyze output:
systemd-analyze dot myservice | dot -Tsvg > service.svg
# Dependency graph

# Verify no dangerous capabilities:
cat /proc/$(pgrep myservice)/status | grep Cap
# Check: does it have CapSysAdmin? CapNetAdmin?
# Should be: CapAmb=0 for unprivileged, no Cap_* for non-container services
```

## Minimal vs Maximum Hardening

```ini
# MINIMAL (still better than nothing):
[Service]
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/
ReadWritePaths=/var/run /var/log
RestrictAddressFamilies=inet inet6

# MAXIMUM (container-like isolation):
[Service]
Type=simple
User=nobody
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
PrivateDevices=true
PrivateUsers=true
ProtectHostname=true
ProtectClock=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
RestrictSUIDSGID=true
RemoveIPC=true
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
RestrictNamespaces=true
RestrictAddressFamilies=unix
LimitNOFILE=65536
LimitNPROC=512
LimitCORE=0
```