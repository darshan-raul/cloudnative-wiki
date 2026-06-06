---
title: auditd
description: Linux auditd — audit subsystem, audit.rules, syscall auditing, file integrity, compliance, aureport
tags:
  - linux
  - security
---

# auditd

auditd is the Linux Audit subsystem daemon — it logs **system calls, file access, network events, and user actions** to `/var/log/audit/audit.log`. It's essential for security compliance (PCI-DSS, HIPAA, etc.), intrusion detection, and forensic investigation.

## How It Works

```
Application:  open("/etc/shadow", O_RDONLY)
              ↓
Kernel:       processes syscall
              ↓
auditd:       hook in kernel (via netlink)
              ↓
audit.log:    {"type":"SYSCALL","pid":1234,"syscall":open,...}
```

The kernel audit hooks fire on specific syscalls and events. auditd reads these and writes structured logs.

## Installing and Starting

```bash
# Install
apt install auditd      # Debian/Ubuntu
yum install audit       # RHEL/CentOS

# Start and enable
systemctl enable --now auditd

# Status
systemctl status auditd
auditd -s
```

## Rules

auditd is configured via rules. There are three types:

### File Watch Rules — Track File Access

```bash
# Watch /etc/shadow (password file — sensitive)
auditctl -w /etc/shadow -p wa -k shadow_access
#   -w  path
#   -p  permissions: r(read) w(write) a(append) x(execute)
#   -k  key name (for searching in logs)

# Watch /etc/passwd
auditctl -w /etc/passwd -p wa -k passwd_access

# Watch a directory
auditctl -w /etc/nginx/ -p wa -k nginx_config
```

### System Call Rules — Track Syscalls

```bash
# Track all unlink() calls (file deletions)
auditctl -a always,exit -F arch=b64 -S unlink -S unlinkat -k file_deletion

# Track connect() — network connections
auditctl -a always,exit -F arch=b64 -S connect -k network_connect

# Track privilege escalation (setuid binaries)
auditctl -a always,exit -F arch=b64 -S execve -F auid=0 -k privilege_escalation

# Track failed syscalls only
auditctl -a always,exit -F arch=b64 -S openat -F exit=-EPERM -k access_denied
```

### User/Session Rules — Track Login Events

```bash
# Track all failed login attempts
auditctl -w /var/log/faillog -p a -k failed_login

# Track sudo usage
auditctl -w /usr/bin/sudo -p x -k sudo_exec
```

## Making Rules Persistent

Rules set with `auditctl` are **lost on reboot**. To make permanent:

```bash
# Method 1: /etc/audit/rules.d/
cat /etc/audit/rules.d/audit.rules
# -w /etc/shadow -p wa -k shadow_access
# -a always,exit -F arch=b64 -S unlink -S unlinkat -k file_deletion

# Then:
augenrules --load
systemctl restart auditd

# Method 2: direct edit of /etc/audit/audit.rules
auditctl -R /etc/audit/audit.rules
```

## Viewing Logs

### aureport — Summary Reports

```bash
# Overall summary
aureport --summary

# Syscall summary
aureport --syscall

# File summary
aureport --file

# User summary
aureport --user

# Failed events only
aureport --failed

# Executable summary
aureport --executable

# Recent events (last hour)
aureport --start recent --numeric --summary
```

### ausearch — Search Logs

```bash
# Search by key
ausearch -k shadow_access

# Search by syscall
ausearch -sc unlink

# Search by file
ausearch -f /etc/shadow

# Search by user (by UID)
ausearch -ui 1000

# Search by result (failed)
ausearch --result failed

# Search by time
ausearch --start 09:00 --end 10:00 --today
ausearch --start $(date -d '1 hour ago' +%x_%H:%M:%S)

# Search and format
ausearch -k shadow_access --raw | aureport --file
```

### tail -f the log

```bash
tail -f /var/log/audit/audit.log
```

## Log Format

```bash
# Raw audit.log entry
type=SYSCALL msg=audit(1717600000.123:456): arch=c000003e syscall=257 success=yes exit=3 a0="0000000000000004" a1=7ffd12340000 a2=0 a3=0 items=1 ppid=1234 pid=5678 auid=1000 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts0 ses=3 comm="nginx" exe="/usr/sbin/nginx" key="shadow_access"
type=EXECVE msg=audit(1717600000.123:456): argc=3 a0="nginx" a1="-s" a2="reload"
type=PATH msg=audit(1717600000.123:456): item=0 name="/etc/shadow" inode=65432 dev=08:01 mode=0100644 ouid=0 ogid=0 rdev=00:00 nametype=NORMAL
```

Key fields:
- `type`: SYSCALL (main event), PATH (file), EXECVE (exec args), USER_AUTH (authentication)
- `arch=c000003e`: x86_64 syscall
- `syscall=257`: openat (syscall number)
- `key="shadow_access"`: searchable tag
- `auid`: original user UID (important for tracking sudo/privilege)

## Common Security Rules

```bash
# Track all writes to /etc/shadow (password file changes)
auditctl -w /etc/shadow -p wa -k password_file_changes

# Track sudo usage
auditctl -w /usr/bin/sudo -p x -k sudo_exec

# Track SSH key access
auditctl -w /root/.ssh -p rwxa -k ssh_keys

# Track cron usage
auditctl -w /usr/bin/crontab -p x -k cron_exec
auditctl -w /var/spool/cron -p rwxa -k cron_spool

# Track all network connections (noisy!)
auditctl -a always,exit -F arch=b64 -S connect -S bind -S accept -k network_activity

# Track module loading
auditctl -w /usr/sbin/modprobe -p x -k module_load
auditctl -w /sbin/insmod -p x -k module_load
```

## Practical Use Cases

### Find who modified a file

```bash
# Set the watch first
auditctl -w /etc/nginx/nginx.conf -p wa -k nginx_config

# Later, search
ausearch -k nginx_config --format raw | aureport --file --summary
ausearch -k nginx_config | head -20
```

### Find failed access attempts

```bash
ausearch --result failed --success no | head -20
aureport --failed --summary
```

### Track privilege escalation

```bash
# Watch for execve by non-root
auditctl -a always,exit -F arch=b64 -S execve -F 'auid!=-1' -F 'uid!=0' -k nonroot_exec

# Then search
ausearch -k nonroot_exec
```

## Troubleshooting

```bash
# auditd not starting?
journalctl -u auditd
cat /var/log/audit/audit.log  # may be empty if rules fail

# Check if audit is working
auditctl -s
# enabled 1
# failure 0
# pid 1234

# Check loaded rules
auditctl -l

# Clear all rules
auditctl -F

# Debug rule loading
augenrules --load -d  # verbose
```

## rate Limiting

auditd can be throttled to prevent log flooding:

```bash
# /etc/audit/auditd.conf
max_log_file = 8              # MB per log file
max_log_file_action = ROTATE   # rotate when full
num_logs = 5                 # number of logs to keep
space_left = 75              # MB free space left
space_left_action = SYSLOG   # or EMAIL, SUSPEND, IGNORE
admin_space_left = 50         # MB (critical)
admin_space_left_action = SUSPEND
disk_full_action = SUSPEND
disk_error_action = SUSPEND
```