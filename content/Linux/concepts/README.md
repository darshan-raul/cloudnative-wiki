---
title: Linux Concepts
description: Linux fundamentals — beginner curriculum covering filesystem, permissions, processes, users, packages, services, networking, storage, and shell
tags:
  - linux
  - concepts
---

# Linux Concepts

A beginner curriculum and reference for Linux fundamentals. Work through the numbered files in order if you're starting out — they build on each other. The quick-reference topics at the bottom can be read standalone at any level.

## Beginner Curriculum (01–12)

Start here if you're new to Linux. Each file builds on the previous.

**01 [[01-filesystem-hierarchy|Filesystem Hierarchy]]**
What every directory in `/` is for — `/etc` for config, `/var` for changing data, `/usr` for programs, `/dev` for devices, `/proc` for kernel state, `/tmp` for temporary files. Understanding the layout makes everything else easier.

**02 [[02-file-permissions|File Permissions]]**
The `rwx` permission model: reading, writing, executing for owner/group/others. `chmod`, `chown`, `chgrp`, `umask`, and the special bits — sticky bit (`+t`), setuid (`+s`), setgid (`+s`). ACLs for more granular control.

**03 [[03-processes|Processes]]**
What a process is: PID, parent/child relationships, zombie and orphan processes, daemon vs foreground. How to list, kill, and manage processes with `ps`, `top`, `htop`, and `kill`.

**04 [[04-users-and-groups|Users and Groups]]**
Linux's multi-user model: `/etc/passwd`, `/etc/shadow`, and `/etc/group` explained. `useradd`, `usermod`, `userdel`, `sudo`, and how service accounts differ from regular users. The difference between `/usr/sbin/nologin` and `/bin/false`.

**05 [[05-package-management|Package Management]]**
How packages work: the package manager's job (dependencies, repositories, upgrades). apt on Debian/Ubuntu, pacman on Arch/Manjaro, dnf on Fedora/RHEL. What a `.deb` or `.pkg.tar.zst` actually contains.

**06 [[06-services|System Services]]**
What a daemon is and how systemd manages services. `systemctl start`, `stop`, `restart`, `enable`, `disable`, `status`. Reading and writing basic `.service` files. The difference between `enable` and `start`.

**07 [[07-boot-process|Boot Process]]**
The full sequence from pressing the power button: BIOS/UEFI POST → bootloader (GRUB) → kernel loads → initramfs mounts the real root → systemd starts services in parallel → login screen. Kernel command-line parameters and GRUB basics.

**08 [[08-logging|Logging]]**
Where Linux stores logs: `/var/log/syslog`, `/var/log/auth.log`, and friends. `journalctl` for querying the systemd journal: filtering by unit, time, priority, boot ID. `logrotate` for keeping logs from filling the disk. Binary logs (`last`, `lastlog`, `faillog`) and when to use them.

**09 [[09-networking-basics|Networking Basics]]**
IP addresses (IPv4 and IPv6), CIDR notation, private ranges. Subnets and gateways. DNS resolution: `/etc/resolv.conf`, `host`, `dig`. Checking connectivity with `ping` and `curl`. Listening ports: `ss -tlnp`. Firewalls at a high level (UFW basics).

**10 [[10-storage-basics|Storage Basics]]**
How Linux sees storage: disks → partitions → filesystems → mount points. `lsblk`, `fdisk`, `parted`. Creating filesystems with `mkfs`. Mounting manually and automatically via `/etc/fstab`. UUIDs and why device names like `/dev/sda1` can be unreliable. LVM at a high level (PV/VG/LV).

**11 [[11-shell-basics|Shell Basics]]**
Bash fundamentals: environment variables, `PATH`, aliases, history (`!!`, `!$`, `Ctrl+R`). Tab completion, job control (`&`, `Ctrl+Z`, `fg`, `bg`, `jobs`). Shell configuration files (`~/.bashrc` vs `~/.bash_profile`).

**12 [[12-io-redirection|I/O Redirection]]**
The three standard streams: stdin (0), stdout (1), stderr (2). Redirecting to files (`>`, `>>`, `2>`). Pipes (`|`). `tee` for write-and-pass-through. `xargs` for building commands from stdin. here-docs (`<<EOF`) and here-strings (`<<<`). Process substitution (`<(cmd)`).

## Quick-Reference Topics

Standalone topics useful at any level:

```
[[hardlink-vs-softlink]]  — Hard links vs symbolic links, when to use each
[[ulimit]]               — Resource limits: open files, processes, memory
[[tty-pty]]             — Terminals: TTY, PTS, PTY, screen, tmux
[[tmpfs]]               — RAM-based filesystem: /dev/shm, /run, /tmp
[[sockets]]             — Unix domain sockets: SOCK_STREAM, SOCK_DGRAM
[[spool-directory]]      — /var/spool: mail, print queues, at-jobs
[[bash-cheatsheet]]     — bash quick reference (devhints.io style)
```