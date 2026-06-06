---
title: Linux Kernel
description: Linux kernel internals — subsystems, syscalls, cgroups, /proc, /sys, signals, process management
tags:
  - linux
  - kernel
---

# Linux Kernel

The kernel is the core of every Linux system. It manages hardware, enforces security boundaries between processes, schedules CPU time across thousands of concurrent processes, and exposes system state through the /proc and /sys virtual filesystems.

This section is reference material — read it after completing the [[../concepts/README|concepts curriculum]], particularly the process and filesystem sections. The concepts here explain *how* Linux works under the hood.

## cgroups — Control Groups

**[[cgroups]]** covers Linux's mechanism for limiting, accounting, and isolating process resource usage. cgroups v2 organizes resources into a unified hierarchy where each controller (cpu, memory, io, pids) contributes to a single tree. Essential for container runtimes — runc, containerd, and podman all use cgroups to enforce per-container resource limits.

Key concepts: `/sys/fs/cgroup/`, controllers vs resources, `cpu.max`, `memory.max`, `io.max`, delegation to unprivileged users.

## /proc and /sys

**[[proc-sys]]** covers the two virtual filesystems that expose kernel state. `/proc/` is process-oriented — every running process has a directory (`/proc/PID/`) with status, maps, fd, and more. `/sys/` is device and driver-oriented — block devices, network interfaces, kernel modules, and tunable parameters live here.

Together they let you inspect and tune the running kernel without special tools: `cat /proc/meminfo`, `echo 1 > /proc/sys/net/ipv4/ip_forward`, `ls /sys/block/`.

## Signals

**[[signals]]** covers how the kernel delivers asynchronous events to processes. Signals are the lowest-level interrupt mechanism in Linux — when you press Ctrl+C, send SIGTERM to stop a service, or watch a process die from SIGKILL, the kernel is routing those signals.

Key signals every admin should know: SIGTERM (15, polite shutdown), SIGKILL (9, force kill), SIGSTOP (19, pause), SIGCHLD (17, child exited), SIGHUP (1, config reload). Signal handlers, signal masks, and how zombie processes relate to unhandled child signals.

## Process Management

**[[process-management]]** goes deeper than the basics in [[../concepts/03-processes|03-processes]]. Covers the full process lifecycle: how the scheduler works (CFS), process states (R/S/D/Z/T/I), the `/proc/PID/status` state machine, zombie reaping, daemon patterns, `prctl(PR_SET_NAME)`, process priority and nice values, `cgroups` integration with the scheduler, and kernel thread (`kthread`) behavior.