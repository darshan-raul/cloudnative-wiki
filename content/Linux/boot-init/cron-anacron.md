---
title: Cron and Anacron
description: Linux cron and anacron — scheduled tasks, crontab syntax, @hourly/@daily/@reboot, anacron for non-always-on systems
tags:
  - linux
  - boot-init
---

# Cron and Anacron

cron and anacron are scheduled task systems. **cron** runs tasks at specific times on always-on systems. **anacron** runs missed tasks on systems that aren't on 24/7.

## cron — Time-Based Scheduling

cron runs as a daemon (`crond`) that wakes up every minute, reads schedule files, and executes matching jobs.

### Crontab Format

```
┌───────────── minute (0-59)
│ ┌───────────── hour (0-23)
│ │ ┌───────────── day of month (1-31)
│ │ │ ┌───────────── month (1-12)
│ │ │ │ ┌───────────── day of week (0-7, 0 and 7 = Sunday)
│ │ │ │ │
* * * * * command
```

| Field     | Values      | Specials          |
|-----------|------------|-------------------|
| minute    | 0-59       | `*` = any, `*/n` = every n  |
| hour      | 0-23       | `*` = any, `*/2` = every 2h |
| day       | 1-31       | `*` = any                   |
| month     | 1-12       | `*` = any                   |
| weekday   | 0-7        | `*` = any, 0,7=Sunday        |

### Examples

```bash
# Every minute
* * * * * /usr/local/bin/backup.sh

# Every hour at minute 15
15 * * * * /usr/local/bin/check-alerts.sh

# Every day at 3:00 AM
0 3 * * * /usr/local/bin/daily-report.sh

# Every Monday at 9:00 AM
0 9 * * 1 /usr/local/bin/weekly-review.sh

# Every 15 minutes
*/15 * * * * /usr/local/bin/monitor.sh

# 2:30 AM on weekdays
30 2 * * 1-5 /usr/local/bin/weekday-task.sh

# Every 6 hours
0 */6 * * * /usr/local/bin/every-six-hours.sh

# Midnight on the 1st of every month
0 0 1 * * /usr/local/bin/monthly.sh

# Run once at boot (per user crontab — systemd timers preferred)
/reboot /usr/local/bin/startup-task.sh
```

### Managing Crontabs

```bash
# Edit current user's crontab
crontab -e

# List current user's crontab
crontab -l

# Remove current user's crontab
crontab -r

# Edit another user's crontab (requires root)
crontab -u darshan -e
crontab -u nginx -l

# Cron log (depends on distro)
#   Debian/Ubuntu: /var/log/syslog (grep CRON)
#   CentOS/RHEL: /var/log/cron
journalctl -u cron
journalctl -u crond
```

### System crontab (root's crontab, /etc/crontab)

```bash
cat /etc/crontab
# SHELL=/bin/bash
# PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# MAILTO=root

# minute hour day month dow user  command
  0      3    *   *    *   root  /usr/local/bin/backup.sh
```

System crontab includes a `user` field before the command.

### cron.d and cron.daily/hourly

```bash
# /etc/cron.d/ — for package-installed cron jobs
ls /etc/cron.d/
# This is where packages (e.g., logrotate, apt) put their cron entries

# /etc/cron.hourly/, /etc/cron.daily/, /etc/cron.weekly/, /etc/cron.monthly/
# run-parts executes scripts in these directories
ls /etc/cron.daily/
# logrotate  apt-compat  man-db  ...
```

## @reboot — Boot-Time Jobs

```bash
# In any crontab:
@reboot /usr/local/bin/startup.sh
@reboot sleep 60 && /usr/local/bin/delayed-start.sh
```

Note: `@reboot` runs after cron daemon starts (usually ~30s after boot). For more precise timing, use systemd timers with `AccuracySec=1us`.

## Anacron — For Non-Always-On Systems

cron misses jobs if the system is off. **anacron** tracks when jobs last ran and executes any that are overdue:

```bash
# Anacron config
cat /etc/anacrontab

# Format: period delay identifier command
#   period:    how often to run (in days, or @daily/@weekly/@monthly)
#   delay:     minutes to wait after boot before running
#   identifier: unique name (for logging)
#   command:    what to run

@daily    10  cron.daily   /usr/bin/logger "Daily job"
@weekly   20  cron.weekly  /usr/bin/logger "Weekly job"
@monthly  30  cron.monthly /usr/bin/logger "Monthly job"
```

**Example**: If `cron.daily` is scheduled to run but the machine was off:
1. Machine boots on Tuesday
2. anacron sees `/etc/cron.daily` wasn't run since Friday
3. Waits 10 minutes (the delay field), then runs it

### Anacron Timestamps

```bash
# Anacron stores last-run timestamps here:
ls /var/spool/anacron/
# cron.daily  cron.weekly  cron.monthly

# View:
cat /var/spool/anacron/cron.daily
# 20250606   ← last ran on this date
```

## systemd Timers — Modern Alternative

systemd timers are more powerful than cron and are preferred on modern systems:

```ini
# /etc/systemd/system/mytask.timer
[Unit]
Description=Run mytask every day at 3am

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true        # run missed jobs if system was off
RandomizedDelaySec=300 # add up to 5min jitter
```

```ini
# /etc/systemd/system/mytask.service
[Unit]
Description=My Scheduled Task

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mytask.sh
```

```bash
systemctl enable --now mytask.timer
systemctl list-timers
```

### cron vs systemd Timers

| Feature             | cron          | systemd timers              |
|--------------------|---------------|----------------------------|
| Resolution         | minute        | second (or better)         |
| Boot-time jobs     | @reboot       | OnBootSec=                 |
| Random jitter      | no            | RandomizedDelaySec=        |
| Manual run         | run-parts     | systemctl start service    |
| Dependencies       | separate      | PartOf=, After=            |
| On-demand          | no            | yes (Path=, Socket=)       |
| Persistence        | file          | unit files                 |
| Syslog             | syslog        | journald                   |

## Gotchas

```bash
# SHELL is NOT /bin/bash by default in crontab — it's /bin/sh
# So: cron uses /bin/sh, not bash
# Variables work differently (no arrays, no local, etc.)

# Workaround: explicitly call bash or source bash profile
0 3 * * * /bin/bash -c 'source ~/.bashrc && /usr/local/bin/mytask.sh'

# PATH is minimal in cron
# Always use absolute paths in crontab
0 3 * * * /usr/local/bin/backup.sh  # YES
0 3 * * * backup.sh                 # NO (might not be found)

# % has special meaning in crontab (newline in command output)
# Escape it:
0 3 * * * /usr/local/bin/report.sh "date: %Y-%m-%d"   # WRONG
0 3 * * * /usr/local/bin/report.sh "date: $(date +\%Y-\%m-\%d)"  # YES

# Output goes to email by default (MAILTO=)
# Disable output: redirect to /dev/null
0 3 * * * /usr/local/bin/mytask.sh > /dev/null 2>&1

# MAILTO="" in crontab suppresses email
```