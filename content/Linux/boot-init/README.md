---
title: Linux Boot & Init
description: Linux boot process and init systems — UEFI/BIOS, GRUB, kernel, systemd, cron, timers
tags:
  - linux
---

# Linux Boot & Init

Beginner: [[07-boot-process]] — the full boot sequence from power button to login.

Reference:
- [[boot-process]] — full boot pipeline (UEFI/BIOS → GRUB → initramfs → systemd)
- [[systemd]] — units, targets, service files, socket activation, journald
- [[systemd-timers]] — systemd's cron alternative, calendar events, persistent timers
- [[cron-anacron]] — cron syntax, anacron for non-always-on machines
- [[tmpfiles]] — systemd-tmpfiles.d, volatile runtime directories
- [[nohup-disown-setsid]] — running processes that survive terminal close