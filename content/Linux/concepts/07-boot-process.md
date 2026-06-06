---
title: "07 — Boot Process"
description: Linux boot process — BIOS/UEFI, POST, bootloader, kernel, initramfs, systemd, login screen
tags:
  - linux
  - concepts
---

# 07 — Boot Process

When you press the power button, Linux goes through a precise sequence of stages to get from hardware to a running system. Here's what happens, step by step.

## The Six Stages

```
1. POST          → Hardware check, find boot device
2. Bootloader    → Load the kernel (GRUB)
3. Kernel        → Initialize hardware, start init
4. initramfs     → Mount the real root filesystem
5. systemd       → Start all services in parallel
6. Login         → Display manager or getty
```

## Stage 1 — POST and Firmware

When the computer powers on:
1. CPU initializes and runs the **BIOS/UEFI firmware**
2. **POST** (Power-On Self-Test) runs — checks RAM, CPU, hardware
3. Firmware looks for a boot device (SSD, HDD, USB, network)
4. Loads the first sector (MBR) or EFI partition — that's the **bootloader**

### BIOS vs UEFI

```
BIOS (Legacy):
  - Uses MBR (Master Boot Record) — first 512 bytes of disk
  - 2TB disk limit
  - No secure boot
  - Simple, widely compatible

UEFI (Modern):
  - Uses GPT (GUID Partition Table) — no 2TB limit
  - EFI System Partition (ESP) holds bootloader files
  - Supports Secure Boot (signed kernel/bootloader only)
  - Faster than BIOS
```

The ESP is a FAT32 partition at `/boot/efi/` on Linux:
```
/boot/efi/
  EFI/
    ubuntu/
      grubx64.efi    # GRUB bootloader for UEFI
    debian/
    fedora/
```

## Stage 2 — Bootloader (GRUB)

The bootloader lives in the MBR or ESP. Its job: let you choose which OS/kernel to boot, then load the kernel and initramfs into memory.

### GRUB Menu

When you boot, you see the GRUB menu:

```
Ubuntu
Advanced options for Ubuntu
Memory test (memtest86+)
UEFI Firmware Settings
```

### What GRUB Actually Does

1. Loads the **kernel image** (`/boot/vmlinuz-*`)
2. Loads the **initramfs** (`/boot/initrd.img-*` or `/boot/initramfs-*`)
3. Passes kernel command-line parameters (root=, quiet, splash, etc.)
4. Transfers control to the kernel

### GRUB Config

```bash
# Main config:
/boot/grub/grub.cfg       # generated — don't edit directly
/etc/default/grub          # edit this instead, then update-grub
/etc/grub.d/              # scripts that generate grub.cfg

# Edit defaults:
sudo nano /etc/default/grub
# GRUB_DEFAULT=0           # default menu entry (0 = first)
/etc/default/grub
# GRUB_TIMEOUT=5           # seconds before auto-boot
# GRUB_CMDLINE_LINUX=...   # kernel command line args

# After editing:
sudo update-grub    # Debian/Ubuntu
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Kernel Command Line

```bash
# See current kernel params:
cat /proc/cmdline
# BOOT_IMAGE=/boot/vmlinuz-5.15.0-generic root=UUID=abc123 ro quiet splash

# Common params:
root=UUID=abc123       # root filesystem location
ro                     # mount root read-only (switched to rw by init)
quiet                  # suppress boot messages
splash                 # show Plymouth splash screen
nomodeset              # don't use kernel mode setting (fallback graphics)
single                 # boot to single-user (root) mode
init=/bin/bash         # override init (emergency recovery)
console=tty1           # redirect console to tty1
```

## Stage 3 — Kernel

Once GRUB loads the kernel into memory, the kernel:
1. Initializes CPU, memory management
2. Detects and initializes hardware
3. Mounts the **initramfs** as the temporary root filesystem
4. Runs `/sbin/init` (or whatever the `init=` param specifies)

## Stage 4 — initramfs

The **Initial RAM Filesystem** (`initramfs`) is a temporary root filesystem that lives in RAM. It contains the minimum tools needed to find and mount the real root filesystem.

```
Why initramfs?
  - The real root filesystem might be on LVM, RAID, encrypted (LUKS), or NFS
  - The kernel can't handle all those without help
  - initramfs has the tools (lvm, mdadm, cryptsetup) to unlock and mount it
```

The initramfs unpacks itself, runs scripts to:
1. Set up LVM volumes
2. Decrypt LUKS-encrypted partitions
3. Mount the real root filesystem
4. Pivot into the real root filesystem
5. Run systemd as PID 1

## Stage 5 — systemd

Once the real root is mounted, systemd takes over as PID 1.

systemd's job: start everything else in the right order, in parallel where possible.

### What systemd starts

```
basic.target         → sets up /tmp, /run, sockets
sysinit.target      → system initialization (mounts, random seed, etc.)
local-fs.target     → mount local filesystems
swap.target         → activate swap
network.target      → bring up networking
network-online.target → wait for network to be fully up
multi-user.target   → CLI system (normal boot)
graphical.target    → GUI system (if installed)
```

### How systemd Decides What to Start

systemd reads unit files (`.service`, `.socket`, `.mount`) and their `Wants=` and `Requires=` dependencies to build a dependency graph. It then starts targets in topological order.

## Stage 6 — Login

```
Multi-user (CLI):  systemd starts getty on tty1-tty6 → login prompt
Graphical (GUI):   systemd starts display manager (GDM, LightDM, SDDM)
                   → GUI login screen → desktop environment
```

## Recovery Boot

If your system won't boot normally:

```bash
# From GRUB menu:
# 1. Select "Advanced options for Ubuntu"
# 2. Select "Ubuntu, with Linux 5.15.0-generic (recovery mode)"
# 3. Choose "root — Drop to root shell prompt"

# Common fixes from recovery:
# Remount filesystem as rw:
mount -o remount,rw /

# Check filesystem:
fsck /dev/sda1

# Check disk space:
df -h

# Check logs:
journalctl -xb

# Reset root password:
passwd root
```

## Boot Time Optimization

```bash
# See what's slow:
systemd-analyze time           # total boot time
systemd-analyze blame         # slowest services (most time consuming)
systemd-analyze critical-chain # services on the critical path

# Disable slow services:
systemctl disable cups         # printing (if not needed)
systemctl mask auditd          # audit subsystem (if not needed)

# Enable systemd-readahead (preload):
systemctl enable systemd-readahead-collect
systemctl enable systemd-readahead-replay
```

## Quick Reference

```bash
# Boot info
cat /proc/cmdline              # kernel command line
systemctl list-units --type=service   # running services

# Boot time analysis
systemd-analyze time
systemd-analyze blame
systemd-analyze critical-chain

# GRUB
cat /etc/default/grub          # edit here
sudo update-grub              # regenerate
# /boot/grub/grub.cfg          # actual config (don't edit)

# Recovery
# From GRUB: Advanced → Recovery mode
# Single user: add 'single' to kernel cmdline
# Reset root: from recovery root shell, run 'passwd root'

# Initramfs
ls /boot/                      # vmlinuz and initrd/initramfs
update-initramfs -u           # regenerate initramfs (after driver changes)
```