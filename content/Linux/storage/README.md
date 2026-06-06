---
title: Linux Storage
description: Linux storage — disks, partitioning, LVM, RAID, filesystems, mount, fstab, storage performance tuning
tags:
  - linux
  - storage
---

# Linux Storage

Linux's storage model is layered: physical disks get partitioned, partitions get filesystems, and filesystems get mounted somewhere in the directory tree. LVM adds a flexible middle layer for resizing and snapshots. This section covers all of it.

Start with [[disks-partitions]] if you need to understand the disk → partition → filesystem chain. [[filesystems]] explains what filesystems actually do and when to choose ext4 vs xfs vs btrfs.

## Disk Management

**[[disks-partitions|Disks and Partitions]]** — How Linux names disks (`/dev/sda`, `/dev/nvme0n1`), partition tables (MBR vs GPT), and tools to manage them (`fdisk`, `parted`, `lsblk`). Creating partitions, reading the partition table, and understanding the difference between primary, extended, and logical partitions.

## Filesystems

**[[filesystems|Filesystems]]** — How filesystems organize data on disk. ext4 (journal, 16TB max, stable), xfs (high throughput, large files, RHEL default), btrfs (copy-on-write, snapshots, checksums, still maturing). Creating filesystems with `mkfs`, checking them with `fsck`, and tuning with `tune2fs` / `xfs_info`.

## Logical Volume Manager

**[[lvm|LVM]]** — The three-layer system: Physical Volumes (PVs, raw partitions), Volume Groups (VGs, pooled storage), and Logical Volumes (LVs, the usable "partitions"). How LVM makes resizing trivial compared to raw partitions. Thin provisioning for overallocation. Snapshots for backups. Common commands: `pvcreate`, `vgcreate`, `lvcreate`, `lvextend`, `lvreduce`.

## RAID

**[[raid|RAID]]** — Software RAID levels (0, 1, 5, 6, 10) and how they differ in redundancy and performance. `mdadm` for creating and managing software RAID arrays. How Linux's `md` kernel driver handles resync, bitmap journals, and hot spares. Checking array health with `/proc/mdstat`.

## Mounting and fstab

[[disks-partitions]] covers the `mount` command and UUIDs. Key concepts: always reference disks by UUID (not `/dev/sda1` — it can change), and `/etc/fstab` for mounts that happen automatically at boot.

## Performance

**[[storage-performance-tuning|Storage Performance Tuning]]** — I/O schedulers (`mq-deadline`, `bfq`, `noop`) and when to switch them. `blockdev --setra` for read-ahead. Filesystem mount options: `noatime`, `nodiratime`, `relatime`, `discard` (for SSDs). `fstrim` for SSDTRIM. `hdparm` and `sdparm` for drive diagnostics. Swappiness and the virtual memory subsystem.