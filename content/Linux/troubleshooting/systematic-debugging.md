---
title: Systematic Debugging
description: Linux debugging methodology — gather, hypothesize, isolate, verify, systematic approach to resolving issues
tags:
  - linux
  - troubleshooting
---

# Systematic Debugging

Good debugging is methodical, not random. A systematic approach finds root causes faster and avoids chasing symptoms. The core loop is: **observe → hypothesize → test → iterate**.

## The 5-Phase Method

### Phase 1: Gather Evidence

Before changing anything, collect what you know:

```bash
# What's currently happening?
# - Error messages, logs
# - When did it start?
# - What changed recently? (updates, config changes, deployments)

# System state
uptime
who -b
last reboot

# Resource state
df -h
free -h
top -bn1 | head -20
```

### Phase 2: Scope the Problem

```bash
# Is it system-wide or per-user/per-process?
whoami
ps aux | grep $USER

# Is it local or network?
ping -c 3 8.8.8.8
ping -c 3 $(hostname)

# Is it a specific service or everything?
systemctl status nginx
journalctl -u nginx -n 50
ss -tlnp
```

### Phase 3: Narrow Down

```bash
# Find the limiting resource:
# CPU-bound? → top, mpstat, pidstat
top
mpstat -P ALL 1 3

# Memory-bound? → free, vmstat
free -h
vmstat 1 5

# I/O-bound? → iostat, iotop
iostat -xz 1
iotop -a

# Network-bound? → ss, netstat
ss -tulnp
ip route get 8.8.8.8
```

### Phase 4: Form and Test Hypotheses

```bash
# Hypothesis: "nginx is returning 502 because upstream is down"
# Test: curl the upstream directly
curl -v http://127.0.0.1:8080/health

# Hypothesis: "disk is full"
# Test:
df -h
du -sh /* 2>/dev/null | sort -h | tail -10

# Hypothesis: "iptables is blocking traffic"
# Test:
iptables -L -n -v
# Temporarily flush if safe:
# iptables -F; curl http://localhost

# Hypothesis: "DNS not resolving"
# Test:
getent hosts example.com
dig example.com
cat /etc/resolv.conf
```

### Phase 5: Verify and Document

```bash
# Apply fix
# Confirm fix works
curl http://localhost/health

# Document:
# - What was the problem?
# - What was the root cause?
# - What fixed it?
# - How to prevent recurrence?
```

## Common Debugging Commands

```bash
# Process not starting?
systemctl status <service>
journalctl -u <service> -n 50 --no-pager
strace -f -e trace=open,openat $(pgrep <service>)

# High CPU?
top
htop
pidstat 1 5 -p $(pgrep -d, <process>)

# Memory leak?
valgrind --leak-check=full <command>
# or
cat /proc/<pid>/status | grep -E "VmRSS|VmSize"

# File descriptor leak?
ls /proc/<pid>/fd | wc -l
lsof -p <pid>

# Network connectivity?
ss -tlnp
netstat -i
ip addr
ip route
iptables -L -n -v
```

## Log-Driven Debugging

```bash
# Real-time log tail
journalctl -u nginx -f
journalctl -f --since "10 minutes ago"

# Search logs
journalctl --since "1 hour ago" | grep -i error
ausearch -k shadow_access

# /var/log/
ls /var/log/
tail -f /var/log/syslog
tail -f /var/log/auth.log
```

## The "It Worked Yesterday" Problem

```bash
# What changed?
last -20
diff /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
# Check package updates:
# Ubuntu/Debian:
dpkg -l | grep -E "nginx|mysql|redis"
# RHEL/CentOS:
rpm -qa | grep -E "nginx|mysql|redis"

# Date of last change to config:
ls -la /etc/nginx/nginx.conf

# Check time of failure:
journalctl --list-boots
journalctl -b -1 --no-pager -n 100
```

## Emergency Recovery

```bash
# Reboot gracefully first:
systemctl reboot

# If hung:
# SysRq: Alt+SysRq+[key] (or echo key > /proc/sysrq-trigger)
echo "w" > /proc/sysrq-trigger  # show blocked tasks
echo "m" > /proc/sysrq-trigger  # dump memory info
echo "s" > /proc/sysrq-trigger  # sync filesystems
echo "u" > /proc/sysrq-trigger  # remount RO
echo "b" > /proc/sysrq-trigger  # reboot NOW

# If a service is looping:
kill -STOP $(pgrep <service>)   # pause first to get core
strace -p $(pgrep <service>)    # see what it's doing
kill -CONT $(pgrep <service>)    # resume
```