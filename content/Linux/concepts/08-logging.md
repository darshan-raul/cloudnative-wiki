---
title: "08 — Logging"
description: Linux logging — journalctl, /var/log, log levels, syslog, reading logs, log rotation
tags:
  - linux
  - concepts
---

# 08 — Logging

Linux records everything: boot messages, service output, authentication attempts, kernel events. Finding and reading logs is a core sysadmin skill.

## Where Logs Live

```bash
# The main log directory:
ls /var/log/

# The big three:
/var/log/syslog       # Debian/Ubuntu: all syslog messages
/var/log/messages     # RHEL/CentOS: all syslog messages
/var/log/audit/audit.log  # auditd: syscall and security events

# Authentication:
/var/log/auth.log     # Debian/Ubuntu: login, sudo, SSH
/var/log/secure       # RHEL/CentOS: same

# Application logs:
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/cron
/var/log/dpkg.log     # apt/dpkg package changes
/var/log/pacman.log   # Arch/Manjaro pacman operations
```

## journalctl — The Modern Log Tool

Most modern distros use **systemd-journald**, which stores logs in a binary format. Use `journalctl` to query them.

```bash
# All logs (paginated):
sudo journalctl

# Follow new entries (like tail -f):
sudo journalctl -f

# View specific service logs:
sudo journalctl -u nginx
sudo journalctl -u sshd
sudo journalctl -u nginx -u postgresql  # both

# Last N lines:
sudo journalctl -n 50

# Since a time:
sudo journalctl --since "1 hour ago"
sudo journalctl --since "2025-06-06 10:00"
sudo journalctl --since "yesterday"
sudo journalctl --since "2025-06-06 10:00:00" --until "2025-06-06 11:00:00"

# Since last boot:
sudo journalctl -b
sudo journalctl -b -1        # previous boot
sudo journalctl -b 2        # boot #2 ago

# By priority (0=emerg to 7=debug):
sudo journalctl -p err       # errors only
sudo journalctl -p warning
sudo journalctl -p info
sudo journalctl -p debug

# Show kernel messages:
sudo journalctl -k
```

### journalctl Tricks

```bash
# JSON output (for scripting):
sudo journalctl -u nginx -o json

# Short format:
sudo journalctl -o short

# Show disk usage:
sudo journalctl --disk-usage

# Vacuum old logs (keep last 500MB):
sudo journalctl --vacuum-size=500M

# Keep last 7 days:
sudo journalctl --vacuum-time=7d

# Full-text search:
sudo journalctl --since "1 hour ago" | grep -i error

# PIDs and units:
sudo journalctl _PID=1234
sudo journalctl _UID=1000
sudo journalctl _SYSTEMD_UNIT=nginx.service
```

## Log Levels

Syslog and journald use the same priority levels:

| Level | Name | When to use |
|-------|------|-------------|
| 0 | emerg | System unusable |
| 1 | alert | Must act immediately |
| 2 | crit | Critical condition |
| 3 | err | Non-critical error |
| 4 | warning | Warning |
| 5 | notice | Normal but significant |
| 6 | info | Informational |
| 7 | debug | Debug messages |

## Reading /var/log Files

```bash
# Last entries in a log:
tail /var/log/auth.log
tail -f /var/log/auth.log     # follow

# All SSH connections:
grep sshd /var/log/auth.log

# Failed login attempts:
grep "Failed password" /var/log/auth.log
grep "Failed password" /var/log/secure

# sudo usage:
grep sudo /var/log/auth.log

# Today's entries only:
grep "$(date +'%b %d')" /var/log/auth.log
```

## Binary Login Logs

Not plain text — use dedicated tools:

```bash
# Who logged in (last):
last
last darshan           # specific user
last reboot            # boot history

# Last login per user:
lastlog

# Failed login attempts:
sudo lastb
sudo lastb | grep darshan

# Failed login counter:
faillog
faillog -u darshan    # specific user
```

## Log Rotation

Logs grow indefinitely. **logrotate** truncates and compresses old logs automatically.

```bash
# How it works:
# /var/log/nginx/access.log
#   → rotated daily
#   → renamed access.log.1
#   → new access.log created
#   → after 14 rotations, oldest is deleted
#   → old logs gzip'd: access.log.2.gz

# Check rotation config:
cat /etc/logrotate.conf
cat /etc/logrotate.d/nginx
```

### Logrotate Directive

```ini
# /etc/logrotate.d/nginx
/var/log/nginx/*.log {
    daily              # rotate daily
    rotate 14          # keep 14 rotated files
    compress          # gzip old logs
    delaycompress     # keep last one uncompressed
    notifempty       # don't rotate empty logs
    create 0640 www-data adm  # mode owner group for new log
    sharedscripts    # postrotate runs once after all logs
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid)
    endscript
}
```

## Quick Reference

```bash
# journalctl (modern systems)
sudo journalctl
sudo journalctl -u nginx
sudo journalctl -f
sudo journalctl --since "1 hour ago"
sudo journalctl -b
sudo journalctl -p err

# /var/log
tail /var/log/syslog
grep sshd /var/log/auth.log

# Binary logs
last
lastlog
sudo lastb

# logrotate
sudo logrotate -f /etc/logrotate.d/nginx  # force rotation
sudo logrotate -d /etc/logrotate.conf    # dry run
```