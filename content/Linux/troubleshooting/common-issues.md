---
title: Common Issues
description: Linux common issues — OOM killer, disk full, permission denied, service won't start, network unreachable
tags:
  - linux
  - troubleshooting
---

# Common Issues

## OOM Killer (Out of Memory)

The Linux OOM killer invokes when physical + swap memory is exhausted. It kills the process that consumed the most memory.

```bash
# Signs:
# - dmesg shows "Out of memory: Killed process"
dmesg | grep -i "out of memory"
dmesg | grep -i "killed process"

# Check if OOM killed something:
grep -i "killed process" /var/log/messages
journalctl -k | grep -i oom

# What was killed:
cat /var/log/syslog.1 | grep -i oom

# Process killed:
dmesg | tail | grep -i killed
# [12345.678] Out of memory: Killed process 1234 (nginx) total-vm:2048000kB, anon-rss:1024000kB, file-rss:0kB
```

### Fix OOM

```bash
# Check actual memory usage:
free -h
cat /proc/meminfo | grep -E "MemAvailable|MemFree|Cached|Buffers"

# Tune vm.swappiness (lower = less aggressive swap)
sysctl -w vm.swappiness=10

# Increase swap
swapon /dev/sdb2
# or create swap file:
fallocate -l 2G /swapfile
mkswap /swapfile
swapon /swapfile

# Check which processes using most memory:
ps aux --sort=-%mem | head -10
```

## Disk Full

```bash
# Find largest directories:
df -h
du -sh /* 2>/dev/null | sort -h | tail -20

# Find largest files:
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null

# Common culprits:
# - /var/log/
# - /tmp/
# - /home/
# - Docker: /var/lib/docker/containers
docker system df   # Docker disk usage

# Clean up:
apt autoremove
docker system prune -a
journalctl --vacuum-size=100M
```

## "Permission Denied" Errors

```bash
# Check actual permissions:
ls -la /path/to/file
id
whoami

# SELinux context?
getenforce   # is SELinux on?
ls -Z /path/to/file

# Check ACLs:
getfacl /path/to/file

# Fix:
chmod 644 /path/to/file
chown user:group /path/to/file

# SSH key permissions:
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

## Service Won't Start

```bash
# Always check status and logs first:
systemctl status nginx
journalctl -u nginx -n 50 --no-pager

# Common causes:
# 1. Port already in use:
ss -tlnp | grep :80

# 2. Config syntax error:
nginx -t
apachectl configtest

# 3. Missing dependencies:
systemctl status postgresql
journalctl -u postgresql -n 20

# 4. Can't bind to address (network issue):
ss -tlnp | grep 8080

# 5. File descriptor limit:
cat /proc/$(pgrep nginx)/limits | grep "Max open files"
```

## Network Unreachable

```bash
# Layer 1: Is interface up?
ip addr
ip link show
cat /sys/class/net/eth0/operstate

# Layer 2: ARP working?
ip neigh show

# Layer 3: Can ping gateway?
ping -c 1 $(ip route | grep default | awk '{print $3}')

# Layer 3: DNS working?
getent hosts google.com
dig google.com

# Layer 4: Port open?
nc -zv 8.8.8.8 443
ss -tlnp | grep :443

# Check firewall:
iptables -L -n -v | head -20
cat /proc/sys/net/ipv4/ip_forward
```

## SSH Connection Refused

```bash
# Is sshd running?
systemctl status sshd

# Is it listening?
ss -tlnp | grep :22

# Firewall?
iptables -L INPUT -n | grep 22

# SELinux?
getenforce
getsebool ssh_sysadm_login

# Logs:
journalctl -u sshd -n 20
tail /var/log/auth.log | grep ssh
```

## High Load Average

```bash
# What is load?
uptime
# Load average: 5.23 4.12 3.45
# (5.23 on 4-core system = 1.3 CPUs busy + 3.9 waiting)

# CPU bound or I/O bound?
top
#wa (wait) = I/O
#us (user) = CPU

iostat -xz 1
# Check for high %util and high await

# What's waiting?
ps aux --sort=-%cpu | head -10
ps -eo pid,stat,wchan:30,cmd --sort=-wchan | head
```

## Docker Container Issues

```bash
# Container won't start:
docker ps -a
docker logs <container>
docker inspect <container>

# Network not working from container:
docker exec <container> ip addr
docker exec <container> ping 8.8.8.8

# Out of disk:
docker system df
docker builder prune -a

# Can't pull image:
docker pull <image>
docker info  # check registry config
```

## Application Not Responding

```bash
# Is it running?
ps aux | grep <app>

# What is it doing?
strace -p $(pgrep <app>)
# or
cat /proc/$(pgrep <app)/wchan

# File descriptors exhausted?
ls /proc/$(pgrep <app>)/fd | wc -l

# Too many connections?
ss -s
ss -tlnp | grep <port>

# Logs:
journalctl -u <service> --since "10 minutes ago"
tail -f /var/log/<app>/error.log
```