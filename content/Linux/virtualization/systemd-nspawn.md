---
title: systemd-nspawn
description: systemd-nspawn — lightweight containers, --boot, --network-veth, --bind, --chroot-like operation, container as PID 1
tags:
  - linux
  - containers
  - virtualization
---

# systemd-nspawn

`systemd-nspawn` is a lightweight container runtime built into systemd. Unlike Docker, there's no daemon — it launches containers directly as a process tree on the host. It's great for homelab, testing, and running services without Docker's overhead.

## Basic Usage

```bash
# Download a minimal Fedora rootfs:
dnf --installroot=/var/lib/machines/fedora --releasever=40 install dnf systemd passwd

# Or Arch:
pacstrap -c /var/lib/machines/arch base

# Or Debian:
debootstrap stable /var/lib/machines/debian

# Start a container from a directory:
systemd-nspawn -b -D /var/lib/machines/fedora
# -b = boot (run systemd as PID 1 inside)
# -D = directory containing the rootfs
```

Inside the container, you get a full init system (systemd), normal login (`root` with password from the host's `/etc/passwd`), and all the usual systemd tools.

Exit: `poweroff` or `Ctrl+]]` three times quickly.

## Networking

```bash
# Default: container shares host's network namespace (no isolation)
# Use --network-veth to create a virtual ethernet pair:

systemd-nspawn -b -D /var/lib/machines/fedora --network-veth

# With a bridge (container gets its own IP):
# Create bridge on host:
ip link add name nspawn-br type bridge
ip addr add 10.0.0.1/24 dev nspawn-br
ip link set nspawn-br up

# Run container with bridge:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --network-bridge=nspawn-br

# Disable networking entirely:
systemd-nspawn -b -D /var/lib/machines/fedora --private-network
```

## Filesystem Access

```bash
# Bind mount a directory from host into container (read-write):
systemd-nspawn -b -D /var/lib/machines/fedora \
    --bind /data

# Read-only bind:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --bind-ro=/etc/ssl

# Bind a specific directory to a different path:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --bind=/tmp/cache:/var/cache/mycachedir

# Bind current working directory as /project:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --bind=$(pwd):/project

# Bind /home from host:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --bind-home

# TMPFS inside container:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --tmpfs=/tmp
```

## Users and Permissions

```bash
# Run as a specific user inside the container:
systemd-nspawn -b -D /var/lib/machines/fedora -U

# With specific UID/GID mapping (rootless-like):
systemd-nspawn -b -D /var/lib/machines/fedora \
    --private-users=pick     # picks UID/GID from /etc/subuid

# Or explicit mapping:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --private-users=0:0:65536  # host 0 → container root (0-65536 range)
```

## Resource Limits

```bash
# Memory limit:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --memory=512M

# CPU limit (2 cores):
systemd-nspawn -b -D /var/lib/machines/fedora \
    --cpu-affinity=0,1

# Process limit:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --processes=100

# Open files limit:
systemd-nspawn -b -D /var/lib/machines/fedora \
    --rlimit=RLIMIT_NOFILE=1024:4096

# Disable personality (setarch):
systemd-nspawn -b -D /var/lib/machines/fedora \
    --personality=x86-64
```

## As a Service (machinectl)

```bash
# machinectl — systemd's container management tool

# Start a container as a system service:
machinectl start fedora
machinectl status fedora

# Login to running container:
machinectl login fedora       # opens pts inside container
machinectl shell fedora        # spawns a shell in the container

# Stop:
machinectl poweroff fedora

# List running containers:
machinectl list
# MACHINE  CLASS     SERVICE OS    VERSION  ADDRESSES
# fedora   container nspawn   Fedora 40       10.0.0.2

# Enable to start at boot:
systemctl enable systemd-nspawn@fedora

# The service file is:
# /etc/systemd/system/systemd-nspawn@.service
```

### Creating a service for it:

```ini
# /etc/systemd/system/myapp-nspawn.service
[Unit]
Description=My App Container
Requires=systemd-nspawn@myapp.service
After=network.target

[Service]
ExecStart=/usr/bin/systemd-nspawn --boot \
    --bind=/etc/myapp/config.yaml:/etc/myapp/config.yaml \
    --bind=/var/log/myapp:/var/log/myapp \
    --private-network \
    --memory=1G \
    -D /var/lib/machines/myapp

[Install]
WantedBy=multi-user.target
```

## Pivot_root vs chroot

```bash
# systemd-nspawn uses pivot_root internally, not chroot:
# - Better isolation (old root can't be reached via pivot_root)
# - /proc, /sys, /dev are isolated per container
# - Works correctly with systemd as PID 1
```

## Common Options Reference

```bash
# Boot as systemd PID 1:
-b, --boot

# Working directory:
-D, --directory=/path/to/rootfs

# Network:
--network-veth         # create virtual eth pair
--network-bridge=NAME  # attach to bridge
--private-network      # no network (fully isolated)
--network-interface=IF # add host interface to container

# Filesystem:
--bind=PATH           # bind mount (rw)
--bind-ro=PATH        # bind mount (ro)
--bind-home           # bind /home from host
--tmpfs=PATH          # tmpfs mount
--overlay=PATH         # overlay FS mount

# Users:
-U, --private-users   # use systemd's UID shifting
--private-users=pick  # auto-pick UID range
--user=USERNAME       # run as this user

# Resource limits:
--memory=VALUE        # e.g., 512M, 4G
--cpu-affinity=N,M    # CPU affinity
--processes=N          # max processes
--rlimit=NAME=SOFT:HARD

# Security:
--no-new-privileges   # like NoNewPrivileges=
--capability=CAP_...  # drop capabilities
--kill-signal=SIGNAL  # signal to send on SIGTERM

# Machine name:
-M, --machine=NAME    # container name (for machinectl)
```

## Container Inside Container (Nested)

```bash
# Running nspawn inside nspawn (nested):
# On host:
systemd-nspawn -b -D /var/lib/machines/outer

# Inside outer:
# You can run another nspawn (requires user namespace):
systemd-nspawn -b -D /var/lib/machines/inner --private-users=pick
```

## Debugging

```bash
# Verbose output:
systemd-nspawn -b -D /var/lib/machines/fedora --verbose

# Drop to shell before boot:
systemd-nspawn -D /var/lib/machines/fedora

# With gdb:
systemd-nspawn -D /var/lib/machines/fedora --strace

# Show what would be executed:
systemd-nspawn -b -D /var/lib/machines/fedora --dry-run

# Network namespace info:
machinectl show fedora
```

## Quick Reference

```bash
# Start container:
systemd-nspawn -b -D /path/to/rootfs

# With networking:
systemd-nspawn -b -D /path/to/rootfs --network-veth

# With resource limits:
systemd-nspawn -b -D /path/to/rootfs --memory=512M --cpu-affinity=0,1

# As service:
systemctl enable --now systemd-nspawn@mycontainer
machinectl start mycontainer
machinectl shell mycontainer
machinectl poweroff mycontainer

# List:
machinectl list
```