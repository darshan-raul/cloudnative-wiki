---
title: Log Management
description: Linux log management — /var/log structure, logrotate, rsyslog, syslog, lastlog, wtmp, btmp, faillog, centralized logging
tags:
  - linux
  - observability
  - logging
---

# Log Management

Linux maintains structured logs across multiple locations. Understanding `/var/log/`, logrotate, syslog facilities, and the binary login logs is essential for both debugging and security auditing.

## /var/log/ Structure

```bash
# Core system logs
/var/log/syslog         # Debian/Ubuntu: all syslog messages
/var/log/messages       # RHEL/CentOS: all syslog messages
/var/log/audit/audit.log  # auditd events (SELinux, syscall logging)
/var/log/kern.log       # kernel messages (Debian/Ubuntu)
/var/log/dmesg          # boot messages (older systems)
/var/log/boot.log       # boot process messages

# Authentication and authorization
/var/log/auth.log       # Debian/Ubuntu: auth, sudo, SSH
/var/log/secure         # RHEL/CentOS: auth, sudo, SSH
/var/log/faillog        # failed login attempts (binary)
/var/log/lastlog        # last successful login per user (binary)
/var/log/wtmp           # login/logout history (binary)
/var/log/btmp           # failed login attempts (binary)

# Application logs
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/apache2/access.log
/var/log/dockerdaemon.log
/var/log/kubelet.log
/var/log/mysql/error.log
/var/log/postgresql/log

# Package management
/var/log/dpkg.log       # apt/dpkg package changes
/var/log/pacman.log     # Arch/Manjaro pacman operations
/var/log/yum.log        # RHEL yum transactions

# Kernel and hardware
/var/log/dmesg          # kernel ring buffer at boot
/var/log/kmsg           # kernel message buffer (writable)
```

## Binary Login Logs

These are binary formats — use the dedicated commands to read them.

### lastlog — Last Login per User

```bash
lastlog
# Username         Port     From             Latest
# root             pts/0    192.168.1.10    Sat Jun  6 10:00:00 +0000 2025
# darshan          pts/1    192.168.1.15    Fri Jun  5 22:30:00 +0000 2025
# nginx                               **Never logged in**

# Search for specific user:
lastlog -u darshan

# Show entries since a date:
lastlog --since $(date -d '2025-06-01' +%a\ %b\ %d\ %H:%M:%S\ %Y)
```

### wtmp — Login/Logout History

```bash
# Read wtmp
last
# darshan  pts/0    192.168.1.15    Sat Jun  6 10:00 - 11:00 (01:00)
# reboot   boot     5.15.0-generic   Sat Jun  6 09:55 - 11:30 (01:35)

# Show only runlevel changes:
last | grep runlevel
last reboot

# Show last 20 logins:
last -20

# Show since a date:
last --since "2025-06-01"

# Parse with Python/awk:
last | awk '{print $1, $3, $4, $5, $6, $7, $8, $9, $10}'
```

### btmp — Failed Login Attempts

```bash
# Read btmp
lastb
# darshan  ssh:notty    192.168.1.99    Sat Jun  6 10:15 - 10:15 (00:00)

# Show failed SSH attempts:
lastb | grep sshd

# Count failed logins per user:
lastb | awk '{print $1}' | sort | uniq -c | sort -rn | head -10

# Show failed logins today:
lastb --since today
```

### faillog — Failed Login Counter

```bash
# Show current failed login counters per user:
faillog
# Login       Failures  Latest
# root              0
# darshan           3   Sat Jun  6 10:15:22 +0000 2025 on ssh:notty

# Show only users with failures:
faillog -a | grep -v "             0$"

# Set lockout threshold (done in PAM, not faillog directly)
# faillog reads the counter set by pam_faillock
```

## logrotate

logrotate rotates, compresses, and removes old log files automatically.

### How It Works

```
/var/log/nginx/access.log
  → rotated daily (or when size threshold hit)
  → renamed to /var/log/nginx/access.log.1
  → new access.log created
  → after 14 rotations, oldest is deleted
  → old logs are gzip'd: access.log.2.gz
```

### Configuration

```bash
# Main config:
/etc/logrotate.conf        # global defaults
# Included configs:
/etc/logrotate.d/*         # per-service configs
```

### Standard logrotate.conf

```bash
# /etc/logrotate.conf
# Global settings
rotate 4           # keep 4 rotated files
weekly            # rotate weekly (or 'daily', 'monthly')
create            # create new empty log after rotation
compress          # gzip rotated logs
dateext           # use date suffix instead of .1, .2
dateformat -%Y%m%d-%s  # date format for dateext
maxage 365        # delete logs older than 365 days
missingok          # don't error if log file is missing
notifempty         # don't rotate if empty
mailarchive        # email logs before deletion (usually disabled)
# mail user@example.com
maxsize 100M       # rotate even if weekly, if file > 100M
size 100M          # rotate when file > 100M (overrides daily/weekly)

# Include service-specific configs:
include /etc/logrotate.d/
```

