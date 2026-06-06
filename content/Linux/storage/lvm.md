---
title: LVM
description: Linux LVM — physical volumes, volume groups, logical volumes, thin provisioning, snapshots
tags:
  - linux
  - storage
---

# LVM

LVM (Logical Volume Manager) is a **virtualized block device layer** that sits between physical disks and filesystems. It lets you resize, snapshot, and stripe volumes without touching the underlying partitions, making storage management far more flexible than raw partitions.

## The Three Layers

```
┌─────────────────────────────────────────────────────┐
│ Logical Volumes (LV)                                │
│   /dev/vg_name/lv_name                             │
│   → ext4, xfs, swap, anything                     │
└────────────────────┬────────────────────────────────┘
                     │ (linear or striped mapping)
┌────────────────────▼────────────────────────────────┐
│ Volume Group (VG)                                   │
│   Combines PVs into one big pool of storage        │
│   Allocates space to LVs on demand                 │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│ Physical Volumes (PV)                               │
│   /dev/sda5, /dev/sdb1                            │
│   Partition or whole disk initialized for LVM       │
└─────────────────────────────────────────────────────┘
```

## Key Concept: Allocation is Flexible

```
Without LVM:
  /dev/sda1  → /       (100G, full)
  /dev/sda2  → /home   (200G, full)
  /home fills up → must move to new disk → complex

With LVM:
  /dev/vg0/home_lv    (200G, on /dev/sda2)
  /dev/vg0/root_lv    (100G, on /dev/sda1)
  /home fills up → lvextend + resize2fs → done in 2 commands
```

## Creating LVM

```bash
# 1. Create physical volume (PV)
pvcreate /dev/sdb1

# 2. Create volume group (VG)
vgcreate vg0 /dev/sdb1

# Or add to existing VG
vgextend vg0 /dev/sdc1

# 3. Create logical volume (LV)
lvcreate -n data_lv -L 100G vg0

# Or use all remaining space
lvcreate -n data_lv -l 100%FREE vg0

# 4. Create filesystem
mkfs.ext4 /dev/vg0/data_lv

# 5. Mount
mount /dev/vg0/data_lv /mnt/data
```

## Viewing LVM State

```bash
pvs                        # physical volumes
vgs                        # volume groups
lvs                        # logical volumes
lvs -a                     # including snapshots
pvdisplay /dev/sdb1        # detailed PV info
vgdisplay vg0              # detailed VG info
lvdisplay /dev/vg0/data_lv # detailed LV info
```

## Resizing LVs and Filesystems

### Extend (online, no unmount needed for ext4)

```bash
# Extend LV by 50G
lvextend -L +50G /dev/vg0/data_lv

# Or extend to fill all free space
lvextend -l +100%FREE /dev/vg0/data_lv

# Resize ext4 filesystem to fill new space
resize2fs /dev/vg0/data_lv

# One step (modern distros):
resize2fs -p /dev/vg0/data_lv   # extends to fill LV
```

### Reduce (must unmount)

```bash
umount /mnt/data

# 1. Filesystem first (shrink before LV)
e2fsck -f /dev/vg0/data_lv
resize2fs /dev/vg0/data_lv 80G

# 2. Then shrink LV
lvreduce -L 80G /dev/vg0/data_lv

# 3. Remount
mount /dev/vg0/data_lv /mnt/data
```

**Rule: extend first, shrink second. Always.**

## Striping (Performance)

Stripe across 3 disks (data interleaved across PVs):

```bash
# Create striped LV: 3-way stripe, 256KB stripe size
lvcreate -n striped_lv -L 300G -i 3 -I 256 vg0
#   -i 3  → 3 disks
#   -I 256 → 256KB stripe size
```

Each chunk (default 4MB) is written round-robin across the PVs. Good for databases, VMs.

## Mirroring (Redundancy)

```bash
# Create mirrored LV (2 copies)
lvcreate -n mirrored_lv -L 100G -m 1 vg0
#   -m 1 → 1 mirror copy (2 copies total)
```

LVM mirror is a software RAID 1 equivalent. Less used now since MD-RAID is more mature.

## Thin Provisioning

Thin provisioning lets you **over-commit** storage — create LVs totaling more space than you physically have, betting that not all will be full at once:

```bash
# 1. Create thin pool
lvcreate -L 500G --thinpool thin_pool vg0

# 2. Create thin volumes (virtual volumes)
lvcreate -V 1T --thin -n thin_vol1 vg0/thin_pool   # 1TB virtual, 0G physical used
lvcreate -V 1T --thin -n thin_vol2 vg0/thin_pool   # 2TB virtual total, 500G physical

# Space consumed as data is written, not when LV is created
```

Useful for:
- VM hosts (many VMs, not all fully allocated)
- Container storage (many containers, sparse usage)

**Warning:** If the thin pool fills up, all thin volumes in it become unusable. Monitor `lvs -a` for `data%`.

## Snapshots

LVM snapshots are **copy-on-write** snapshots — the snapshot LV initially references the original data, then records changes as they happen:

```bash
# Create snapshot of data_lv
lvcreate -n data_snap -L 10G -s /dev/vg0/data_lv
#   -s  → snapshot
#   -L  → snapshot size (must be enough to record changes)

# Mount and inspect
mount /dev/vg0/data_snap /mnt/snap
# Compare /mnt/snap with /mnt/data

# When done: merge snapshot back
umount /mnt/snap
lvremove /dev/vg0/data_snap

# Or: merge snapshot to restore original
# (must unmount original first)
umount /mnt/data
lvconvert --merge /dev/vg0/data_snap
# After reboot/umount: data_lv is reverted to snapshot state
mount /dev/vg0/data_lv /mnt/data
```

Snapshot size determines how many changes can be recorded. If the snapshot fills up, it breaks (becomes invalid).

## LVM and /etc/fstab

```bash
# Can use /dev/vg0/lv_name (not stable across reboots on some distros)
# Better: use UUID
blkid /dev/vg0/data_lv
# /dev/vg0/data_lv: UUID="abc123" TYPE="ext4"

# /etc/fstab:
UUID=abc123  /mnt/data  ext4  defaults  0 2
```

## Removing LVM

```bash
# 1. Unmount
umount /mnt/data

# 2. Remove LV
lvremove /dev/vg0/data_lv

# 3. Remove VG (frees PVs)
vgremove vg0

# 4. Remove PV signatures
pvremove /dev/sdb1
```

## Complete Example: Setup from Raw Disks

```bash
# Raw disk /dev/sdb → LVM → ext4 filesystem
# 1. Partition (optional — can use whole disk)
parted /dev/sdb mklabel gpt
parted /dev/sdb mkpart primary lvm 0% 100%

# 2. PV
pvcreate /dev/sdb1

# 3. VG
vgcreate myvg /dev/sdb1

# 4. LV
lvcreate -n mylv -L 50G myvg
mkfs.ext4 /dev/myvg/mylv

# 5. Mount
echo "/dev/myvg/mylv /mnt/mylv ext4 defaults 0 2" >> /etc/fstab
mount -a
```

## Common Mistakes

- **Extending LV but not filesystem**: `lvextend` alone doesn't resize filesystem. Always follow with `resize2fs`.
- **Reducing LV without reducing filesystem first**: Data loss/corruption.
- **Thin pool fills up**: All thin volumes become read-only until pool expanded.
- **Snapshot fills up**: Snapshot becomes invalid (marked as "snapshot-invalid").