---
title: "10 — Storage Basics"
description: Linux storage — disks, partitions, filesystems, mount, fstab, UUID, basic disk management
tags:
  - linux
  - concepts
---

# 10 — Storage Basics

Linux sees storage as files. Disks are partitioned, partitions get filesystems, and everything gets mounted somewhere in the tree.

## The Storage Hierarchy

```
Physical disk (/dev/sda)
  └── Partition 1 (/dev/sda1)   ← formatted with filesystem
  └── Partition 2 (/dev/sda2)   ← formatted with filesystem
  └── Partition 3 (/dev/sda3)   ← formatted with filesystem
       └── Mounted at /data     ← appears in the directory tree
```

## Disks and Partitions

```bash
# List all disks and partitions:
lsblk
fdisk -l

# Example output:
# NAME  MAJ:MIN  RM  SIZE  RO  TYPE  MOUNTPOINT
# sda     8:0    0   100G  0   disk
# ├─sda1  8:1    0   512M  0   part  /boot/efi
# ├─sda2  8:2    0   99.5G 0   part  /
# sdb     8:16   0   1T    0   disk
# └─sdb1  8:17   0   1T    0   part  /data

# View partition table:
fdisk -l /dev/sda
parted /dev/sda print
```

## Filesystems

A filesystem defines how data is stored and retrieved on a partition. Different filesystems have different features.

```
ext4      — default for most Linux, journaling, 16TB max
xfs       — high-performance, preferred for large filesystems, RHEL default
btrfs     — copy-on-write, snapshots, checksums — modern features
vfat      — FAT32 — used for EFI System Partition (ESP)
swap      — not a filesystem — swap space
ntfs      — Windows filesystem — accessible via ntfs-3g driver
```

```bash
# Check filesystem type of a partition:
blkid /dev/sda1
# /dev/sda1: UUID="abc123" TYPE="ext4" PARTUUID="..."

# What filesystem is mounted where:
df -Th
# Filesystem  Type  Size  Used  Avail  Use%  Mounted on
# /dev/sda2   ext4   99G   20G   74G   22%  /
# tmpfs       tmpfs  7.8G     0  7.8G    0%  /dev/shm
```

## Creating a Filesystem (mkfs)

```bash
# Create ext4:
sudo mkfs.ext4 /dev/sdb1

# Create xfs:
sudo mkfs.xfs /dev/sdb1

# Create swap:
sudo mkswap /dev/sdb2
sudo swapon /dev/sdb2     # activate immediately
```

## Mounting

```bash
# Mount a filesystem:
sudo mount /dev/sdb1 /mnt/data

# Mount with specific filesystem:
sudo mount -t ext4 /dev/sdb1 /mnt/data

# Mount read-only:
sudo mount -o ro /dev/sdb1 /mnt/data

# Unmount:
sudo umount /mnt/data

# Lazy unmount (if busy):
sudo umount -l /mnt/data

# Force unmount (if nothing else works):
sudo umount -f /mnt/data
```

## UUIDs — The Right Way to Reference Disks

Disk device names (`/dev/sda1`) can change — USB drives, SATA reorder, kernel naming. **UUIDs are permanent identifiers** and are the correct way to reference disks in fstab.

```bash
# Find the UUID of a partition:
sudo blkid
# /dev/sda1: UUID="abc123" TYPE="ext4" PARTUUID="..."
# /dev/sdb1: UUID="def456" TYPE="ext4" PARTUUID="..."

# Mount by UUID:
sudo mount UUID="abc123" /mnt/data

# Also:
ls -la /dev/disk/by-uuid/
# lrwxrwxrwx 1 root root 10 Jun  6 10:00 abc123 -> ../../sda1
```

## fstab — Mount at Boot

`/etc/fstab` defines filesystems to mount automatically at boot.

```bash
cat /etc/fstab
# UUID=abc123 /               ext4    defaults        0 1
# UUID=def456 /data           ext4    defaults        0 2
# UUID=ghi789 none             swap    sw              0 0
# tmpfs /tmp tmpfs defaults   0 0
```

### fstab Fields

```
<device>  <mount point>  <type>  <options>  <dump>  <pass>
device    = UUID=... or /dev/sda1
mount pt  = / or /data or swap or none
type      = ext4, xfs, btrfs, swap, tmpfs
options   = defaults, ro, noatime, etc. (comma-separated)
dump      = 0 (don't backup with dump) — almost always 0
pass      = 0 (skip fsck), 1 (root), 2 (other) — fsck order at boot
```

### Common fstab Entries

```bash
# Data partition:
UUID=def456  /data  ext4  defaults  0 2

# NFS network mount:
192.168.1.100:/shared  /mnt/nfs  nfs  defaults  0 0

# tmpfs (RAM disk):
tmpfs  /tmp  tmpfs  defaults,noatime,mode=1777  0 0

# EFI System Partition:
UUID=abc123  /boot/efi  vfat  umask=0077  0 2
```

## Disk Usage

```bash
# How much space is used?
df -h

# Per-directory size:
du -sh /var/log
du -sh /var/log/*
du -sh /var/log/*/ | sort -rh | head -10

# Largest files in a directory:
find /var/log -type f -exec du -h {} + | sort -rh | head -10
```

## LVM — Logical Volume Manager

LVM is a layer between partitions and filesystems that lets you resize and snapshot volumes dynamically. Most Linux servers use it.

```
Physical Volume (PV)   → /dev/sda3
  └── Volume Group (VG) → vg_main
        ├── Logical Volume (LV) → lv_root (root filesystem)
        ├── Logical Volume (LV) → lv_home (home filesystem)
        └── Logical Volume (LV) → lv_data (data filesystem)
```

```bash
# Show LVM layout:
lsblk
pvs         # physical volumes
vgs         # volume groups
lvs         # logical volumes

# Resize a volume (online, no unmount needed with ext4/xfs):
sudo lvextend -L +10G /dev/vg_main/lv_data
sudo resize2fs /dev/vg_main/lv_data   # for ext4
sudo xfs_growfs /data                  # for xfs
```

## Quick Reference

```bash
# List storage
lsblk
fdisk -l
df -Th

# Filesystem type
blkid

# Create filesystem
mkfs.ext4 /dev/sdb1
mkfs.xfs /dev/sdb1
mkswap /dev/sdb2

# Mount
mount /dev/sdb1 /mnt/data
mount UUID="..." /mnt/data
umount /mnt/data

# fstab
cat /etc/fstab

# UUID
blkid
ls -la /dev/disk/by-uuid/

# Disk usage
df -h
du -sh /var/log
du -sh /var/log/*

# LVM
pvs; vgs; lvs
```