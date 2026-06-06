---
title: TMPFS
description: Linux tmpfs — RAM-based filesystem, /dev/shm, /run, /tmp, size limits, mtmpfs
tags:
  - linux
  - filesystem
  - memory
---

# tmpfs

tmpfs is a **RAM-based filesystem** — data stored in tmpfs lives entirely in memory (with optional swap backing). It's extremely fast because there's no disk I/O, and it's automatically freed when the filesystem is unmounted or the system reboots.

## What tmpfs Is

```
tmpfs:
  - Uses RAM + swap as backing store
  - No disk — no spinning, no seek
  - Fixed size limit (doesn't grow forever)
  - Contents lost on reboot
  - Permissions work normally (unlike /dev/shm in older kernels)
```

## Common tmpfs Mounts

```bash
# Most Linux systems mount several things as tmpfs:
mount | grep tmpfs
# tmpfs on /run type tmpfs (rw,nosuid,nodev,mode=755)
# tmpfs on /dev/shm type tmpfs (rw,nosuid,nodev)
# tmpfs on /tmp type tmpfs (rw,nosuid,nodev)

# /run — runtime data (PID files, sockets)
# /dev/shm — POSIX shared memory (also used by df -h /dev/shm)
# /tmp — temporary files (often tmpfs on modern systems)
```

## Creating a tmpfs

```bash
# Mount tmpfs manually
mount -t tmpfs -o size=1G tmpfs /mnt/tmpfs

# With options
mount -t tmpfs -o size=512M,mode=1777,uid=root,gid=root tmpfs /mnt/myfs

# Add to /etc/fstab for persistence
tmpfs  /mnt/myfs  tmpfs  defaults,size=512M,mode=1777  0 0
```

## Options

```bash
# size — maximum size (required in fstab, optional on CLI)
mount -t tmpfs -o size=256M tmpfs /mnt

# nr_blocks — same as size (in 4K blocks)
# nr_inodes — max number of inodes (file count limit)

# mode — permissions
mount -t tmpfs -o mode=1777 tmpfs /mnt  # sticky bit

# uid, gid — ownership
mount -t tmpfs -o uid=1000,gid=1000 tmpfs /mnt

# Defaults: size=half of RAM, mode=1777, uid=0, gid=0
```

## /dev/shm — POSIX Shared Memory

```bash
# /dev/shm is tmpfs mounted for shared memory
# POSIX shm: shmget(), shmat(), shmdt()

# df shows it
df -h /dev/shm
# Filesystem      Size  Used Avail Use% Mounted on
# tmpfs            7.8G     0  7.8G   0% /dev/shm

# Useful for:
# - tmpfs for caches (Chrome uses /dev/shm for default tmpfs)
# - tmpfs for Docker's tmpfs mounts
docker run --tmpfs /run:rw,noexec,nosuid,size=1G nginx

# Increase /dev/shm size (Docker with --shm-size)
docker run --shm-size 256M nginx
```

## tmpfs for Performance

```bash
# /tmp as tmpfs (often default on modern distros):
# Check if /tmp is tmpfs:
mount | grep " /tmp "
# tmpfs on /tmp type tmpfs ...  ← yes

# If not, mount as tmpfs:
mount -t tmpfs -o size=10G tmpfs /tmp

# Browser cache as tmpfs (ram browsers):
mount -t tmpfs -o size=2G,uid=1000 tmpfs /home/darshan/cache/chromium

# Build cache as tmpfs:
mount -t tmpfs -o size=10G tmpfs /var/cache/build

# SQLite database on tmpfs (max speed):
mount -t tmpfs -o size=1G tmpfs /mnt/db
# WARNING: data lost on reboot — use for temp tables, not persistence!
```

## Checking tmpfs Usage

```bash
# df
df -h | grep tmpfs

# du (be careful — walking tmpfs can be slow on large)
du -sh /tmp

# Check size
mount | grep " /tmp "
# tmpfs on /tmp type tmpfs (rw,nosuid,nodev,relatime,size=10240k)

# Resize tmpfs (if remountable):
mount -o remount,size=5G /tmp
```

## tmpfs vs ramfs

| Feature       | tmpfs                          | ramfs                          |
|--------------|-------------------------------|-------------------------------|
| Backing store | RAM + swap                     | RAM only (no swap)             |
| Size limit   | Yes (enforced)                 | No (grows until OOM)           |
| Fixed size   | Can remount to change size     | Cannot change size             |
| OOM behavior | Writes fail at size limit      | OOM killer triggers             |
| Disk quotas  | Supported                      | Not supported                  |
| Persistence  | Lost on reboot                 | Lost on reboot                 |
| Swappiness   | Can use swap                   | Cannot use swap                |

## tmpfs and Containers

```bash
# Docker tmpfs mount
docker run --tmpfs /tmp:rw,noexec,size=1G alpine

# Kubernetes tmpfs volume
spec:
  containers:
  - name: app
    volumeMounts:
    - name: tmpfs
      mountPath: /tmp
  volumes:
  - name: tmpfs
    emptyDir:
      medium: Memory     # ← tmpfs
      sizeLimit: 1Gi

# Kubernetes memory-backed emptyDir (tmpfs):
emptyDir:
  medium: Memory
  sizeLimit: 512Mi
```

## Security Notes

```bash
# tmpfs should usually be nosuid,nodev,noexec
mount -t tmpfs -o nosuid,noexec,nodev,mode=1777 tmpfs /mnt

# Common tmpfs flags:
# rw, nosuid, nodev, noexec, relatime, size=...
```