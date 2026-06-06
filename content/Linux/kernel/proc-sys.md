---
title: /proc and /sys
description: Linux /proc and /sys filesystems — kernel data, process info, tunable parameters, hardware visibility
tags:
  - linux
  - kernel
---

# /proc and /sys

`/proc` and `/sys` are **virtual filesystems** — they don't exist on disk, they're generated on-the-fly by the kernel and expose kernel data structures, configuration, and hardware information to userspace. Everything readable in them comes from the kernel; writing to them configures kernel parameters.

## /proc — Process and Kernel Information

`/proc/` is organized into directories by PID (processes) plus special files for system-wide data.

### Process Information

```
/proc/1234/              # info about process PID 1234
/proc/$$/                # current process
/proc/self/             # symlink to current process's /proc/PID
```

| File              | What it contains                                |
|------------------|------------------------------------------------|
| `/proc/PID/cmdline` | Command line (null-separated)                  |
| `/proc/PID/environ` | Environment variables (null-separated)         |
| `/proc/PID/status`  | Human-readable process state (UID, memory, etc.) |
| `/proc/PID/statm`   | Memory usage in pages                          |
| `/proc/PID/maps`    | Memory mappings (address → file)                |
| `/proc/PID/fd/`     | Open file descriptors (symlinks to files/sockets)|
| `/proc/PID/fdinfo/` | FD metadata (flags, position)                 |
| `/proc/PID/cgroup`  | Cgroup membership                              |
| `/proc/PID/ns/`     | Namespace inodes (shows namespace IDs)          |
| `/proc/PID/syscall` | Current syscall number and args                 |
| `/proc/PID/wchan`   | Kernel function the process is sleeping in      |
| `/proc/PID/stack`   | Kernel stack trace (if running in kernel)      |

### System-Wide /proc Files

```
/proc/cmdline          # kernel command line (boot params)
/proc/cpuinfo          # CPU model, cores, flags
/proc/meminfo          # memory usage (free, available, cached)
/proc/vmstat           # virtual memory statistics
/proc/loadavg          # load average (uptime)
/proc/uptime           # system uptime (seconds)
/proc/partitions       # block device partitions
/proc/interrupts       # IRQ counts per CPU
/proc/softirqs         # softirq counts per CPU
/proc/stat             # kernel/system statistics
/proc/diskstats        # disk I/O statistics
/proc/buddyinfo        # memory fragmentation (buddy allocator)
/proc/pagetypeinfo     # memory page type breakdown
/proc/slabinfo         # kernel slab cache info (slaballoc)
/proc/zoneinfo         # memory zone info (DMA, Normal, etc.)
/proc/kallsyms         # kernel symbol addresses
/proc/modules          # loaded kernel modules
/proc/mounts           # current mounts (same as /etc/mtab)
/proc/swaps            # active swap devices
/proc/sys/             # TUNABLE KERNEL PARAMETERS (WRITE HERE)
```

## /proc/sys — Tunable Kernel Parameters

Files in `/proc/sys/` control kernel behavior. **Readable with `cat`, writable with `echo` or `sysctl`**:

```bash
# Read
cat /proc/sys/net/ipv4/ip_forward
# 0

# Write (temporary — lost on reboot)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Persistent: use sysctl
sysctl -w net.ipv4.ip_forward=1
```

### Key /proc/sys Paths

| Path                          | What it controls                         |
|-------------------------------|------------------------------------------|
| `net/ipv4/ip_forward`          | Enable IP forwarding (router)           |
| `net/ipv4/conf/eth0/forwarding` | Per-interface forwarding                 |
| `net/ipv4/tcp_syncookies`      | Enable SYN cookies                       |
| `net/ipv4/icmp_echo_ignore_all` | Ignore all ICMP pings                   |
| `net/ipv4/icmp_echo_ignore_broadcasts` | Ignore broadcast pings        |
| `net/ipv4/conf/default/rp_filter` | Reverse path filtering                |
| `net/core/somaxconn`            | Max listen() backlog                     |
| `net/core/file-max`             | System-wide max open files               |
| `net/ipv4/tcp_max_syn_backlog`  | Max pending TCP connections              |
| `vm/swappiness`                 | How aggressively to swap (0-100)         |
| `vm/dirty_ratio`                | % of RAM before pdflush starts writing   |
| `vm/dirty_background_ratio`     | % of RAM before background flush starts  |
| `vm/overcommit_memory`          | Memory overcommit (0=heuristic, 1=always)|
| `kernel/hostname`               | System hostname                          |
| `kernel/domainname`             | NIS domain name                          |
| `kernel/shmmax`                  | Max shared memory segment size           |
| `kernel/shmall`                  | Max shared memory pages total            |
| `kernel/threads-max`             | Max threads in system                    |
| `kernel/pid_max`                 | Max PID number                          |
| `kernel/randomize_va_space`      | ASLR (0=off, 1=stack, 2=all)           |
| `kernel/sysrq`                   | SysRq key enable (1=full, 0=disabled)   |
| `fs/file-max`                   | System-wide max open files               |
| `fs/inotify/max_user_watches`   | inotify watches limit                   |
| `fs/inotify/max_user_instances` | inotify instances per user              |

