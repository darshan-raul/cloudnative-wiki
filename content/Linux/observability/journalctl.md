---
title: journalctl
description: journalctl — querying systemd journal, filtering by unit, priority, boot, time, facility, JSON output, log management
tags:
  - linux
  - observability
  - logging
---

# journalctl

`journalctl` queries the systemd journal — the structured binary log that systemd maintains for all system events. It's the primary log tool on modern Linux distros.

## Core Queries

```bash
# All logs (paginated, like less)
journalctl

# Follow in real-time (tail -f equivalent)
journalctl -f

# Last 100 lines
journalctl -n 100

# Show from boot messages onwards
journalctl -b
journalctl -b -1          # previous boot
journalctl -b 2           # boot ID 2

# Since/until time
journalctl --since "1 hour ago"
journalctl --since "2025-06-06 10:00:00"
journalctl --since "1 day ago"
journalctl --since "-2 hours" --until "-1 hour"
journalctl --since today
journalctl --since yesterday
```

## Filtering

```bash
# By unit/service
journalctl -u nginx.service
journalctl -u nginx.service -u postgresql.service   # multiple units
journalctl -u nginx.service --since "10 minutes ago"

# By user session
journalctl --user -u myapp.service

# By PID
journalctl _PID=1234

# By UID/GID
journalctl _UID=0
journalctl _GID=1000

# By executable
journalctl /usr/sbin/sshd
journalctl /usr/bin/dockerd

# By kernel device
journalctl _KERNEL_DEVICE=+usb:usb1

# By priority (0=emerg, 7=debug)
journalctl -p err
journalctl -p warning
journalctl -p info
journalctl -p debug
journalctl -p 0..3        # emerg, alert, crit, err

# By facility (auth, authpriv, cron, daemon, kern, mail, syslog, user)
journalctl SYSLOG_FACILITY=3     # daemon
journalctl SYSLOG_FACILITY=10    # mail (standard syslog)
journalctl _TRANSPORT=kernel
journalctl _TRANSPORT=audit
journalctl _TRANSPORT=syslog

# By message content (grep equivalent)
journalctl -g "error"
journalctl -g "SSH"
journalctl --grep "connection refused"
```

## Output Formats

```bash
# Default (human-readable, multi-line)
journalctl

# Short format (syslog-style)
journalctl -o short

# Short-iso (ISO timestamps)
journalctl -o short-iso

# Short-precise (precise timestamps with microseconds)
journalctl -o short-precise

# Verbose (all fields)
journalctl -o verbose

# JSON (one object per line — great for grep/jq)
journalctl -o json

# JSON-pretty
journalctl -o json-pretty

# Export to tar + gzip (for sharing/sending)
journalctl --no-pager -o export | gzip > logs.tar.gz

# Catalog (show message descriptions for unknown errors)
journalctl -o catalog
```

## Useful Fields

```bash
# Show all available fields for recent entries
journalctl -F _SYSTEMD_UNIT
journalctl -F _TRANSPORT
journalctl -F PRIORITY
journalctl -F _UID
journalctl -F _GID
journalctl -F _CMDLINE
journalctl -F _EXE

# See what boot IDs exist
journalctl --list-boots
```

## Boot ID and System Journal

```bash
# List all boots in journal
journalctl --list-boots
# IDX  BTIMESTAMP              UTOR  LOCAL                REMOTE
#  -1  Mon 2025-06-02 00:00:00  2h   system boot          -
#   0  Wed 2025-06-04 00:00:00  1h   system boot          -

# Current boot ID
journalctl --boot=0
journalctl --boot=0 --list-boots   # show which is boot 0

# System journal only (not /var/log/journal/)
# By default journalctl reads both /run/log/journal and /var/log/journal
journalctl -D /run/log/journal

# Show disk usage of journal
journalctl --disk-usage
journalctl --vacuum-size=500M     # keep last 500M
journalctl --vacuum-time=7d       # keep last 7 days
journalctl --vacuum-files=5       # keep last 5 files
```

## Real-World Patterns

