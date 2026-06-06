---
title: Filesystems
description: Linux filesystems — ext4, xfs, btrfs, vfat, swap, mount options, UUID, journaling, copy-on-write
tags:
  - linux
  - storage
---

# Filesystems

A filesystem is how the kernel organizes data on a storage device. It defines the on-disk structure — inodes, directory entries, free space management, and metadata. Linux supports dozens of filesystems; the most common are ext4, xfs, and btrfs.

## ext4 — The Workhorse

ext4 (Fourth Extended Filesystem) is the default on most Linux distributions. It's a journaling filesystem with good performance, large filesystem support, and mature tooling.

```bash
# Create ext4 filesystem
mkfs.ext4 /dev/sdb1
mkfs.ext4 -L mydata /dev/sdb1          # with label
mkfs.ext4 -E lazy_itable_init=1 /dev/sdb1  # fast init (no zeroing)

# Tune ext4 at creation:
mkfs.ext4 -O has_journal,extent,dir_index,flex_bg /dev/sdb1

# Mount
mount -t ext4 /dev/sdb1 /mnt/data

# Key ext4 mount options:
mount -o noatime,nodiratime,errors=remount-ro /dev/sdb1 /mnt/data
# noatime: don't update atime on read (performance)
# nodiratime: don't update atime for directories
# errors=remount-ro: remount read-only on errors
```

### ext4 Features

- **Journaling**: writes metadata changes to a journal first, replays on crash recovery
- **Extent mapping**: contiguous block allocation (vs block-mapped in ext2/3)
- **Delayed allocation**: writes buffered in memory before allocation (better clustering)
- **Online defragmentation**: `e4defrag /mount/point`
- **Resize online**: can grow filesystem while mounted
- **inode size**: configurable (default 256 bytes, can be 512 for extended attributes)

```bash
# Check filesystem
fsck.ext4 /dev/sdb1          # check (unmount first!)
dumpe2fs -h /dev/sdb1        # show superblock info

# Show inode usage
df -i /mnt/data

# Get inode count
tune2fs -l /dev/sdb1 | grep -i inode
```

## xfs — Scalable and Fast

xfs is the default on RHEL/CentOS/Fedora. It's optimized for large files and large filesystems (multi-TB), and performs well with concurrent I/O.

```bash
# Create xfs
mkfs.xfs /dev/sdb1
mkfs.xfs -L mydata /dev/sdb1
mkfs.xfs -f /dev/sdb1     # force (if existing filesystem)

# Mount
mount -t xfs /dev/sdb1 /mnt/data

# Key mount options:
mount -o noatime,nodiratime,logbufs=8,logdev=/dev/sdc1 /dev/sdb1 /mnt/data
# logdev: put journal on separate fast device (SSD)
```

### xfs Features

- **Journaled**: external journal device option
- **Grow online**: `xfs_growfs /mount/point`
- **Quota**: project-based and user-based quotas
- **Defragmentation**: `xfs_fsr` (online)
- **Free space management**: UUIDs, labels, access time tracking

```bash
# Check xfs
xfs_check /dev/sdb1
xfs_info /mnt/data         # show xfs filesystem info
xfs_growfs /mnt/data        # grow (needs free space in LVM or partition)

# Repair (must unmount)
xfs_repair /dev/sdb1
```

## btrfs — Copy-on-Write, Snapshots

btrfs is a modern CoW (copy-on-write) filesystem with built-in snapshots, compression, checksumming, and multi-device support. Good for containers and VMs.

```bash
# Create btrfs
mkfs.btrfs /dev/sdb1
mkfs.btrfs -L mydata /dev/sdb1

# Mount
mount -t btrfs /dev/sdb1 /mnt/data

# Compressed
mount -t btrfs -o compress=zstd /dev/sdb1 /mnt/data
```

### btrfs Key Features

- **Copy-on-Write (CoW)**: modified pages written to new blocks, original unchanged
- **Snapshots**: read-only snapshot of a subvolume at a point in time
- **Subvolumes**: independently mountable filesystem within a filesystem
- **Checksumming**: data integrity (CRC32c)
- **Compression**: zstd, zlib, lzo
- **RAID**: software RAID 0/1/10 (not RAID5/6 — unstable)
- **Send/Receive**: stream snapshots for replication

```bash
# Create subvolume
btrfs subvolume create /mnt/data/vol1

# Create snapshot
btrfs subvolume snapshot /mnt/data /mnt/data/snap1

# Show subvolumes
btrfs subvolume list /mnt/data

# Compressed mount
mount -o compress=zstd:3 /dev/sdb1 /mnt/data

# Usage
btrfs filesystem df /mnt/data
btrfs filesystem usage /mnt/data

# Balance (re-distribute data across devices)
btrfs balance start -dusage=0 /mnt/data

# Convert ext4 → btrfs (in-place, requires free space):
btrfs-convert /dev/sdb1
```

## swap — Virtual Memory

```bash
# Create swap
mkswap /dev/sdb1
mkswap -L swap0 /dev/sdb1

# Enable
swapon /dev/sdb1
swapon -s                      # show active swaps

# Disable
swapoff /dev/sdb1

# Priority (higher = preferred)
swapon -p 100 /dev/sdb1

# In /etc/fstab:
# UUID=abc123 none swap sw,pri=100 0 0
```

## vfat — FAT32 (USB, EFI)

```bash
mkfs.vfat /dev/sdb1
# or
mkfs.fat /dev/sdb1

mount -t vfat /dev/sdb1 /mnt/usb
```

## Mount Options Reference

```bash
# Generic mount options (most filesystems):
defaults     # rw,suid,dev,exec,auto,nouser,async
ro           # read-only
rw           # read-write
noatime      # don't update access time (best for performance)
nodiratime   # don't update directory atimes
nosuid       # ignore suid bit
noexec       # no execution of binaries
nodev        # don't interpret device files
sync         # all writes synchronous (vs async)
async        # writes buffered (default)
suid         # honor suid bit (default)
user        # allow unprivileged user to mount
users       # allow any user to mount
auto         # mount at boot (via /etc/fstab)
noauto      # don't mount at boot
```

## Comparing Filesystems

| Feature       | ext4     | xfs      | btrfs        |
|--------------|----------|----------|--------------|
| Journal      | Yes      | Yes      | Yes (CoW)    |
| Max size     | 1EB      | 8EB      | 16EB         |
| Max file     | 16TB     | 8EB      | 16EB         |
| Copy-on-Write| No       | No       | Yes          |
| Snapshots    | No (via LVM)| No   | Yes          |
| Compression  | No       | No       | Yes          |
| Checksumming | No       | No       | Yes          |
| Online grow  | Yes      | Yes      | Yes          |
| Online shrink| No       | No       | Yes          |
| Default on   | Ubuntu   | RHEL     | OpenSUSE     |