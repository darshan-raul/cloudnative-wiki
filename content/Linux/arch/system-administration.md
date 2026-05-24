---
title: Arch Linux System Administration
---

# 4. System Administration

## systemd Deep Dive

systemd is Arch's init system and service manager. Virtually all Arch-based distros use it.

### Core Commands

```bash
# Start/stop/restart services
systemctl start <service>
systemctl stop <service>
systemctl restart <service>

# Enable/disable at boot
systemctl enable <service>
systemctl disable <service>

# Check status
systemctl status <service>

# List running services
systemctl list-units --type=service
systemctl list-units --state=running

# View dependency tree
systemctl list-dependencies <service>

# Show failed units
systemctl --failed
```

### Unit Files

Located in `/usr/lib/systemd/system/` (packages) and `/etc/systemd/system/` (local overrides).

**Service unit example** (`/etc/systemd/system/myservice.service`):
```ini
[Unit]
Description=My Application
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/myapp --foreground
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
User=myapp

[Install]
WantedBy=multi-user.target
```

**Timer unit** (cron replacement):
```ini
[Unit]
Description=Daily backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

### Targets (Runlevels)

| Target | Purpose |
|--------|---------|
| `poweroff.target` | System halt |
| `rescue.target` | Single user mode |
| `multi-user.target` | CLI multi-user |
| `graphical.target` | GUI multi-user |
| `reboot.target` | Reboot |

```bash
# Change default target
systemctl set-default multi-user.target

# Switch target temporarily
systemctl isolate multi-user.target
```

### Managing Boot Process

```bash
# View boot time
systemd-analyze
systemd-analyze blame     # By time consumed

# View service logs
journalctl -u <service>
journalctl -f             # Follow logs
journalctl --since "1 hour ago"

# Clean old journal entries
journalctl --vacuum-time=2weeks
journalctl --vacuum-size=500M
```

## Boot Process

Arch's boot sequence:

1. **UEFI/BIOS** → loads Boot Loader
2. **Boot Loader** (systemd-boot/GRUB) → loads kernel + initramfs
3. **initramfs** (early userspace) → detects hardware, opens LUKS, mounts root
4. **systemd** → starts all units per target

### initramfs (mkinitcpio)

Regenerated after kernel upgrades or config changes.

```bash
# Generate new initramfs
mkinitcpio -P

# Config: /etc/mkinitcpio.conf
# HOOKS order matters:
HOOKS=(base udev autodetect keyboard keymap encrypt lvm2 resume filesystems)

# Common hooks:
# base       — minimum tools
# udev       — device enumeration
# autodetect — skip unnecessary modules
# keyboard   — keyboard support
# encrypt    — LUKS support
# lvm2       — LVM support
# resume     — Hibernation support
# filesystems — fsck, mounting
```

### Kernel Arguments

```bash
# View current
cat /proc/cmdline

# Add to GRUB: /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash mitigations=off"

# Add to systemd-boot: /boot/loader/entries/arch.conf
options root=UUID=<uuid> rw mitigations=off

# Apply GRUB changes
grub-mkconfig -o /boot/grub/grub.cfg
```

## Kernel Management

### Installing Kernels

```bash
# Official kernels
pacman -S linux           # Current (default)
pacman -S linux-lts       # Long-term support
pacman -S linux-zen        # Optimized (zen scheduler)

# Install extra kernel
pacman -S linux61         # Kernel 6.1.x

# Manjaro-specific
mhwd-kernel -i linux61    # Manjaro's kernel manager

# Remove kernel
pacman -R linux
```

### Updating Kernel

```bash
# Upgrade includes kernel
pacman -Syu

# Manually regenerate initramfs after kernel change
mkinitcpio -P
```

### Kernel Modules

```bash
# List loaded modules
lsmod

# Load module manually
modprobe <module>

# Block module from loading (e.g., nouveau)
# /etc/modprobe.d/blacklist.conf
blacklist nouveau

# Module parameters
# /etc/modprobe.d/params.conf
options <module> param=value
```

## System Maintenance

### Regular Maintenance Tasks

```bash
# Full system upgrade
pacman -Syu

# After upgrade (check for .pacnew files)
pacdiff

# Clean package cache
paccache -r              # Keep last 1 version
# Or in /etc/pacman.conf:
CleanMethod = KeepCurrent

# Remove orphans
pacman -Rns $(pacman -Qdtq)

# Check for filesystem errors
fsck /dev/sda1

# Repair filesystem
fsck -fy /dev/sda1       # Force repair
```

### pacman Config

```bash
# /etc/pacman.conf

[options]
# Parallel downloads
ParallelDownloads = 5

# Color output
Color

# Verbose package lists
VerbosePackageLists

# Clean cache on upgrade
CleanMethod = KeepCurrent

# Hold packages (don't upgrade)
HoldPkg = pacman glibc

# Ignore group changes
IgnoreGroup = base

# Skip file from upgrade
NoUpgrade = etc/pacman.conf
```

## mkinitcpio (Initramfs Generation)

Key hooks:

| Hook | Purpose |
|------|---------|
| `base` | Core utilities |
| `udev` | Dynamic device loading |
| `autodetect` | Skip unused modules |
| `keyboard` | Keyboard support (for LUKS at boot) |
| `keymap` | Load keymap |
| `encrypt` | LUKS decryption |
| `lvm2` | LVM activation |
| `resume` | Hibernation resume |
| `filesystems` | Root mount |
| `fsck` | Filesystem check |

```bash
# Generate with custom preset
mkinitcpio -P

# Kernel-specific
mkinitcpio -k /boot/vmlinuz-linux -P

# Show what changed
mkinitcpio -L
```

## Systemd-journald (Logging)

```bash
# View logs
journalctl -b              # Current boot
journalctl -e              # End (latest)
journalctl -f              # Follow
journalctl -u <service>    # Specific service
journalctl --since "2024-01-01" --until "2024-01-02"

# Priority levels
journalctl -p err          # Errors and worse

# Disk usage
journalctl --disk-usage
journalctl --vacuum-time=2weeks
journalctl --vacuum-bytes=500M

# Persistent logs across boots
# /etc/systemd/journald.conf
[Journal]
Storage=persistent
```

## Package Hooks (Automatic Actions)

Triggered on package install/upgrade/remove.

```bash
# /etc/pacman.d/hooks/update-grub.hook
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = grub

[Action]
Description = Regenerating GRUB config...
When = PostTransaction
Exec = /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg

# Another example: update initramfs on kernel install
[Trigger]
Type = Package
Operation = Install
Target = linux

[Action]
Description = Regenerating initramfs...
When = PostTransaction
Exec = /usr/bin/mkinitcpio -P
```

## Systemd Slice & Resource Control

```bash
# Create slice for a service
# /etc/systemd/system/myapp.slice
[Slice]
CPUWeight=50
MemoryMax=512M

# In service unit:
[Service]
Slice=myapp.slice
```

## cron-equivalent: systemd Timers

```bash
# Daily timer example
[Unit]
Description=Daily cleanup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target

# Timer paired with service
systemctl enable --now mytimer.timer
systemctl list-timers
```