---
title: Device Files
description: Linux device files — /dev/, mknod, character vs block devices, udev, device nodes
tags:
  - linux
  - filesystem
---

# Device Files

Device files are special files in `/dev/` that represent hardware devices or kernel resources. They look like regular files but provide an interface to the kernel's device drivers.

## Character vs Block Devices

```
Character device (c):  read/write byte-by-byte (no buffering)
  Examples: /dev/null, /dev/zero, /dev/tty, /dev/urandom, /dev/console

Block device (b):      read/write in fixed-size blocks (buffered, cached)
  Examples: /dev/sda, /dev/nvme0n1, /dev/ram0
```

```bash
ls -la /dev/
# crw-rw-rw- 1 root video 226,   0 Jun  6 /dev/dri/card0   (c = char)
# brw-rw---- 1 root disk   8,    0 Jun  6 /dev/sda           (b = block)
```

Major and minor numbers:
- **Major number**: identifies the driver (e.g., 8 = SCSI disk driver)
- **Minor number**: which device instance (e.g., sda=0, sda1=1)

## /dev/null and /dev/zero

```bash
# /dev/null — discard all data written to it, returns EOF on read
echo "hello" > /dev/null     # data discarded
cat /dev/null               # returns nothing (EOF)

# Common uses:
command > /dev/null 2>&1   # discard all output
dd if=/dev/zero of=/dev/null bs=1M count=1  # measure CPU speed

# /dev/zero — returns infinite null bytes
# Useful for:
dd if=/dev/zero of=swapfile bs=1M count=1024   # create empty file
dd if=/dev/zero of=/dev/null bs=1M count=100   # burn CPU
```

## /dev/urandom and /dev/random

```bash
# /dev/urandom — non-blocking, returns pseudo-random bytes (good for crypto)
# Always returns data immediately
head -c 32 /dev/urandom | base64

# /dev/random — blocking, waits for entropy
# Blocks when entropy pool is low (security paranoid uses)
head -c 32 /dev/random | base64

# /dev/random quality:
# /dev/urandom: TLS keys, session tokens, nonces
# /dev/random: GPG keys, SSH keys (where blocking is acceptable)
```

## /dev/tty and /dev/console

```bash
# /dev/tty — controlling terminal of the current process
# Useful for programs that need terminal interaction:
echo "Password:" > /dev/tty
read -s password < /dev/tty

# /dev/console — system console (physical keyboard + display)
# All kernel messages go here
# On headless servers: /dev/console → /dev/ttyS0 (serial)
```

## udev — Dynamic Device Management

`udev` dynamically creates device files in `/dev/` when devices are detected, using rules in `/etc/udev/rules.d/`:

```bash
# See device events in real-time:
udevadm monitor

# Trigger a re-scan:
udevadm settle

# Query device info:
udevadm info --query=property --name=/dev/sda
udevadm info --query=all --path=/sys/block/sda

# Manually trigger a rule reload:
udevadm control --reload-rules
```

### udev Rules

```bash
# /etc/udev/rules.d/99-mydevice.rules
# KERNEL: match device name pattern
# SUBSYSTEM: match device subsystem
# ACTION: add, remove, change
# NAME: set device name
# SYMLINK: create a symlink
# RUN: execute a program

# Example: create symlink for specific USB device
SUBSYSTEM=="usb", ATTR{idVendor}=="1234", ATTR{idProduct}=="5678", \
    SYMLINK+="mydevice%n", MODE="0666"

# Example: set permissions for /dev/ttyUSB0
SUBSYSTEM=="usb-serial", KERNEL=="ttyUSB0", \
    MODE="0666", OWNER="dialout"
```

## mknod — Creating Device Files Manually

```bash
# mknod creates a device node
# Syntax: mknod NAME TYPE MAJOR MINOR

# Create a character device
sudo mknod /dev/mycdrv c 245 0

# Create a block device
sudo mknod /dev/myblk b 8 0

# Change permissions
sudo chmod 666 /dev/mycdrv

# Remove
sudo rm /dev/mycdrv
```

Normally you don't need `mknod` — udev creates device files automatically. You'd only use it for:
- Driver development
- Container environments where /dev is mounted from host
- Recovery situations

## /dev/null in Containers

Containers use `/dev/null` from the host's /dev (or a simulated one):

```bash
# In container:
ls -la /dev/null
# crw-rw-rw- 1 root root 1, 3 Jun  6 /dev/null

# Test:
echo "hello" > /dev/null   # works
cat /dev/zero | head -c 16  # works
```

## Major/Minor Number Reference

```bash
# Known major numbers:
# 1 = /dev/mem (memory), /dev/null, /dev/zero, /dev/urandom
# 4 = /dev/tty, /dev/tty0, /dev/console
# 5 = /dev/tty
# 7 = /dev/null (loopback)
# 8 = SCSI disk (sda, sdb, ...)
# 9 = Software RAID (md0)
# 11 = /dev/sr0 (CD-ROM)
# 189 = USB character devices
# 226 = DRM/gpu devices (dri/card0)
# 245-246 = I2C devices
```

## Loop Devices

```bash
# Loop devices: map a file to a block device
# Used for: mounting disk images, encrypted containers

# Attach file to loop device
sudo losetup -f                        # find free loop device
sudo losetup /dev/loop0 disk.img      # attach
mount /dev/loop0 /mnt

# Detach
sudo losetup -d /dev/loop0

# Or auto-detach on umount:
mount -o loop disk.img /mnt
# The loop device auto-cleanup happens on umount
```