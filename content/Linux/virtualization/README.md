---
title: Virtualization
description: Linux virtualization — containers, container runtimes, namespaces, overlayfs, podman, systemd-nspawn
tags:
  - linux
  - virtualization
  - containers
---

# Virtualization

Linux containers and virtual machines isolate workloads using kernel primitives: namespaces, cgroups, and overlay filesystems.

## Containers

- [[container-runtimes]] — runc, containerd, OCI spec, runtime hierarchy
- [[podman]] — rootless containers, pods, Quadlet, Docker-compatible CLI
- [[overlayfs]] — upperdir/lowerdir/merged, whiteout files, copy-up
- [[mount-namespace]] — mount propagation, shared/private/slave
- [[user-namespace]] — UID/GID mapping, subuid/subgid, rootless containers
- [[network-namespace]] — veth pairs, bridge, NAT, isolated network stacks
- [[container-security]] — seccomp, cap-drop, read-only rootfs, user namespaces

## System Containers

- [[systemd-nspawn]] — lightweight containers, machinectl, as service

## Traditional Virtualization

- [[hypervisors]] — type 1 vs type 2, KVM, Xen, VMware
- [[emulator-vs-virtualization]] — full emulation vs paravirtualization