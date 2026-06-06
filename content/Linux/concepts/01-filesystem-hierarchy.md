---
title: "01 — Filesystem Hierarchy"
description: Linux filesystem hierarchy — what /, /home, /var, /etc, /tmp, /opt, /usr mean, and why it matters
tags:
  - linux
  - concepts
---

# 01 — Filesystem Hierarchy

Linux presents everything as files — but where those files live tells you a lot about what they're for.

## The Big Picture

```
/               # root — the top of the entire tree
├── bin/        # essential commands (usually symlinked to /usr/bin)
├── boot/       # kernel, GRUB config — the stuff needed to boot
├── dev/        # device files — disks, terminals, null, zero
├── etc/        # configuration files — your apps' settings live here
├── home/       # regular users' personal files and settings
├── lib/        # shared libraries (usually symlinked to /usr/lib)
├── media/      # removable media — USB drives, CDs get mounted here
├── mnt/        # temporary mount point for external filesystems
├── opt/        # optional/third-party software (Oracle, Chrome, etc.)
├── proc/       # kernel's view of running processes and system state
├── root/       # root user's home directory (NOT /home/root)
├── run/        # runtime data — PID files, sockets, state
├── sbin/       # system administration commands
├── srv/        # data served by this machine (web content, FTP, etc.)
├── sys/        # kernel's view of hardware and kernel parameters
├── tmp/        # temporary files — cleared on reboot by default
├── usr/        # user-installed programs and libraries
└── var/        # variable data — logs, databases, mail spools
```

## What Lives Where

### /etc — Configuration

Every service and many system tools store their config here.

```bash
/etc/nginx/nginx.conf
/etc/ssh/sshd_config
/etc/systemd/system/          # systemd service files
/etc/apt/sources.list        # Debian package sources
/etc/pacman.conf             # Arch package sources
/etc/hosts                   # static hostname → IP mapping
/etc/resolv.conf             # DNS nameservers
/etc/fstab                   # filesystems to mount at boot
/etc/crontab                 # system-wide cron jobs
```

### /var — Things That Change

"Variable" data — files that grow and change over time.

```bash
/var/log/                    # all system and app logs
/var/cache/                  # cached data from package managers, etc.
/var/lib/                    # application state (databases, etc.)
/var/spool/                  # queued jobs — print queues, mail, cron
/var/tmp/                    # temporary files preserved between reboots
/var/mail/                   # incoming mail (usually symlinked to /var/spool/mail)
```

### /usr — Installed Software

The bulk of installed programs and libraries.

```bash
/usr/bin/                    # non-essential user commands (ls, cp, git)
/usr/sbin/                   # non-essential system admin commands
/usr/lib/                    # libraries for /usr/bin and /usr/sbin programs
/usr/local/                  # software YOU install (not from package manager)
/usr/share/                  # architecture-independent data (man pages, icons)
/usr/include/                # header files for C/C++ compilation
```

### /dev — Device Files

Everything is a file, even hardware devices.

```bash
/dev/null      # black hole — anything written here is discarded
/dev/zero     # infinite zero bytes — useful for wiping files
/dev/random   # random data (blocking — waits for entropy)
/dev/urandom  # random data (non-blocking)
/dev/sda      # first SATA/SCSI disk
/dev/sda1     # first partition on first disk
/dev/tty      # your current terminal
/dev/pts/0   # pseudo-terminal (what your terminal emulator uses)
/dev/full     # always "full" — writes fail with ENOSPC
```

### /proc — Kernel's Process Table

Not real files — the kernel exposes process and system state as files here.

```bash
/proc/1/          # PID 1 (init/systemd) — inspect any process
/proc/cpuinfo     # CPU model and features
/proc/meminfo     # RAM usage
/proc/loadavg     # load averages (1, 5, 15 min)
/proc/uptime      # how long since last boot
/proc/version     # kernel version
/proc/sys/net/    # tunable network parameters
/proc/sys/vm/     # virtual memory tunables
```

## Why This Matters

### Finding Things

Knowing the structure means you can find anything without searching:

```bash
# "Where does SSH store its config?"
# Answer: /etc/ssh/

# "Where do logs go?"
# Answer: /var/log/

# "Where are user home directories?"
# Answer: /home/

# "Where do I install my own software?"
# Answer: /opt/ or /usr/local/
```

### Troubleshooting

When something breaks, knowing where to look is half the battle:

```bash
# Disk full?
df -h              # check mount points
du -sh /var/log/* # which log is eating space?

# Which service owns this config?
ls /etc/systemd/system/*.wants/ | grep nginx

# What's listening on port 80?
ss -tlnp | grep :80
```

### Understanding Security

Many privilege escalations rely on misconfigured permissions under /etc, /var, /tmp, and /dev.

```bash
# World-writable /etc/shadow = owned
ls -la /etc/shadow

# /tmp with sticky bit missing = another user can tamper with your files
ls -la / | grep tmp

# /dev/null behaving oddly
# If /dev/null is a regular file instead of a device = something is wrong
file /dev/null
```

## Key Commands

```bash
ls -la /              # see the full hierarchy with permissions
df -h                # disk space per mount
du -sh /path/to/dir  # size of a directory
tree /               # visual tree (if installed: apt install tree)
mount                # show all mounted filesystems
find / -name nginx.conf  # find a file anywhere on the system
```

## The TL;DR

| Path | What it's for |
|------|--------------|
| `/etc` | Configuration — static system and app settings |
| `/var` | Variable data — logs, caches, databases, queues |
| `/home` | Regular users' files |
| `/root` | Root's home directory |
| `/usr` | Installed software (from packages) |
| `/opt` | Optional/third-party software (manual installs) |
| `/tmp` | Temporary files (cleared on reboot) |
| `/var/tmp` | Temporary files (preserved across reboots) |
| `/dev` | Device files — hardware as files |
| `/proc` | Kernel's view of processes and state |
| `/sys` | Kernel's view of hardware and parameters |