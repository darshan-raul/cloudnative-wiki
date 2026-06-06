---
title: Linux
description: "Linux operating system — beginner to advanced: filesystem, users, processes, networking, storage, boot, security, virtualization"
tags:
  - linux
---

# Linux

## Start Here — Concepts Curriculum

The [[Linux/concepts/README|concepts section]] is a beginner curriculum — work through it in order if you're starting out, or use it as a reference. It progresses from filesystem basics through to services, networking, and shell skills.

```
01-filesystem-hierarchy.md    — /etc, /var, /usr, /dev, /proc explained
02-file-permissions.md        — rwx, chmod, chown, umask, ACLs, special bits
03-processes.md              — PID, parent/child, zombies, daemons
04-users-and-groups.md        — /etc/passwd, /etc/shadow, /etc/group, sudo
05-package-management.md      — apt, pacman, dnf — packages and repositories
06-services.md               — systemd, systemctl, service files
07-boot-process.md           — BIOS/UEFI → GRUB → kernel → systemd
08-logging.md                — journalctl, /var/log, logrotate, binary logs
09-networking-basics.md       — IP, subnet, gateway, DNS, curl, ss
10-storage-basics.md          — disks, partitions, filesystems, mount, fstab, LVM
11-shell-basics.md           — bash, environment, PATH, aliases, history, pipes
12-io-redirection.md         — stdin/stdout/stderr, pipes, tee, xargs, here-docs
```

## Sections

### [[Linux/concepts/README|Concepts]] — Beginner curriculum
Fundamentals: filesystem hierarchy, permissions, processes, users/groups, packages, services, boot, logging, networking, storage, shell, I/O redirection. Also: hardlinks/softlinks, ulimit, TTY/PTY, tmpfs, sockets, spool directory.

### [[Linux/kernel/README|Kernel]] — Kernel internals
cgroups, /proc & /sys, signals, process management. Reference material for after you've gone through the concepts curriculum.

### [[Linux/networking/README|Networking]] — TCP/IP, firewall, DNS
TCP/IP model, routing, iptables, firewalld, DNS resolution, ip command, dhcp, netplan, ss, network performance tuning.

### [[Linux/storage/README|Storage]] — Disks, LVM, filesystems
Disks and partitions, LVM, RAID, filesystems (ext4, xfs, btrfs), mount and fstab, storage performance tuning.

### [[Linux/users-groups/README|Users & Groups]] — Identity and PAM
User management, nologin accounts, sudo, /etc/passwd, /etc/shadow, /etc/group.

### [[Linux/boot-init/README|Boot & Init]] — Boot, systemd, scheduling
Boot process, systemd, cron and anacron, systemd timers, systemd-tmpfiles, nohup and disown.

### [[Linux/security/README|Security]] — Hardening and access control
Capabilities, seccomp, AppArmor, auditd, chattr/lsattr, core dumps, device files, sysctl tuning, systemd service hardening, Linux CIS hardening, container security.

### [[Linux/virtualization/README|Virtualization]] — Containers and hypervisors
Container runtimes (runc, containerd), podman, namespaces (mount, user, network), overlayfs, systemd-nspawn, hypervisors, emulator vs virtualization.

### [[Linux/packaging/README|Packaging]] — apt, pacman
apt, pacman — package management, repositories, AUR.

### [[Linux/observability/README|Observability]] — Monitoring and tracing
top, vmstat, iostat, sar, strace, journalctl, log management.

### [[Linux/shell-scripting/README|Shell Scripting]] — Bash scripting
bash cheatsheet, shell redirection, here-docs, process substitution, shell expansion, exit codes.

### [[Linux/troubleshooting/README|Troubleshooting]] — Debugging methodology
Systematic debugging, common issues, diagnosis framework.