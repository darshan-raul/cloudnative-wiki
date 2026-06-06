---
title: Boot Process
description: Linux boot process — UEFI/BIOS, bootloader (GRUB), kernel, initramfs, systemd, runlevels, target units
tags:
  - linux
---

# Boot Process

The Linux boot process is a staged pipeline from hardware power-on to a running userspace. Each stage loads and transfers control to the next. Understanding it helps debug boot failures, understand init systems, and appreciate what happens before systemd takes over.

## The Full Pipeline

```
Power On → BIOS/UEFI → Bootloader (GRUB) → Kernel → Initramfs → /sbin/init (systemd) → Services
```

## Stage 1: BIOS/UEFI

When the system powers on, the CPU jumps to the firmware (BIOS or UEFI) which:

1. Runs Power-On Self Test (POST)
2. Initializes hardware
3. Reads the boot order from CMOS/NVRAM
4. Loads the first sector of the configured boot device (MBR or EFI partition)

**BIOS** (legacy): Reads 512-byte MBR → finds and runs bootloader.

**UEFI** (modern): Reads GPT partition table → finds EFI System Partition (ESP) → loads `.efi` bootloader from `/EFI/boot/bootx64.efi` or a configured path.

```
UEFI boot order:
  /EFI/systemd/systemd-bootx64.efi
  /EFI/ubuntu/grubx64.efi
  /EFI/Microsoft/Boot/bootmgfw.efi
```

## Stage 2: Bootloader

The bootloader (almost always GRUB2) does two jobs:
1. **Select a kernel** from disk
2. **Pass kernel parameters** and load the kernel + initramfs into memory

### GRUB2

```bash
# GRUB2 config lives at:
/boot/grub/grub.cfg          # auto-generated — don't edit directly
/etc/default/grub            # edit this, then update-grub
/etc/grub.d/                 # snippets that update-grub assembles

# GRUB2 menu entries look like:
menuentry 'Ubuntu' {
    load_video
    insmod gzio
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root abc123
    linux   /boot/vmlinuz-5.15.0 root=UUID=abc123 ro quiet splash
    initrd  /boot/initrd.img-5.15.0
}
```

### Kernel Parameters

```bash
# Common kernel parameters:
root=UUID=abc123          # root filesystem device
ro                        # mount root read-only initially
quiet                     # suppress kernel boot messages
splash                    # show splash screen
single                    # boot to single-user mode
emergency                 # boot to emergency shell
systemd.unit=multi-user.target   # override default target
net.ifnames=0             # disable predictable network interface names
```

### Initramfs

The **initial RAM filesystem** (`initramfs`) is a temporary root filesystem loaded into RAM by the bootloader. It contains:
- Busybox (minimal /bin/sh, /bin/cat, /bin/mount, etc.)
- Kernel modules needed to access the real root filesystem (SCSI, RAID, LVM, ext4, xfs, etc.)
- `init` script that mounts the real root and pivots into it

```bash
# View contents of initramfs (it's a cpio archive)
zcat /boot/initrd.img-$(uname -r) | cpio -id

# The initramfs init script handles:
# 1. Device detection (loading kernel modules)
# 2. Logical Volume Management (lvm2)
# 3. RAID assembly (mdadm)
# 4. Encryption (LUKS)
# 5. Mounting the real root filesystem
# 6. pivot_root to the real root
# 7. exec /sbin/init (systemd)
```

## Stage 3: Kernel

The kernel loads into memory and decompresses itself:

```
1. Decompress kernel image (arch/x86/boot/compressed/)
2. Early setup (IDT, GDT, paging)
3. Detect hardware (PCI, memory)
4. Load drivers (from initramfs if needed)
5. Mount root filesystem (from kernel cmdline)
6. Free initramfs memory
7. Start /sbin/init
```

The kernel's `init=` parameter overrides the default `/sbin/init`.

## Stage 4: /sbin/init

### Traditional SysVinit

The oldest init system. Uses shell scripts and runlevels:

```
/sbin/init
  → reads /etc/inittab
  → determines default runlevel (usually 2, 3, or 5)
  → runs /etc/rc.d/rc $RUNLEVEL
    → runs /etc/rc.d/rcS.d/      (startup scripts)
    → runs /etc/rc.d/rc$LEVEL.d/  (runlevel-specific: K* = kill, S* = start)
  → runs /etc/rc.d/rc.local
  → starts getty on ttys
```

Runlevels:
- 0: Halt
- 1/s/S: Single-user mode (no network, root only)
- 2-5: Multi-user (2 = no network, 3 = full, 5 = GUI)
- 6: Reboot

### systemd (Modern)

systemd is now universal on desktop/server Linux. It replaces shell scripts with **unit files**:

```bash
# systemd's first process is PID 1 (the systemd binary itself)
systemd --system   # PID 1 in system context
```

systemd's job is to **manage services, dependencies, and system state**:

```
systemd
  → reads /etc/systemd/system/default.target   (or kernel param)
  → starts basic.target (local-fs, swap, etc.)
  → starts sysinit.target (all units marked Requires= or After=)
  → starts graphical.target (or multi-user.target)
  → starts getty@tty1.service
```

Units are in:
```
/etc/systemd/system/     # system administrator units
/run/systemd/system/    # runtime units
/lib/systemd/system/    # vendor units (Ubuntu, Fedora, etc.)
```

### systemd Targets (equivalent to runlevels)

| Target         | Equivalent | Purpose                          |
|---------------|-----------|----------------------------------|
| emergency.target | init 1  | Emergency shell                  |
| rescue.target    | init s  | Single-user with basic services |
| multi-user.target| init 3  | Multi-user, no GUI              |
| graphical.target | init 5  | Multi-user with GUI            |
| default.target   |         | What systemd boots to by default |

```bash
# Change default target
systemctl set-default multi-user.target

# Boot to a specific target once
systemd.unit=multi-user.target

# Switch target at runtime
systemctl isolate multi-user.target
```

## Stage 5: Services

After basic.target (or equivalent), systemd starts services:

```bash
# Boot takes this sequence (simplified):
basic.target
  ↓
sysinit.target   (mounts, swap, kernel modules, sysctl)
  ↓
sockets.target   (D-Bus, systemd sockets)
  ↓
timers.target    (cron, atd)
  ↓
basic.target     (hostname, locale, etc.)
  ↓
multi-user.target
  ↓
graphical.target (if multi-user succeeded and default is graphical)
```

Each unit has dependencies (`Wants=`, `Requires=`, `After=`, `Before=`).

## Debugging Boot Problems

```bash
# Boot to emergency shell (add to kernel params):
emergency

# Boot to single-user (add to kernel params):
single

# See what systemd started:
systemctl list-units --type=service --state=failed
systemctl status nginx

# Boot journal:
journalctl -xb          # current boot
journalctl -b -1        # previous boot
journalctl -f           # follow live

# GRUB edit at boot:
# At GRUB menu: press 'e' → edit kernel line → add 'systemd.unit=emergency.target'
```

## Systemd Units Quick Reference

```bash
# Common unit types:
# .service  — a running daemon/process
# .socket   — an IPC socket (activates .service on connection)
# .target   — a group of units (like a runlevel)
# .timer    — cron-like scheduled activation
# .mount    — a filesystem mount
# .path     — monitor a file/directory (activates .service on change)

systemctl start nginx
systemctl stop nginx
systemctl restart nginx
systemctl reload nginx
systemctl status nginx
systemctl enable nginx       # start at boot
systemctl disable nginx      # don't start at boot
systemctl is-enabled nginx
systemctl daemon-reload      # reload unit files
systemctl list-dependencies multi-user.target
```