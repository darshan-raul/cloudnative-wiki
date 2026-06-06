---
title: Linux Capabilities
description: Linux capabilities — granular privileges, CAP_SYS_ADMIN, CAP_NET_ADMIN, cap_add/cap_drop, privilege separation
tags:
  - linux
  - security
  - containers
---

# Linux Capabilities

Traditional Unix distinguishes between **root** (UID 0, all privileges) and **non-root** (no privileges). Linux capabilities split root's privileges into ~40 granular units, so a process can have just the network privileges it needs without having file system privileges.

## The Problem with Root

Historically, if a process needed to bind port 80 (a privileged port), it had to run as root. Running as root means it could do *anything*: mount filesystems, load kernel modules, read all files, etc.

Linux capabilities solve this by breaking up what "root" means into individual capabilities.

## How Capabilities Work

Each thread has a set of permitted, effective, and inheritable capabilities:

```bash
# View capabilities of a process
cat /proc/$$/status | grep Cap
# CapInh: 0000000000000000   # inherited capabilities
# CapPrm: 0000003fffffffff   # permitted (what it CAN enable)
# CapEff: 0000003fffffffff   # effective (what it IS using)
# CapBnd: 0000003fffffffff   # bounding set (limits on what's possible)
# CapAmb: 0000000000000000   # ambient (inherited across execve)
```

```bash
# Human-readable form
capsh --print

# Decode a capability bitmask
grep -E "0x[0-9a-f]+|cap_" /proc/$$/status
python3 -c "import os; print([i for i in range(40) if os.getresuid(0) or True])"
```

## The 40 Capabilities

### Full List (from `<linux/capability.h>`)

```
CAP_CHOWN         chown — change file ownership (owner + group)
CAP_DAC_OVERRIDE  bypass file read/write/execute permission checks
CAP_DAC_READ_SEARCH  bypass read + search permission on files
CAP_FOWNER        bypass owner check on operations requiring it
CAP_FSETID        allow setting file owner/group on files you don't own
CAP_KILL          send signals to processes without being their parent
CAP_SETGID        change process GID
CAP_SETUID        change process UID
CAP_SETPCAP       modify process capabilities (in bounding set)
CAP_LINUX_IMMUTABLE  chattr +i / -i (immutable files)
CAP_NET_BIND_SERVICE  bind to ports < 1024
CAP_NET_BROADCAST  broadcast, multicast routing
CAP_NET_ADMIN     network namespace operations, interface config, routing
CAP_NET_RAW       raw sockets, packet sniffing, ICMP
CAP_IPC_LOCK      lock memory into RAM (mlock, mlockall)
CAP_IPC_OWNER     IPC operations on objects you don't own
CAP_SYS_MODULE    load/unload kernel modules
CAP_SYS_RAWIO     direct disk I/O (hdparm, raw devices)
CAP_SYS_CHROOT    use chroot()
CAP_SYS_ADMIN     *** THE GOD CAP *** (mount, setup namespaces, cgroups, ...)
CAP_SYS_NICE      set process nice value, CPU affinity
CAP_SYS_RESOURCE  override resource limits, disk quotas
CAP_SYS_TIME      set system clock, real-time clocks
CAP_SYS_TTY_CONFIG  configure TTY
CAP_MKNOD         create special files (mknod)
CAP_LEASE         take file leases
CAP_AUDIT_WRITE   write to audit log
CAP_AUDIT_CONTROL  configure audit subsystem
CAP_SETFCAP       set file capabilities
```

### The "God Cap" — CAP_SYS_ADMIN

`CAP_SYS_ADMIN` is the most dangerous capability. It includes:

- Mount/unmount filesystems
- Create/modify/delete namespaces (pid, mnt, net, user, etc.)
- Configure cgroups
- Load kernel modules
- Perform raw I/O
- Modify hostname
- Set up IPC
- Access performance counters

This is what `docker --privileged` grants. It's essentially root.

### CAP_NET_ADMIN

Required for network interface configuration:

