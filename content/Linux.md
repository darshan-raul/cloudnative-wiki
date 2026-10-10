---
title: Linux
tags: [linux, system-admin, networking, kernel, tools, security]
date: 2026-09-06
description: "Linux operating system from beginner to advanced: filesystem, users, processes, networking, storage, boot, kernel internals, security, and virtualization."
---

# Linux 🐧

Linux system administration, internals, and tooling for cloud-native engineering.

## Start Here — Concepts Curriculum

The [[Linux/concepts/README|concepts section]] is a progressive curriculum from filesystem fundamentals to processes, services, and networking:

- [[Linux/concepts/01-filesystem-hierarchy|01 — Filesystem Hierarchy]] (`/etc`, `/var`, `/usr`, `/dev`, `/proc`)
- [[Linux/concepts/02-file-permissions|02 — File Permissions]] (`rwx`, `chmod`, `chown`, `umask`, ACLs)
- [[Linux/concepts/03-processes|03 — Processes]] (PID, parent/child, zombies, daemons)
- [[Linux/concepts/04-users-and-groups|04 — Users & Groups]] (`/etc/passwd`, `/etc/shadow`, sudo)
- [[Linux/concepts/05-package-management|05 — Package Management]] (`apt`, `pacman`, repositories)
- [[Linux/concepts/06-services|06 — Services & systemd]] (`systemctl`, service units)
- [[Linux/concepts/07-boot-process|07 — Boot Process]] (BIOS/UEFI → GRUB → Kernel → systemd)
- [[Linux/concepts/08-logging|08 — Logging]] (`journalctl`, `/var/log`, logrotate)
- [[Linux/concepts/09-networking-basics|09 — Networking Basics]] (IP, CIDR, gateway, DNS, `ss`, `curl`)
- [[Linux/concepts/10-storage-basics|10 — Storage Basics]] (Disks, partitions, filesystems, LVM)
- [[Linux/concepts/11-shell-basics|11 — Shell Basics]] (`bash`, environment, PATH, pipes)
- [[Linux/concepts/12-io-redirection|12 — I/O Redirection]] (`stdin`, `stdout`, `stderr`, `tee`, `xargs`)

---

## Core Domains & Reference

### 1. [[Linux/kernel/README|Kernel Internals]]

Kernel architecture, cgroups v1 & v2, `/proc` and `/sys` virtual filesystems, signals, IPC, and process scheduling.

### 2. [[Linux/networking/README|Networking & Firewalls]]

TCP/IP datapath, routing tables, `iptables`, `nftables`, `firewalld`, DNS resolution (`systemd-resolved`), `netplan`, and network tuning (`sysctl`).

### 3. [[Linux/storage/README|Storage & Filesystems]]

Block storage, partition schemes (GPT/MBR), LVM (PV/VG/LV), RAID arrays, filesystems (`ext4`, `xfs`, `btrfs`), mount options, and `/etc/fstab`.

### 4. [[Linux/users-groups/README|Identity, PAM & Permissions]]

User/group management, service accounts (`nologin`), `sudoers` policy, PAM authentication modules, and user namespaces.

### 5. [[Linux/boot-init/README|Boot, Init & Scheduling]]

System initialization, GRUB2 configuration, `systemd` target units, systemd timers, `cron` & `anacron`, and ephemeral cleanup (`systemd-tmpfiles`).

### 6. [[Linux/security/README|Hardening & Sandboxing]]

Linux Capabilities (`cap_net_admin`, `cap_sys_admin`), seccomp syscall filtering, AppArmor profiles, `auditd` logging, immutable files (`chattr +i`), core dump restriction, and CIS benchmark baselines.

### 7. [[Linux/virtualization/README|Containers & Virtualization]]

Container runtimes (`runc`, `containerd`), Linux namespaces (mount, PID, net, IPC, UTS, user), `overlayfs` storage driver, Podman rootless containers, and KVM/QEMU hypervisors. The [[Containers]] section builds on these: [[Containers/namespaces-and-cgroups|namespaces and cgroups]], [[Containers/images-and-layers|images]] and [[Containers/container-networking|container networking]].

### 8. [[Linux/packaging/README|Package Management]]

Package managers and repository infrastructure: `apt` (Debian/Ubuntu), `pacman` (Arch), `yum`/`dnf` (RHEL/Fedora), and low-level package tooling.

### 9. [[Linux/observability/README|System Observability & Tracing]]

Performance monitoring and diagnostics: `top`, `htop`, `vmstat`, `iostat`, `sar`, `strace`, `lsof`, and eBPF tracing tools.

### 10. [[Linux/shell-scripting/README|Shell Scripting & Productivity]]

Bash automation patterns, error handling (`set -euo pipefail`), traps, subshells, arrays, string manipulation, and terminal productivity with [[Linux/tmux|tmux]].

### 11. [[Linux/troubleshooting/README|Troubleshooting Methodology]]

Systematic root cause analysis playbooks for high CPU/load, OOM killer triggers, disk saturation, networking latency, and broken boot states.

---

## Related Topics

- ☸️ **[[Kubernetes]]** — Node kubelets, cgroups, network namespaces, and container runtimes run on Linux.
- ☁️ **[[AWS]]** — EC2 Amazon Linux 2023, Ubuntu, and container hosts.
- 🚀 **[[DevOps]]** — CI/CD runner environments, shell scripting, and DevSecOps runtime hardening.
- 🔐 **[[Security]]** — Host IDS/IPS, Wazuh agent integration, and endpoint hardening.