```bash
# Watch nginx errors in real-time
journalctl -u nginx -f -p err

# Find all errors for a service in the last hour
journalctl -u myapp -p err --since "1 hour ago"

# Find process restarts (EXIT_CODE contains code)
journalctl -u nginx _SYSTEMD_UNIT=nginx.service | grep "Started nginx"

# Follow boot from initramfs
journalctl -f

# See kernel ring buffer (dmesg equivalent)
journalctl -k
# or
journalctl -k -b -1           # previous boot kernel log

# See user session logs
journalctl --user
journalctl --user -u myapp --follow

# Find failed service starts
journalctl -p err --no-pager | grep -i "failed\|error"

# All logs from the last reboot
journalctl -b 0 --no-pager

# Follow SSH login attempts
journalctl -f _TRANSPORT=syslog SYSLOG_FACILITY=auth
# or equivalently:
journalctl -f SYSLOG_IDENTIFIER=sshd
```

## Log Management

### journald.conf

```bash
# /etc/systemd/journald.conf
[Journal]
Storage=persistent          # persistent = /var/log/journal (survives reboot)
                          # volatile = /run/log/journal (cleared on reboot)
                          # auto = /var/log/journal if exists, else /run
                          # none = don't store logs (only transient)
Seal=yes                   # seal journal with symmetric key (detect tampering)
SplitMode=uid             # split by UID (user sees own logs)
Compress=yes              # compress old entries
RateLimitInterval=30s     # rate limit per unit
RateLimitBurst=1000      # allow 1000 messages per interval before throttling
MaxRetentionSec=30day     # max age
MaxFileSec=1week          # rotate file every week
MaxFiles=5                # max 5 files
SystemMaxUse=500M         # max disk usage for system journal
SystemKeepFree=1G         # keep at least 1G free
SystemMaxFileSize=50M     # max size per file
MaxLevelStore=debug       # max level to store
MaxLevelSyslog=debug      # max level for syslog transport
MaxLevelKMsg=notice       # max level for kernel messages
MaxLevelConsole=info      # max level for console
MaxLevelWall=emerg        # max level for wall messages
```

### Rotating and Cleaning

```bash
# Check current usage
journalctl --disk-usage
# Used: 423.4M on 4.0G

# Vacuum old logs (reduce to last 3 days)
journalctl --vacuum-time=3d

# Vacuum to keep under 200MB
journalctl --vacuum-size=200M

# Vacuum to keep only 3 files
journalctl --vacuum-files=3

# This doesn't delete the most recent entries — it cleans from oldest

# Force immediate rotation
killall -USR1 systemd-journald
```

## Combining with Other Tools

```bash
# Count error frequency by unit
journalctl -p err -o json-pretty | jq -r '._SYSTEMD_UNIT' | sort | uniq -c | sort -rn

# Find top error messages
journalctl -p err -o json | jq -r '.MESSAGE' | sort | uniq -c | sort -rn | head -20

# Watch for SSH brute force
journalctl -f SYSLOG_IDENTIFIER=sshd | grep -i "invalid\|failed\|BREAK"

# Performance: measure service startup time
journalctl -u myapp -o short-precise | grep "Started\|Stopping"
```

## Quick Reference

```bash
# Basics
journalctl               # all logs
journalctl -f           # follow
journalctl -n 50        # last 50 lines

# Time
journalctl --since today
journalctl --since "1 hour ago"
journalctl --since "2025-06-06 00:00" --until "2025-06-06 23:59"

# Units
journalctl -u nginx
journalctl -u nginx -u postgresql

# Priority
journalctl -p err
journalctl -p warning..err

# Boot
journalctl -b           # this boot
journalctl -b -1        # previous boot
journalctl --list-boots

# Output
journalctl -o short     # syslog-style
journalctl -o json
journalctl -o verbose

# Maintenance
journalctl --disk-usage
journalctl --vacuum-size=500M
journalctl --vacuum-time=7d

# Fields
journalctl -F _SYSTEMD_UNIT
journalctl -F _UID
```