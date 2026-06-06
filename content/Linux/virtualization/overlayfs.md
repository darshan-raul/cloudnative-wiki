---
title: OverlayFS
description: Linux OverlayFS — upperdir, lowerdir, workdir, copy-on-write, layer merging, container images
tags:
  - linux
  - filesystem
  - containers
---

# OverlayFS

OverlayFS is a **union filesystem** that merges multiple read-only directories into a single merged view, with a writable top layer. It's the standard filesystem for container images — each image layer becomes a `lowerdir`, and the container's changes accumulate in the `upperdir`.

## The Three-Layer Model

```
         ┌─────────────────────────────┐
         │     /merged (view you see) │
         │  ↑ read from upper on conflict   │
         └─────────────────────────────┘
                    ▲
         ┌──────────┴──────────┐
         │                     │
    upperdir (rw)         lowerdirs (ro)
    /var/lib/docker/      /var/lib/docker/
    overlay2/xxx/diff     overlay2/l/yyy
    (container changes)   (image layers)
```

- **lowerdir**: read-only image layers. Multiple can be stacked (colon-separated, first on top).
- **upperdir**: read-write layer for the container. All writes go here.
- **workdir**: empty directory needed by the kernel for atomic `rename()` during copy-up.
- **merged**: the combined view that processes see.

## Mounting OverlayFS Manually

```bash
# Create the directories
mkdir -p /overlay/lower1 /overlay/lower2 /overlay/upper /overlay/work /overlay/merged

# Create some content in lower layers
echo "from lower1" > /overlay/lower1/file1.txt
echo "from lower2" > /overlay/lower2/file2.txt

# Mount
mount -t overlay overlay \
  -o lowerdir=/overlay/lower2:/overlay/lower1,\
      upperdir=/overlay/upper,\
      workdir=/overlay/work \
  /overlay/merged

# See the merged view
ls /overlay/merged
# file1.txt  file2.txt

# Write something
echo "from container" > /overlay/merged/newfile.txt

# Check: upperdir has the new file
ls /overlay/upper/
# newfile.txt  (upperdir is where writes land)
```

## Copy-on-Write in Action

```bash
# Lower layer has a 1GB file
ls -la /overlay/lower1/bigfile.bin
# -rw-r--r-- 1 root root 1073741824 Jan  1 12:00 bigfile.bin

# Container reads it (no copy — still reads from lowerdir)
cat /overlay/lower1/bigfile.bin | head -1

# Container modifies it
echo "change" >> /overlay/merged/bigfile.bin

# Now upperdir has the modified file
ls -la /overlay/upper/bigfile.bin
# -rw-r--r-- 1 root root 1073741831 Jun  6 12:00 bigfile.bin

# Lower layer file is UNCHANGED (CoW = copy on write)
ls -la /overlay/lower1/bigfile.bin
# -rw-r--r-- 1 root root 1073741824 Jan  1 12:00 bigfile.bin  (original, unchanged)
```

This is why multiple containers sharing the same image layer don't interfere with each other — the lower layer is never written to.

## The Whiteout File

When a container **deletes** a file from a lower layer, overlay doesn't actually delete anything. It creates a **whiteout file** in the upperdir:

```bash
# Container deletes /bin/bash (from lower1)
rm /overlay/merged/bin/bash

# Upperdir now has:
ls /overlay/upper/
# .wh.bin/bash        ← whiteout file (the .wh. prefix = "hide this")

# In the merged view, bash is invisible
ls /overlay/merged/bin/  # no bash
```

The whiteout tells the kernel: "this file was deleted in this layer." Without it, the lower layer file would still appear.

## Layer Ordering (lowerdir precedence)

lowerdirs are colon-separated. **First listed = highest priority** for reads:

```bash
mount -t overlay overlay \
  -o lowerdir=/layer3:/layer2:/layer1   # layer3 on top, layer1 at bottom
```

When reading: if a file exists in layer3 AND layer1, the layer3 version wins. When writing: always goes to `upperdir` (never to lowerdirs).

## Docker's Use of OverlayFS

Docker uses overlay2 storage driver by default on modern Linux:

```bash
# Docker's overlay2 structure (simplified):
/var/lib/docker/overlay2/
  l/                     ← symlinks to layer directories (short link names)
  <image-hash>/          ← lowerdir content (image layer)
    link                 ← symlink to actual layer dir
  <container-hash>/       ← upperdir content (container layer)
    diff/                ← files created/modified in this container
    lower-data           ← list of lower layer IDs
    merged/              ← the merged container filesystem
    work/                ← workdir for atomic operations
```

The `diff/` directory is the `upperdir`. The `merged/` is what the container sees as its filesystem root `/`.

## OverlayFS and Hardlinks

Be careful with hardlinks across overlay layers:

```bash
# Lower has a hardlink
ln /overlay/lower1/existing /overlay/lower1/hardlink_pair

# In merged view, they're the same file
ls -li /overlay/merged/
# 12345 -rw-r--r-- 2 ... existing
# 12345 -rw-r--r-- 2 ... hardlink_pair

# If container modifies one via the hardlink path:
echo "changed" >> /overlay/merged/hardlink_pair

# Now upperdir has the modified file (copy-up happens)
# The original in lowerdir is unchanged
# But hardlink relationship is BROKEN in upperdir
# (upperdir has a NEW inode)
```

## Performance Characteristics

| Operation      | Performance | Notes                                       |
|---------------|-------------|---------------------------------------------|
| Read (cache hit) | Fast     | Kernel page cache serves from RAM          |
| Read (first time) | Moderate | Must traverse upper → lower                 |
| Write (new file)  | Fast     | Direct write to upperdir                   |
| Write (copy-up)   | Slow     | Must copy entire file from lower to upper  |
| Delete            | Fast     | Just creates whiteout, no data move       |
| Many small writes | Slower   | Each copy-up copies a whole file          |

## Checking Overlay Mounts

```bash
# See all overlay mounts
findmnt -t overlay

# See details for a specific mount
cat /proc/mounts | grep overlay

# With overlay2 driver (Docker):
docker inspect <container> --format '{{json .GraphDriver.Data}}' | jq
# {"LowerDir": "...", "UpperDir": "...", "WorkDir": "..."}
```

## When Overlay Is the Wrong Choice

- **Large files that get partially modified** (databases): partial overwrite copies the whole file → lots of I/O
- **Overlay only works on the same filesystem** (can't cross device boundaries for upper/lower)
- **NFS or CIFS backing**: overlay over network filesystems has limitations (requires same underlying fs features)