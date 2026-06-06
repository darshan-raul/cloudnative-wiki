---
title: Storage and I/O Performance
description: Linux storage performance — I/O schedulers, blockdev, noatime, fstrim, hdparm, SSD tuning, filesystem mount options, virtual memory
tags:
  - linux
  - storage
  - performance
---

# Storage and I/O Performance

Storage performance tuning covers: I/O schedulers, filesystem mount options, block device tuning, SSD optimization, and virtual memory/swappiness.

## I/O Schedulers

The I/O scheduler determines the order in which block I/O requests are submitted to disk. Different schedulers optimize for different workloads.

### Available Schedulers

```
none       → no scheduling (pass-through, best for NVMe/SSDs)
mq-deadline → per-I/O priority queues (good for mixed read/write)
bfq         → budget fair queueing (good for desktop/interactive)
kyber        → token bucket (good for low-latency)
cfq         → completely fair queueing (legacy, still available)
noop         → FIFO (very low CPU overhead, fast SSDs)
```

```bash
# Check available schedulers for a device:
cat /sys/block/sda/queue/scheduler
# [mq-deadline] kyber bfq none

# Current scheduler:
cat /sys/block/sda/device/scsi_disk/0:0:0:0/manageable_scheduled
```

### Setting the Scheduler

```bash
# Per-device (runtime):
echo mq-deadline > /sys/block/sda/queue/scheduler

# NVMe: set to none (no scheduler needed):
echo none > /sys/block/nvme0n1/queue/scheduler

# Persistent: via kernel boot param:
# Add to GRUB_CMDLINE_LINUX in /etc/default/grub:
# scsi_mod.use_blk_mq=1 scsi_mod.default_dev_flags=0x41
# Or per-device udev rule:

# /etc/udev/rules.d/60-ioscheduler.rules
ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_TYPE}=="disk", \
    KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", \
    ATTR{queue/scheduler}="none"

ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_TYPE}=="disk", \
    KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", \
    ATTR{queue/scheduler}="bfq"
```

### Scheduler-Specific Settings

```bash
# mq-deadline tunables:
echo 16 > /sys/block/sda/queue/iosched/read_lat_nsec     # read latency target (ns)
echo 32 > /sys/block/sda/queue/iosched/write_lat_nsec    # write latency target (ns)
echo 256 > /sys/block/sda/queue/iosched/fifo_batch      # batch size

# bfq tunables:
echo 8 > /sys/block/sda/queue/iosched/quantum         # max requests per queue
echo 20 > /sys/block/sda/queue/iosched/low_latency    # enable low-latency mode
echo 200 > /sys/block/sda/queue/iosched/target_latency  # target latency (ms)

# kyber tunables:
echo 16 > /sys/block/sda/queue/iosched/rd_lat_ns       # read target latency
echo 64 > /sys/block/sda/queue/iosched/wr_lat_ns       # write target latency
```

## Read-Ahead (Block Size)

```bash
# Check current read-ahead (in 512-byte sectors, so 256 = 128KB):
blockdev --getra /dev/sda
# 256

# Set read-ahead:
blockdev --setra 4096 /dev/sda   # 4MB read-ahead (8KB sectors * 4096)
# Good for sequential reads (databases, media)

# For random I/O (databases):
blockdev --setra 256 /dev/sda    # 128KB

# Persistent via udev:
# /etc/udev/rules.d/60-read-ahead.rules
ACTION=="add|change", KERNEL=="sd[a-z]", \
    ATTR{queue/read_ahead_kb}="4096"
```

## Filesystem Mount Options

### SSD/Flash Optimization

```bash
# /etc/fstab — add to SSD partitions:
# UUID=abc123  /  ext4  defaults,noatime,nodiratime,discard,errors=remount-ro  0  1

# Key mount options:
# noatime         → don't update atime on read (huge performance gain)
# nodiratime      → don't update dir atimes (noatime already skips dirs)
# discard         → enable TRIM (SSD garbage collection) on delete
# errors=remount-ro → remount read-only on errors
# barrier=1       → enable write barriers (data integrity, slight perf cost)
# barrier=0       → disable barriers (faster, risky on power loss without battery-backed RAID)
# commit=30        → flush metadata every 30s (default 5s, higher = fewer writes)
# nobh             → don't attach buffer heads to pages (ext4 only, performance)
# data=writeback   → ext4: don't journal data, only metadata (faster, riskier)
# data=ordered     → ext4: journal data in order (default, safe)
# data=journal     → ext4: journal all data (slowest, safest)

# fstab example for ext4 SSD:
# UUID=abc123  /var/lib/postgresql  ext4  defaults,noatime,nodiratime,discard  0  2
```

### xfs Mount Options

```bash
# xfs options for performance:
# /dev/sda3  /data  xfs  defaults,noatime,nodiratime,swalloc,attr2  0  0

# noatime,nodiratime  → skip atime updates
# swalloc         → stripe-aligned allocation (for hardware RAID)
# attr2           → improved attribute format (default in modern xfs)
# inode64         → allow inodes anywhere on device (large filesystems)
# largeio         → use large I/O for "sw" (optimized for large files)
# noquota         → disable quota accounting (if not needed)
```

