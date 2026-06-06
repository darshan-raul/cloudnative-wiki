---
title: Podman
description: Podman — rootless containers, podman vs Docker, pod management, Quadlet, rootless networking
tags:
  - linux
  - containers
  - podman
---

# Podman

Podman is a **daemonless, rootless** container runtime that's Docker-compatible. It uses the same OCI runtime (runc) and image format as Docker, but runs containers without a daemon and without root privileges. It's the default container runtime on RHEL/Fedora and preferred for rootless workloads.

## Podman vs Docker

| Feature             | Docker                  | Podman                        |
|--------------------|------------------------|-------------------------------|
| Daemon             | dockerd (runs as root)  | None (daemonless)             |
| Root privileges    | Requires root or docker group | Runs as normal user (rootless) |
| Container UID mapping | via dockerd (root) | via user namespaces (no root) |
| Pods | Via docker-compose     | Native pod support |
| Socket | /var/run/docker.sock   | /run/podman/podman.sock |
| systemd | docker.service | podman.socket + quadlet |

## Rootless Containers

Rootless Podman runs containers as the **user's own UID range** via user namespaces:

```bash
# Rootless: containers run as your UID
id
# uid=1000(darshan) gid=1000(darshan)

podman run --rm alpine echo "hello"
# Inside container: UID0 (root) maps to UID 100000 outside
# This is NOT real root — mapped through user namespace
```

### subuid / subgid

Rootless containers need a UID/GID range to map container UIDs to host UIDs:

```bash
# /etc/subuid and /etc/subgid control this mapping
cat /etc/subuid
# darshan:100000:65536
#  user start_uid count
# darshan gets UID100000-165535 to map into user namespaces

cat /etc/subgid
# darshan:100000:65536
```

## Basic Commands

```bash
# Run a container
podman run -d --name nginx nginx:latest
podman run -it alpine /bin/sh

# List containers
podman ps -a

# Logs
podman logs nginx
podman logs -f nginx

# Exec
podman exec -it nginx /bin/sh

# Build
podman build -t myapp:latest .

# Images
podman images
podman pull docker.io/library/alpine:latest

# Network
podman network ls
podman network create mynet
podman run --network mynet -d nginx
```

## Pods — Native Support

Podman has **native pod support** (unlike Docker which needs docker-compose for pods):

```bash
# Create a pod with shared resources
podman pod create --name mypod \
  --publish8080:80 \
  --publish 5432:5432

# Run containers in the pod
podman run -d --pod mypod --name app myapp:latest
podman run -d --pod mypod --name db postgres:15

# Pods share: network namespace, PID namespace (optionally), IPC namespace
podman pod inspect mypod
podman pod logs mypod        # all containers in pod
podman pod stop mypod
podman pod rm mypod
```

## Rootless Networking

Rootless containers can't use host networking directly (no CAP_NET_ADMIN outside a user namespace). Podman uses slirp4netns or pasta:

```bash
# Default: slirp4netns (userspace networking)
podman run --rm alpine ip addr
# eth0@if10: inet 10.0.2.100/24

# Host network (requires root):
sudo podman run --network host nginx

# pasta (newer, better slirp4netns replacement):
podman run --network pasta alpine ip addr
```

## Quadlet — systemd Integration

Podman uses **Quadlet** to manage containers as systemd units (the modern way to run containers at boot):

```bash
# /etc/containers/systemd/myapp.container
[Container]
Image=myapp:latest
ContainerName=myapp
PublishPort=8080:80
Volume=/data:/var/data

[Service]
Restart=always

# Or /etc/containers/systemd/myapp.volume
[Volume]
VolumeName=mydata

# Then:
systemctl daemon-reload
systemctl enable --now myapp
```

## Podman vs Docker CLI Compatibility

```bash
# Docker socket compatibility:
# Add to ~/.docker/config.json or set DOCKER_HOST:
export DOCKER_HOST=unix:///run/user/1000/podman/podman.sock

# Now docker CLI works with podman:
docker ps # uses podman socket transparently
docker run myapp:latest
```

## Common Troubleshooting

```bash
# Podman won't start (rootless) — check subuid mapping:
getent passwd | grep darshan
cat /etc/subuid | grep darshan
# Must have entries in /etc/subuid and /etc/subgid

# Network not working in rootless:
podman run --rm alpine ping8.8.8.8
# If fails: check firewall (rootless uses slirp4netns)

# Clean up:
podman system prune -a         # remove stopped containers, unused images
podman container rm -a
podman image rm -a
```