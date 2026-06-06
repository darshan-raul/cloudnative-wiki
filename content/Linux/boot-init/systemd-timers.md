---
title: systemd Timers
description: systemd timers — calendar events, monotonic timers, Persistent, RandomizedDelaySec, socket activation, cron vs timers
tags:
  - linux
  - boot-init
  - systemd
---

# systemd Timers

systemd timers are systemd's answer to cron. They can trigger units based on **calendar events** (like cron) or **monotonic timers** (after boot, after a previous event). They offer persistent execution, runtime dependencies, and structured logging — advantages over traditional cron.

## Basic Structure

A timer unit (`*.timer`) activates a corresponding service unit (`*.service`):

```
/etc/systemd/system/
  myapp.timer
  myapp.service
```

The service does the work. The timer triggers it.

## Calendar Events (cron-style)

Calendar events use a rich cron-like expression:

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Run backup every day at 3am

[Timer]
# Calendar event: daily at 03:00
OnCalendar=*-*-* 03:00:00

# Persistent=true means if the system was off at the scheduled time,
# the service runs immediately when the system starts
Persistent=true

[Install]
WantedBy=timers.target
```

### OnCalendar Syntax

```ini
# Specific time:
OnCalendar=2025-06-06 14:00:00      # specific date and time
OnCalendar=*-*-* 14:00:00           # daily at 14:00
OnCalendar=*-01,06,12-01 00:00:00  # Jan/Jun/Dec 1st at midnight

# Shorthand:
OnCalendar=daily
OnCalendar=hourly
OnCalendar=minutely
OnCalendar=weekly
OnCalendar=monthly
OnCalendar=yearly
OnCalendar=*:0/15                     # every 15 minutes (*:00, *:15, *:30, *:45)

# Weekdays:
OnCalendar=Mon..Fri *-*-* 09:00:00 # Weekdays at 9am
OnCalendar=Sat,Sun *-*-* 10:00:00  # Weekends at 10am

# Ranges:
OnCalendar=*-*-01..07 10:00:00     # 1st week of every month at 10am
OnCalendar=*-01..03-01 00:00:00   # Q1 start at midnight

# Examples:
OnCalendar=*-*-* 00:00:00          # daily at midnight
OnCalendar=*-01-01 00:00:00        # Jan 1st at midnight
OnCalendar=*-02-14 12:00:00        # Valentine's day at noon
OnCalendar=hourly                   # :00 of every hour
OnCalendar=*:0/5                    # every 5 minutes
```

## Monotonic Timers

Monotonic timers fire relative to a starting event — not an absolute clock time:

```ini
[Timer]
# 30 seconds after boot:
OnBootSec=30s

# 5 minutes after boot:
OnBootSec=5min

# 1 hour after boot:
OnBootSec=1h

# 5 minutes after the service last ran:
OnUnitActiveSec=5min

# 10 minutes after the timer was activated:
OnUnitInactiveSec=10min

# Combined: 2 minutes after boot AND every hour after last run:
OnBootSec=2min
OnUnitActiveSec=1h
```

## The Service Unit

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Run backup
Requires=backup.timer   # (optional, ties lifecycle)

[Service]
Type=oneshot           # run once and exit (like cron jobs)
ExecStart=/usr/local/bin/run-backup.sh

# Or Type=simple if the script runs in foreground

# Resource limits (optional):
MemoryMax=512M
CPUQuota=50%
```

## RandomizedDelaySec (Jitter)

Prevent all timers from firing at the same instant (like midnight on Jan 1st):

```ini
[Timer]
OnCalendar=hourly
RandomizedDelaySec=5min    # delay up to 5 minutes randomly
# If OnCalendar=*-*-* 00:00:00, fires between 00:00 and 00:05
```

## Persistent and Boots

```ini
[Timer]
# Persistent is crucial for catching up after missed runs:
Persistent=true
OnCalendar=daily

# If system was off for 3 days at 3am, service runs immediately on boot
# Without Persistent=true, it waits until next 3am
```

## AccuracySec