### btrfs Mount Options

```bash
# btrfs SSD options:
# /dev/sda2  /  btrfs  defaults,noatime,ssd,ssd_spread,compress=zstd  0  0

# ssd              → enable SSD optimizations
# ssd_spread       → try to use more unallocated space (better for SSDs)
# compress=zstd    → enable zstd compression (faster than NO compression on some workloads!)
# compress=lzo     → alternative (faster than zstd, lower compression ratio)
# compress=no      → no compression
# commit=120       → commit interval 120s (default 30s, reduces writes)
# noatime          → no access time updates
# space_cache=v2   → improved free space cache (for rotational disks)
```

## fstrim — SSD TRIM

SSDs need periodic TRIM to reclaim deleted blocks. Without TRIM, write performance degrades over time.

```bash
# Manual TRIM (run periodically):
fstrim -a              # TRIM all mounted filesystems
fstrim -v /            # TRIM root
fstrim -v /home        # TRIM home

# Check if filesystem supports discard:
mount | grep discard
# /dev/sda1 on / type ext4 (rw,noatime,discard)

# Automated via systemd timer (weekly by default on most distros):
systemctl status fstrim.timer
systemctl list-timers fstrim.timer

# Check if discard is working:
fstrim -v /
# /: 48.4 GiB (52073123840 bytes) trimmed

# NOTE: If mount option is "discard", TRIM happens on delete (synchronous)
#       If not, use fstrim timer (periodic batch TRIM) — better performance
```

## hdparm — IDE/SATA Disk Tuning

```bash
# Check drive info and performance:
hdparm -I /dev/sda
hdparm -i /dev/sda

# Measure read speed:
hdparm -t /dev/sda
# Timing buffered disk reads:  420.56 MB/sec

# Measure cached read:
hdparm -T /dev/sda
# Timing cached reads:  5203.62 MB/sec

# Power management (spin down idle drives):
hdparm -B 254 /dev/sda    # 1-127: power level (127 = minimum power)
hdparm -y /dev/sda        # put drive to standby
hdparm -Y /dev/sda        # put drive to sleep

# Check power mode:
hdparm -C /dev/sda
# drive state is:  active/idle

# Disable automatic acoustic management:
hdparm -M 254 /dev/sda   # 128=quiet, 254=fast

# Set DMA mode:
hdparm -d 1 /dev/sda     # enable DMA
hdparm -X34 /dev/sda     # Ultra DMA mode 2
hdparm -X66 /dev/sda     # Ultra DMA mode 4
```

## Virtual Memory and Swappiness

```bash
# Check memory:
free -h

# Check swap usage:
swapon -s
cat /proc/swaps

# Current swappiness (0-100, how aggressively to swap):
cat /proc/sys/vm/swappiness
# Default: 60

# Change swappiness:
sysctl vm.swappiness=10
# Add to /etc/sysctl.d/99-tuning.conf:
# vm.swappiness=10

# When to lower swappiness:
# - Databases: swappiness=10 (keep data in RAM, not swap)
# - Desktops: swappiness=60-80 (free RAM for cache)
# - Containers: swappiness=10-30

# vfs_cache_pressure (how aggressively to reclaim inode/dentry cache):
# Higher = less cache kept (more RAM for processes)
# Lower = more cache kept (better file performance)
cat /proc/sys/vm/vfs_cache_pressure
# Default: 100
sysctl vm.vfs_cache_pressure=50   # keep more dentry/inode cache

# memory pressure (kernel 4.0+):
cat /proc/sys/vm/memory_pressure
# Read-only score of memory pressure (for OOM decisions)
```

## Monitoring I/O

```bash
# iostat (from sysstat package):
iostat -xz 1          # 1-second interval, extended
iostat -dx /dev/sda 1  # specific device
# %util = disk utilization (100% = saturated)
# await = average time for I/O (ms)
# r_await, w_await = read/write separate
# svctm = average service time (ms)
# ar_await, aw_await = queue wait time

# iotop (per-process I/O):
iotop
iotop -a              # accumulated I/O since start
iotop -o              # only active processes
iotop -P              # only processes (not threads)

# pidstat (per-process I/O):
pidstat -d 1          # I/O per second
pidstat -dl 1         # I/O with command line

# check I/O scheduler queue:
cat /sys/block/sda/queue/nr_requests   # default 128, increase for throughput
cat /sys/block/sda/queue/write_cache

# Using blktrace (advanced — traces I/O requests):
blktrace -d /dev/sda -o - | blkparse -i - > /tmp/io.trace
```

## Quick Reference

```bash
# Check scheduler
cat /sys/block/sda/queue/scheduler

# Set scheduler
echo mq-deadline > /sys/block/sda/queue/scheduler

# Check read-ahead
blockdev --getra /dev/sda

# TRIM SSD
fstrim -v /

# Check mount options
mount | grep /dev/sda

# I/O stats
iostat -xz 1
iotop

# Swappiness
cat /proc/sys/vm/swappiness
sysctl vm.swappiness=10

# DMA mode
hdparm -I /dev/sda | grep -i dma
```