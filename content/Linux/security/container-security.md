---
title: Container Security
description: Container security — seccomp profiles, cap-drop, read-only rootfs, user namespaces, no-new-privileges, AppArmor, resource limits, healthchecks
tags:
  - linux
  - containers
  - security
---

# Container Security

Hardening containers means reducing the blast radius if a container is compromised. The key principles: run as non-root, drop capabilities, restrict syscalls, make the filesystem read-only, and isolate the network.

## Run as Non-Root

```bash
# Create a user in the Dockerfile:
RUN useradd -m -s /bin/bash appuser
USER appuser

# Or in docker-compose:
user: "1000:1000"

# Or in Kubernetes:
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
```

## Drop All Capabilities, Add Only What's Needed

Linux capabilities are the granular privileges that root has. Docker grants a subset by default. You should drop all and add back only what's required.

```bash
# Drop ALL capabilities, add only what you need:
docker run --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    nginx

# Common capabilities:
# AUDIT_WRITE       — write to kernel audit log
# CHOWN             — change file ownership
# DAC_OVERRIDE      — bypass read/write/execute checks
# FOWNER            — bypass owner checks
# KILL              — send any signal
# NET_BIND_SERVICE  — bind to port < 1024
# NET_RAW           — raw sockets (ping uses this)
# SETFCAP           — set file capabilities
```

## No New Privileges

```bash
# Prevent container or its children from gaining new privileges:
docker run --security-opt=no-new-privileges:true \
    nginx

# In docker-compose:
security_opt:
  - no-new-privileges:true
```

## Read-Only Root Filesystem

```bash
# Make entire filesystem read-only, only allow specific rw mounts:
docker run --read-only \
    --tmpfs /tmp:rw,noexec,size=64m \
    --tmpfs /run:rw,noexec \
    nginx

# In docker-compose:
read_only: true
tmpfs:
  - /tmp
  - /run
```

## Seccomp Profiles

Seccomp restricts which syscalls a container can make. Docker's default profile blocks ~44 dangerous syscalls. You can use the built-in profile or provide your own.

```bash
# Use Docker's default seccomp profile (already applied by default):
docker run --security-opt seccomp=unconfined nginx   # disable seccomp

# Use a custom profile:
docker run --security-opt seccomp=/path/to/profile.json nginx

# Key: don't run containers as --privileged (that disables ALL seccomp and gives all capabilities)
```

### Example: Block dangerous syscalls

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {
      "names": ["mount", "umount2", "mount_points"],
      "action": "SCMP_ACT_ERRNO"
    },
    {
      "names": ["ptrace"],
      "action": "SCMP_ACT_ERRNO"
    },
    {
      "names": ["syslog"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
```

## AppArmor in Containers

```bash
# Run with AppArmor profile:
docker run --security-opt apparmor=/etc/apparmor.d/nginx nginx

# Docker's default AppArmor profile is applied automatically.
# To check what's allowed:
docker run --rm -it --security-opt apparmor=unconfined nginx aa-status
```

## User Namespaces (Rootless Containers)

Map container root (UID 0) to an unprivileged host UID:

```bash
# /etc/subuid and /etc/subgid must have entries:
# darshan:100000:65536

# dockerd must be started with:
dockerd --userns-remap=default

# Or in /etc/docker/daemon.json:
{
  "userns-remap": "default"
}

# Now container root (0) maps to host UID 100000:
# Container UID 0   → Host UID 100000
# Container UID 65535 → Host UID 165535
```

## Resource Limits

```bash
docker run \
    --memory=512m \
    --memory-swap=1g \
    --cpus=1.5 \
    --cpuset-cpus=0,1 \
    --pids-limit=100 \
    --ulimit nofile=1024:2048 \
    nginx
```

## Network Isolation

```bash
# By default, containers can reach the external network (NAT'd via bridge)
# To isolate:
docker network create --internal internal-net
docker run --network=internal-net nginx  # no external access

# Or disable networking entirely:
docker run --network=none nginx

# To allow only specific ports from host:
docker run --publish 127.0.0.1:8080:80 nginx  # host-only binding
```

## Secrets Management

**Never put secrets in Dockerfile or environment variables.**

```bash
# Docker secrets (swarm mode):
docker secret create db_password - <<< "supersecret"
docker service create --secret db_password myapp

# Kubernetes secrets (encrypted at rest in etcd):
kubectl create secret generic db-creds \
    --from-literal=password=supersecret

# Or use external secrets operators (HashiCorp Vault, AWS Secrets Manager)
```

## Healthchecks

```dockerfile
# In Dockerfile:
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
```

```bash
# Check health:
docker inspect --format='{{.State.Health.Status}}' container
```

## Image Security

```bash
# Scan images for vulnerabilities:
docker scan nginx
trivy image nginx:latest
anchore-cli image scan myrepo/myimage:latest

# Pull only signed images (Docker Content Trust):
export DOCKER_CONTENT_TRUST=1
docker pull myrepo/myimage

# Use minimal base images (alpine, distroless):
FROM gcr.io/distroless/static-debian12

# Don't run as root in Dockerfile:
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
```

## Kernel Hardening for Containers (Host Side)

On the Docker host, set these sysctls:

```bash
# /etc/sysctl.d/99-container.conf

# Prevent container from modifying iptables (already blocked by default):
net.bridge.bridge-nf-call-iptables=1

# Restrict the kernel from loading modules:
kernel.modules_disabled=1   # after loading required modules

# Prevent Docker from starting privileged containers by default:
# /etc/docker/daemon.json:
{
  "icc": false,
  "userns-remap": "default",
  "live-restore": true,
  "no-new-privileges": true,
  "default-ulimits": {
    "nofile": {"Name": "nofile", "Hard": 64000, "Soft": 64000}
  }
}
```

## Quick Reference

```bash
# Full hardened run command:
docker run \
    --detach \
    --name=hardened-app \
    --user=1000:1000 \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    --security-opt=no-new-privileges:true \
    --read-only \
    --tmpfs /tmp:rw,noexec,size=64m \
    --memory=512m \
    --cpus=1 \
    --pids-limit=50 \
    --network=internal-net \
    --publish 127.0.0.1:8080:8080 \
    --health-cmd="curl -f http://localhost:8080/health" \
    --health-interval=30s \
    myapp:latest
```

## Kubernetes Security Context

```yaml
apiVersion: v1
kind: Pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  containers:
  - name: app
    image: myapp:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
        add:
          - NET_BIND_SERVICE
    resources:
      limits:
        memory: "512Mi"
        cpu: "500m"
      requests:
        memory: "256Mi"
        cpu: "100m"
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    tmpfs:
      sizeLimit: "64Mi"
```