Timers are not guaranteed to fire at the exact scheduled time. By default, systemd allows up to 1 minute of slack:

```ini
[Timer]
# AccuracySec: how close to the scheduled time the timer must fire
# Default is 1min. Lower values = more precise = more CPU wake-ups.
AccuracySec=1min    # default
AccuracySec=1us     # as precise as possible (not recommended for battery)
AccuracySec=1h      # allow up to 1 hour slack (power saving)
```

## Managing Timers

```bash
# Start/stop
systemctl start backup.timer
systemctl stop backup.timer

# Enable (start at boot):
systemctl enable backup.timer

# Status (shows next run time):
systemctl status backup.timer
systemctl list-timers
systemctl list-timers --all

# See last 5 timer executions:
systemctl list-timers --all --no-pager | head -20

# Manually trigger now:
systemctl start backup.service

# View logs:
journalctl -u backup.service
journalctl -u backup.timer
```

## Calendar Event Examples

```ini
# Every 5 minutes:
OnCalendar=*:0/5

# Every 15 minutes:
OnCalendar=*:0/15

# Every hour:
OnCalendar=hourly     # same as *-*-* *:00:00

# Daily at 3am:
OnCalendar=*-*-* 03:00:00

# Weekly Monday at 9am:
OnCalendar=Mon *-*-* 09:00:00

# Monthly on the 1st at midnight:
OnCalendar=*-*-01 00:00:00

# Quarterly:
OnCalendar=*-01,04,07,10-01 00:00:00

# Yearly on Jan 1st:
OnCalendar=*-01-01 00:00:00

# Every weekday at 6pm:
OnCalendar=Mon..Fri *-*-* 18:00:00

# First Monday of every month:
OnCalendar=*-*-01..07 09:00:00

# Every 30 seconds (very precise, not recommended for battery):
OnCalendar=*:0/0/30
```

## cron vs systemd Timers

| Feature | cron | systemd timers |
|---------|------|----------------|
| Persistence | Not automatic | `Persistent=true` catches up |
| Logs | syslog | journald (structured) |
| Dependencies | Limited | Full dependency graph |
| Randomized delay | No | `RandomizedDelaySec` |
| Calendar expressions | Standard only | Rich + shorthand |
| Manual trigger | `run-parts` | `systemctl start` |
| Status | `crontab -l` | `systemctl list-timers` |
| User-level timers | `crontab -e` | `systemctl --user` |

## User-Level Timers

```bash
# Create a timer as a normal user:
mkdir -p ~/.config/systemd/user/
# ~/.config/systemd/user/myapp.timer
# ~/.config/systemd/user/myapp.service

systemctl --user enable --now myapp.timer
systemctl --user list-timers

# Enable lingering (so timer runs even without user logged in):
loginctl enable-linger $USER
```

## Multiple Timers (Shorthand)

You can define multiple timers in one unit:

```ini
[Timer]
OnCalendar=*-*-* 06:00:00
OnCalendar=*-*-* 18:00:00
```

Or use named timer units with a shared pattern:

```ini
# /etc/systemd/system/hourly-checks.timer
[Timer]
OnCalendar=*:0/15
RandomizedDelaySec=60

[Install]
WantedBy=timers.target
```

## Real-World: fstrim Timer

systemd ships with a fstrim timer for SSDs:

```bash
cat /usr/lib/systemd/system/fstrim.timer
# [Unit]
# Description=Discard unused blocks once a week
# [Timer]
# OnCalendar=weekly
# Persistent=true
# RandomizedDelaySec=1h
# [Install]
# WantedBy=timers.target
```

## Troubleshooting

```bash
# Timer not firing?
systemctl status backup.timer
systemctl status backup.service

# See next/previous run times:
systemctl list-timers backup.timer

# View the timer definition:
systemctl cat backup.timer

# Check journal:
journalctl -u backup.service -n 20

# If service failed to start, check:
journalctl -xe

# Ensure timer is enabled:
systemctl is-enabled backup.timer
systemctl is-active backup.timer
```
