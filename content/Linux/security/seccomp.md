---
title: seccomp
description: Linux seccomp — syscall filtering, BPF filters, SECCOMP_MODE_FILTER, SECBIT_NO_NEW_PRIVS, container seccomp profiles
tags:
  - linux
  - security
  - containers
---

# seccomp

seccomp (secure computing) is a Linux kernel feature that lets you **filter syscalls** a process can make. It's the mechanism that prevents containers from calling syscalls like `mount()` or `reboot()` — even with CAP_SYS_ADMIN, seccomp can block the underlying syscall.

## Modes

seccomp has three modes:

### seccomp mode 0 — Disabled
No filtering. Default for most processes.

### seccomp mode 1 (SECCOMP_MODE_STRICT)
Only allows `read()`, `write()`, `_exit()`, and `sigreturn()`. Anything else → `SIGKILL`.

```c
// Very restrictive — used in early Chrome sandbox
#include <linux/seccomp.h>
prctl(PR_SET_SECCOMP, SECCOMP_MODE_STRICT);
```

Used by Chrome's sandbox before BPF. No practical admin use today.

### seccomp mode 2 (SECCOMP_MODE_FILTER)
Allows **any BPF program** to decide whether to allow or block syscalls. This is what containers use.

```c
#include <linux/seccomp.h>
#include <linux/filter.h>

struct sock_filter filter[] = {
    // If syscall == mount, return SECCOMP_RET_KILL
    BPF_STMT(BPF_JMP+BPF_JEQ, SYS_mount, 0, SECCOMP_RET_KILL),
    // If syscall == reboot, return SECCOMP_RET_KILL
    BPF_STMT(BPF_JMP+BPF_JEQ, SYS_reboot, 0, SECCOMP_RET_KILL),
    // Otherwise, allow
    BPF_STMT(BPF_RET, SECCOMP_RET_ALLOW),
};

struct sock_fprog prog = {
    .len = (unsigned short)(sizeof(filter)/sizeof(filter[0])),
    .filter = filter,
};

prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog);
```

## BPF Filter Language (simplified)

BPF for seccomp filters is a tiny language with two statement types:

```c
BPF_STMT(opcode, argument, value)   // action
BPF_JMP(opcode, from, true, false) // jump (conditional)
```

### Return Values (Actions)

| Return            | Effect                                       |
|------------------|---------------------------------------------|
| `SECCOMP_RET_ALLOW` | Syscall proceeds normally                  |
| `SECCOMP_RET_KILL`  | Process killed immediately (no signal)     |
| `SECCOMP_RET_KILL_THREAD` | Kill the thread (not whole process) |
| `SECCOMP_RET_TRAP`   | Send SIGSYS to process                     |
| `SECCOMP_RET_ERRNO`  | Return this errno to userspace              |
| `SECCOMP_RET_TRACE`  | Trigger ptrace event (for debugger)        |
| `SECCOMP_RET_LOG`    | Allow but log to audit log                  |

### Reading Syscall Arguments

```c
BPF_STMT(BPF_LD+BPF_W+BPF_ABS, (offsetof(struct seccomp_data, nr))),  // syscall number
BPF_JMP(BPF_JMP+BPF_JEQ, SYS_mount, 0, 1),                           // if mount?
BPF_STMT(BPF_RET, SECCOMP_RET_KILL),                                   // kill it
```

The BPF program receives a `struct seccomp_data`:
```c
struct seccomp_data {
    int nr;                      // syscall number
    __u32 arch;                  // AUDIT_ARCH_* (x86_64, etc.)
    __u64 instruction_pointer;   // IP at time of syscall
    __u64 args[6];              // syscall arguments
};
```

## The Default Container Seccomp Profile

Docker ships a default seccomp profile that blocks ~44 syscalls considered dangerous for containers:

```json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    {"name": "mount", "action": "SCMP_ACT_ERRNO"},
    {"name": "umount2", "action": "SCMP_ACT_ERRNO"},
    {"name": "reboot", "action": "SCMP_ACT_ERRNO"},
    {"name": "syslog", "action": "SCMP_ACT_ERRNO"},
    {"name": "init_module", "action": "SCMP_ACT_ERRNO"},
    {"name": "delete_module", "action": "SCMP_ACT_ERRNO"},
    {"name": "ptrace", "action": "SCMP_ACT_ERRNO"},
    ...
  ]
}
```

Syscalls blocked include: `mount`, `umount`, `reboot`, `syslog`, `module` operations, `ptrace`, `perf_event_open`, `ioprio_set`, `mbind`, `set_mempolicy`, `migrate_pages`, `move_pages`, `vmsplice`.

## Container Runtime Flags

```bash
# Run Docker with no seccomp (--security-opt overrides)
docker run --security-opt seccomp=unconfined alpine

# Run with a custom profile
docker run --security-opt seccomp=profile.json myimage

# Kubernetes: Pod seccomp (alpha in 1.18, beta in 1.25+)
securityContext:
  seccompProfile:
    type: RuntimeDefault   # use container runtime default
    # or
    type: Localhost
    localhostProfile: profiles/my-profile.json
```

## `SECBIT_NO_NEW_PRIVS`

`no_new_privs` is a separate but related security bit. It prevents setuid binaries and file capabilities from granting new privileges:

```bash
# Set via prctl
prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);

# In /proc
cat /proc/self/status | grep NoNewPrivs
# NoNewPrivs: 0   (normal — can gain privileges)
# NoNewPrivs: 1   (secure — cannot gain new privileges)

# Via setpriv
setpriv --no-new-privs nginx
```

When `no_new_privileges` is set:
- `execve()` of setuid binaries won't change UID/GID
- `file capabilities` won't grant additional capabilities
- `SECBIT_NO_NEW_PRIVS` propagates to child processes

In Kubernetes, you set it via `securityContext.noNewPrivileges: true`.

## `seccomp` in Kubernetes Pod Spec

```yaml
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: profiles/audit.json   # logs instead of blocks
---
# The actual profile lives on the node at:
# /var/lib/kubelet/seccomp/profiles/audit.json
```

Node must have the profile. For `type: RuntimeDefault`, the runtime default profile is used (Docker's default, containerd's default, etc.).

## Inspecting Seccomp

```bash
# Check if a process has seccomp enabled
cat /proc/$$/status | grep Seccomp
# Seccomp: 0  (disabled)
# Seccomp: 1  (strict mode)
# Seccomp: 2  (filter/BPF mode)

# For a specific PID
cat /proc/1234/status | grep Seccomp

# See blocked syscalls in audit log
ausearch -- интервал --format=raw | aureport --file

# strace shows syscalls
strace -c -f nginx
# % time     seconds  usecs/call     calls    errors syscall
# ------ ----------- ----------- --------- --------- -------
#  56.29    0.000123           7     17658           read
#  23.81    0.000052           3     15000           write
#   8.33    0.000018          18      1000      100 getdents
# ...
```