### sysctl — Manage These Persistently

```bash
# View all
sysctl -a                       # all current values
sysctl -a --pattern ipv4        # filter by pattern

# Read specific
sysctl net.ipv4.ip_forward

# Set (temporary)
sysctl -w net.ipv4.ip_forward=1

# Persistent: /etc/sysctl.conf or /etc/sysctl.d/
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-router.conf
sysctl --system                 # reload from /etc/sysctl.d/

# Verify
sysctl net.ipv4.ip_forward
```

## /sys — Kernel Object Hierarchy

`/sys/` exposes the kernel's **device model** (sysfs) and provides access to device drivers, device tree, and hardware configuration:

```
/sys/
├── block/          # block devices (disks, partitions)
├── bus/            # bus types (PCI, USB, etc.)
├── class/          # device classes (net, block, tty, etc.)
├── devices/        # physical device hierarchy
├── dev/            # character and block device nodes
├── firmware/       # firmware (ACPI, DMI, etc.)
├── fs/             # pseudo filesystems (tmpfs, devpts, etc.)
├── hypervisor/     # if running under a hypervisor
├── kernel/         # kernel subsystem config
└── module/         # loaded kernel modules
```

### Key /sys Uses

```bash
# Block devices (disks)
ls /sys/block/
# sda  sr0  zram0

# Per-device info
cat /sys/block/sda/device/model
cat /sys/block/sda/size             # sectors (512 bytes each)
cat /sys/block/sda/queue/scheduler  # I/O scheduler
cat /sys/block/sda/queue/read_ahead_kb

# Change I/O scheduler (scheduler: none, mq-deadline, bfq, kyber)
echo mq-deadline > /sys/block/sda/queue/scheduler

# Set read-ahead
echo 4096 > /sys/block/sda/queue/read_ahead_kb

# Network interfaces
ls /sys/class/net/
# eth0  lo  wlan0

cat /sys/class/net/eth0/address     # MAC address
cat /sys/class/net/eth0/speed       # link speed
cat /sys/class/net/eth0/duplex      # full/half duplex
cat /sys/class/net/eth0/operstate   # up/down
ethtool eth0                        # more details

# Device info (PCI)
/sys/bus/pci/devices/
ls /sys/bus/pci/devices/0000:00:00.0/
cat /sys/bus/pci/devices/0000:00:00.0/vendor
cat /sys/bus/pci/devices/0000:00:00.0/device

# Loaded modules
ls /sys/module/
cat /sys/module/nf_conntrack/parameters/hashsize
```

## /proc vs /sys

| Aspect        | /proc                        | /sys                          |
|--------------|------------------------------|-------------------------------|
| Contents      | Process info + kernel stats  | Device model + device drivers  |
| Organization  | Per-PID dirs + system files  | Hierarchical tree (device tree)|
| Origin        | `fs/proc/` kernel code      | `fs/sysfs/` kernel code       |
| Writable      | Some files (tunables)       | Device attributes (driver-specific)|
| Use case      | Process inspection, tuning   | Hardware inspection, driver config |

## Practical Examples

```bash
# What's using memory right now?
cat /proc/meminfo
# MemAvailable: how much apps can use
# Cached: file cache (reclaimable)
# Shmem: shared memory

# What processes are using swap?
for f in /proc/*/status; do
  awk '/VmSwap/{print $1, $2}' "$f" 2>/dev/null | grep -v " 0 kB"
done

# What's the current load?
cat /proc/loadavg
# Compare with number of CPUs
nproc

# What IRQ is eth0 using?
cat /proc/interrupts | grep eth0

# Check for ASLR (Address Space Layout Randomization)
cat /proc/sys/kernel/randomize_va_space
# 0 = off, 1 = stack only, 2 = stack + VDSO + mmap
```