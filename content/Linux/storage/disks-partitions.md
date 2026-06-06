---
title: Disks and Partitions
description: Linux disks and partitions — /dev/sda, GPT, fdisk, parted, mkfs, mount, UUID, fstab
tags:
  - linux
  - storage
---

# Disks and Partitions

Linux exposes disks as `/dev/sd*` (SCSI/SATA), `/dev/nvme*` (NVMe), or `/dev/vd*` (virtio). Partitions are numbered slices of a disk, formatted with filesystems.

## Block Devices

```bash
# List all block devices
lsblk
# NAME MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
# sda      8:0    0  100G  0 disk
# ├─sda1   8:1    0    1M  0 part
# ├─sda2   8:2    0   50G  0 part /
# └─sda3   8:3    0   50G  0 part /home
# sdb      8:16   0 1T  0 disk
# sr0     11:0    1 1024M  0 rom

# NVMe
lsblk
# nvme0n1    259:0    0  512G  0 disk
# ├─nvme0n1p1 259:1    0  512G  0 part /

# Detailed info
fdisk -l /dev/sda
parted /dev/sda print
```

## Partition Tables

### MBR (MS-DOS) — Legacy

- Max 2TB disk, max 4 primary partitions
- Uses `fdisk`
- Partition type bytes in the MBR determine type (Linux, FAT, etc.)

### GPT — Modern

- Max disk size:8ZiB (ZB-scale)
- Max partitions: 128 (or64K with spec)
- Uses `gdisk` or `parted`
- UEFI systems require GPT for boot

## fdisk (MBR)

```bash
fdisk /dev/sdb
# Command (m for help): m
# p = print table
# n = new partition
# d = delete
# t = change type (83=Linux, 82=Swap, 8e=LVM)
# w = write and quit
# q = quit without writing

# Create a new Linux partition:
# n → p (primary) → 1 (partition number) → default start → +50G (size)
# t → 83 → w
```

## parted (GPT and MBR)

```bash
parted /dev/sdb
# (parted) help
# (parted) print
# (parted) mklabel gpt
# (parted) mkpart primary ext4 0% 50%
# (parted) set 1 boot on   # for bootable partition
# (parted) quit
```

## Filesystems

### Creating Filesystems

```bash
# ext4 (most common Linux fs)
mkfs.ext4 /dev/sdb1
mkfs.ext4 -L mydata /dev/sdb1        # with label
mkfs.ext4 -E lazy_itable_init=1      # fast format (no zeroing)
mkfs.ext4 -O ^has_journal            # no journal (smaller)

# xfs (good for large filesystems, default in RHEL)
mkfs.xfs /dev/sdb1
mkfs.xfs -L mydata /dev/sdb1

# btrfs (copy-on-write, snapshots, compression)
mkfs.btrfs /dev/sdb1

# vfat (USB, cross-platform)
mkfs.vfat /dev/sdb1

# swap
mkswap /dev/sdb1
mkswap --label swap0 /dev/sdb1
```

### UUID — Persistent Device Names

Disk device names (`/dev/sda1`) can change. **UUID is persistent**:

```bash
# Get UUID
blkid /dev/sdb1
# /dev/sdb1: UUID="abc123-..." TYPE="ext4"

# Or:
ls -la /dev/disk/by-uuid/
# lrwxrwxrwx 1 root root 10 ... abc123-... -> ../../sdb1

# Get PARTUUID (GPT partition UUID)
ls -la /dev/disk/by-partuuid/
```

## Mounting

```bash
# Temporary mount
mount /dev/sdb1 /mnt/data

# Mount with specific filesystem
mount -t ext4 /dev/sdb1 /mnt/data

# Mount read-only
mount -o ro /dev/sdb1 /mnt/data

# Mount with specific options
mount -o noexec,nosuid,nodev /dev/sdb1 /mnt/data

# Unmount
umount /mnt/data
umount /dev/sdb1 # can use device or mountpoint
```

## /etc/fstab — Persistent Mounts

```bash
# /etc/fstab format:
# <device>  <mountpoint>  <type>  <options>  <dump>  <fsck>
# UUID=abc123  /mnt/data  ext4  defaults0 2

# Get device UUID:
blkid /dev/sdb1

# /etc/fstab entry:
UUID=abc123-... /mnt/data  ext4  defaults,noatime  0 2
# ↑ dump flag (0=don't backup)
#                                                 ↑ fsck order (0=no check, 1=root, 2=others)
```

```bash
# Validate fstab before reboot:
mount -a              # mounts everything in fstab that isn't already mounted
# If this succeeds without error, fstab is valid

# Common mount options:
defaults # rw,suid,dev,exec,auto,nouser,async
noatime     # don't update access time (performance)
nodiratime  # don't update dir access time
nosuid      # ignore suid bit on files
noexec      # no executing binaries from this fs
nodev       # don't interpret device files
ro          # read-only
```

## lsblk and /etc/fstab Interaction

```bash
# lsblk shows mountpoints and filesystem info:
lsblk -f
# NAME   FSTYPE  LABEL  UUID         MOUNTPOINT
# sda
# ├─sda1 vfat            ABCD-1234   /boot/efi
# ├─sda2 ext4            def456 /
# └─sda3 xfs             ghi789      /home
```

## Checking Filesystem Health

```bash
# ext4/xfs: don't fsck while mounted (xfs doesn't even support it)
# For unmounted filesystem:
umount /dev/sdb1
fsck.ext4 /dev/sdb1
fsck.xfs /dev/sdb1        # xfs only repairs via mount (xfs_repair)

# SMART (disk health)
smartctl -a /dev/sda
smartctl -H /dev/sda      # overall health check
smartctl -t short /dev/sda # short self-test
```