```
- Create network namespaces
- Bring interfaces up/down
- Configure routing tables
- Set up bridging, VLANs
- Configure traffic control (tc)
- Modify iptables rules
- Enable IP forwarding
```

`CAP_NET_ADMIN` is required for Kubernetes pod networking setup.

## Container Capabilities

### Docker Capability Flags

```bash
# Drop all capabilities, add just NET_BIND
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE nginx

# Run privileged (ALL capabilities, disables seccomp)
docker run --privileged nginx

# Keep all capabilities (Docker default)
docker run --cap-add ALL nginx

# User namespace remapping (combines with --privileged)
docker run --userns host nginx
```

### Kubernetes Security Context

```yaml
securityContext:
  capabilities:
    add: ["NET_BIND_SERVICE"]
    drop: ["ALL"]
```

### What's the Difference?

```
CAP_NET_BIND_SERVICE (bind port < 1024)
  → Allows: nginx listening on :80
  → Blocks: mounting filesystems, creating namespaces

CAP_SYS_ADMIN (--privileged equivalent)
  → Allows: everything
  → Blocks: almost nothing
```

## File Capabilities

Files can have capabilities attached (POSIX file capabilities), so a binary can get specific privileges without running as root:

```bash
# Set file capability
setcap cap_net_bind_service+ep /usr/bin/nginx
#   cap      = capability name
#   +ep      = add (e=effecgive, p=permitted)
#   -ep      = remove
#   =ep      = set

# Verify
getcap /usr/bin/nginx
# /usr/bin/nginx = cap_net_bind_service+ep

# Remove all file capabilities
setcap -r /usr/bin/nginx
```

When a file has `cap_net_bind_service+ep`:
- Anyone running it gets `CAP_NET_BIND_SERVICE` permitted
- `e` flag means effective immediately (no need to call `capset()`)

## Inherited Capabilities and execve()

When a program is executed:

```
Permitted   = (file_cap_effective) & (inheritable) & (bounding_set)
Effective   = (file_cap_effective) OR (no_new_privs)
Inheritable = (inheritable)
```

The `inheritable` set controls which capabilities survive across `execve()`. This is why a capability granted in a container may not be available outside it.

## No-New-Privileges

`SECBIT_NO_NEW_PRIVS` prevents gaining NEW capabilities after it's set:

```bash
# Once set, even a setuid binary won't gain root
prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);

# In Kubernetes:
securityContext:
  noNewPrivileges: true
```

This is important for privilege escalation prevention: even if a vulnerability in the container process lets you manipulate file capabilities, `no_new_privileges` blocks it.

## Quick Reference: What You Need

| Task                    | Capability Needed               |
|------------------------|-------------------------------|
| Bind port < 1024       | CAP_NET_BIND_SERVICE          |
| Use ping (ICMP raw)    | CAP_NET_RAW                    |
| tcpdump                 | CAP_NET_RAW + CAP_SYS_ADMIN   |
| strace                  | CAP_SYS_PTRACE                |
| mount (in user NS)     | CAP_SYS_ADMIN (in user NS)   |
| Network namespace       | CAP_SYS_ADMIN (or user NS)    |
| Modify routing table    | CAP_NET_ADMIN                  |
| Modify iptables rules   | CAP_NET_ADMIN                  |
| Load kernel module      | CAP_SYS_MODULE                |
| chmod +i (immutable)   | CAP_LINUX_IMMUTABLE          |
| mlock (lock memory)    | CAP_IPC_LOCK                  |
| Set real-time clock     | CAP_SYS_TIME                  |

## Listing Current Capabilities

```bash
# Of current shell
capsh --print

# Of a running process
grep Cap /proc/1234/status
cat /proc/1234/status | grep Cap

# Decode
capsh --decode=0000003fffffffff

# Check specific capability
cat /proc/$$/status | grep CapEff
# CapEff: 0000003fffffffff

# Does current process have CAP_NET_RAW?
python3 -c "import os; print(os.geteuid() == 0 or True)"  # check effective uid
getpcaps $$   # shows caps of current process
```