### Per-Service Example: nginx

```bash
# /etc/logrotate.d/nginx
/var/log/nginx/*.log {
    daily              # rotate daily
    missingok           # don't error if no log
    rotate 14           # keep 14 rotated files
    compress            # gzip old logs
    delaycompress       # keep last one uncompressed (for some programs that hold it open)
    notifempty          # don't rotate empty logs
    create 0640 www-data adm   # mode owner group for new log
    sharedscripts       # run postrotate script only once (not per log)
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid)
    endscript
}
```

### Per-Service Example: custom application

```bash
# /etc/logrotate.d/myapp
/var/log/myapp/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 myapp myapp
    maxsize 50M         # rotate if > 50M even if not daily
    olddir /var/log/myapp/archive  # move old logs to archive dir
    missingok
    postrotate
        systemctl reload myapp > /dev/null 2>&1 || true
    endscript
}
```

### Commands

```bash
# Test a logrotate config (dry run)
logrotate -d /etc/logrotate.conf

# Force a rotation now
logrotate -f /etc/logrotate.conf

# Verbose output
logrotate -v /etc/logrotate.conf

# Force specific config
logrotate -f /etc/logrotate.d/nginx
```

## rsyslog

rsyslog is the syslog daemon on most Linux distros. It receives log messages and routes them to files, databases, or remote servers.

### /etc/rsyslog.conf

```bash
# /etc/rsyslog.conf

# Modules
module(load="imuxsock")    # local system logging (socket /dev/log)
module(load="imklog")      # kernel logging (/proc/kmsg)
module(load="imudp")       # UDP syslog reception
module(load="imtcp")       # TCP syslog reception

# Template: standard syslog format
template(name="ForwardFormat" type="string" string="%FROMHOST-IP% %syslogtag%%msg%\n")

# Remote logging (client side — send to central log server)
*.* @@(o)logserver.example.com:514   # TCP
*.* @(o)logserver.example.com:514   # UDP
# (o) = use template above

# Rules: facility.priority → action
# Facilities: auth, authpriv, cron, daemon, kern, lpr, mail, mark, news, syslog, user, uucp, local0-7
# Priorities: debug, info, notice, warn, err, crit, alert, emerg

# Example:
mail.*                           -/var/log/mail.log
mail.err                          /var/log/mail.err
cron.*                           /var/log/cron.log
*.info;mail.none;authpriv.none;cron.none  /var/log/messages
authpriv.*                       /var/log/secure
*.emerg                          :omusrmsg:*
```

### rsyslog server config

```bash
# /etc/rsyslog.d/remote.conf
# Listen on TCP/UDP 514
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")

# Template for remote logs (per host)
template(name="RemoteLogs" type="string" \
    string="/var/log/remote/%FROMHOST%/%PROGRAMNAME%.log")

# Apply template to all incoming
*.* ?RemoteLogs
& stop    # stop processing (don't also write to local files)
```

## Syslog Facilities and Priorities

```bash
# Facilities (first field of syslog message)
auth       # authentication (login, sudo)
authpriv   # private authentication (SSH, PAM)
cron       # cron/at scheduling
daemon     # system daemons
kern       # kernel messages
lpr        # printing
mail       # mail server
news       # news server
syslog     # syslog internal messages
user       # user programs
uucp       # UUCP (old Unix-to-Unix copy)
local0-7   # custom/local use
*          # all facilities

# Priorities (second field)
debug      # debug messages
info       # informational
notice     # normal but significant
warn       # warnings
err        # errors
crit       # critical
alert      # must be handled immediately
emerg      # system is unusable
```

## Centralized Logging

```bash
# Send logs to remote server (rsyslog client):
# /etc/rsyslog.d/50-remote.conf
*.* @@(o)rsyslog.example.com:514

# Using TLS (recommended for production):
# /etc/rsyslog.d/50-tls.conf
global(
    DefaultNetStreamDriver="gtls"
    DefaultNetStreamDriverCAFile="/etc/ssl/certs/ca.pem"
    DefaultNetStreamDriverCertFile="/etc/ssl/certs/client.pem"
    DefaultNetStreamDriverKeyFile="/etc/ssl/private/client.key"
)
action(type="omfwd"
    Target="rsyslog.example.com"
    Port="6514"
    Protocol="tcp"
    StreamDriver="ossl"
    StreamDriverMode="1"
    StreamDriverAuthMode="anon"
)
```

## Quick Reference

```bash
# Read binary logs
lastlog              # last login per user
last                # full wtmp history
lastb               # failed login attempts
faillog             # failed login counters

# logrotate
logrotate -d /etc/logrotate.conf    # dry run
logrotate -f /etc/logrotate.conf    # force now
logrotate -v /etc/logrotate.conf    # verbose

# rsyslog
rsyslogd -N 1        # validate config
systemctl restart rsyslog
tail -f /var/log/syslog
tail -f /var/log/secure
tail -f /var/log/auth.log
```