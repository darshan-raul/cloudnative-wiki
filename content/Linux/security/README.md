---
title: Linux Security
description: Linux security — capabilities, seccomp, AppArmor, auditd, PAM, sysctl hardening, systemd service hardening, CIS benchmarks
tags:
  - linux
  - security
---

# Linux Security

Defense in depth on Linux means layers: kernel capabilities removed from services, syscalls filtered, access control enforced, system calls audited, and the kernel itself hardened via sysctl. This section covers all those layers.

## Access Control and Hardening

**[[sysctl|System Sysctl Hardening]]** — Kernel parameters you tune at runtime via `/proc/sys` or `/etc/sysctl.conf`. Network hardening (ARP flux, source routing, ICMP redirects, IP forwarding), memory hardening (`kernel.dmesg_restrict`, `kernel.kptr_restrict`), and kernel lockdown module.

**[[linux-cis-hardening|Linux CIS Hardening]]** — The Center for Internet Security Linux Benchmarks as a checklist. GRUB bootloader hardening, filesystem mounts (disabling unused filesystems), user limits (`/etc/security/limits.conf`), PAM password quality (`pam_pwquality.so`), `/etc/login.defs` settings, and auditd rules for compliance.

**[[systemd-service-hardening|systemd Service Hardening]]** — Every systemd service should be hardened. The key directives: `ProtectSystem=full`, `ReadOnlyPaths=/`, `NoNewPrivileges=true`, `PrivateTmp=true`, `AmbientCapabilities=`, `SystemCallFilter=@system-service`, `User=`/`Group=`, `SupplementaryGroups=`, `LimitNOFILE=`, `Restart=`, `RestartSec=`. CIS-style service lockdown for any service you run.

## Capabilities

**[[capabilities|Linux Capabilities]]** — The fine-grained privilege model that replaced suid root. The 40+ capability bits (CAP_SYS_ADMIN, CAP_NET_ADMIN, CAP_NET_RAW, CAP_DAC_OVERRIDE, etc.) and how to drop all but the minimum a service needs. `capsh` for inspecting and manipulating capability sets. The security implications of CAP_SYS_ADMIN (almost root equivalent).

## Syscall Filtering

**[[seccomp|seccomp]]** — The Linux kernel's syscall filter mechanism. BPF programs that decide which syscalls a process is allowed to make. The default seccomp profile in Docker (whitelist of ~300 syscalls). Writing custom seccomp profiles for containers. `SECCOMP_MODE_FILTER`, `prctl(PR_SET_SECCOMP)`, and how strace relates to seccomp.

## Mandatory Access Control

**[[apparmor|AppArmor]]** — Path-based Mandatory Access Control (MAC). Profiles that whitelist specific files and capabilities for each program — unlike SELinux's label-based model. `aa-status`, `aa-genprof`, `aa-logprof`, enforcing vs complain/learning mode. AppArmor's integration with Docker and podman.

## Auditing

**[[auditd|auditd]]** — The Linux audit subsystem for syscall and security event logging. `/etc/audit/audit.rules` syntax and key rules to track file access, privilege escalation, and failed syscalls. `aureport` for human-readable summaries, `ausearch` for querying the log, `autrace` for per-process syscall traces. What audit events look like in `/var/log/audit/audit.log`.

## Process Security

**[[core-dumps|core-dumps]]** — Controlling whether running processes can dump their memory to disk. `ulimit -c`, `/proc/sys/kernel/core_pattern`, `systemd-coredump`, and `abrt` on RHEL. Why you want core dumps disabled in production (they contain sensitive data) but useful in development.

**[[chattr-lsattr|chattr and lsattr]]** — File attributes beyond permissions. `chattr +i` (immutable — not even root can delete), `chattr +a` (append-only), and how these prevent accidental or malicious modification. `lsattr` to view them. Why immutable is useful for `/etc/passwd` and `/etc/shadow`.

**[[device-files|Device Files]]** — `/dev/null`, `/dev/zero`, `/dev/urandom`, `/dev/full` — special device files and their uses. How `mknod` creates device nodes, the major/minor number system, and how udev dynamically creates device nodes when hardware is hotplugged.

## Container Security

**[[container-security|Container Security]]** — Applying the above to containers: dropping all capabilities except what's needed, seccomp profile customization, read-only rootfs, non-root containers via user namespaces, healthcheck design that doesn't bypass security, and rootless podman.

## PAM

**[[pam|PAM]]** — Pluggable Authentication Modules used by login, sudo, passwd, and most authentication paths. Covers auth, account, password, and session module stacks, with practical examples of `pam_limits.so` (ulimits) and `pam_unix.so` (traditional password auth).