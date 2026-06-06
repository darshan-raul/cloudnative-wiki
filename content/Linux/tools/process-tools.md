---
title: Process Management Tools
description: Linux process management utilities — lsof, fuser, pkill, pgrep, killall, pgrep, ps usage patterns, signal reference
tags:
  - linux
  - tools
  - processes
---

# Process Management Tools

Beyond `ps` and `top`, Linux has a suite of focused tools for finding processes, managing them, and investigating what files/sockets they have open.

## lsof — List Open Files

"Everything is a file" on Linux. `lsof` shows what files, directories, sockets, and devices are open by which processes.

```bash
# All open files for a process
lsof -p 1234

# All files opened by a specific user
lsof -u darshan

# All processes using a specific file
lsof /var/log/syslog
lsof /etc/passwd

# All processes using a directory (useful before unmounting)
lsof +D /var/log
# +D = recursive — shows all processes using any file in that dir

# Network connections (files = sockets)
lsof -i                 # all network connections
lsof -i TCP             # only TCP
lsof -i UDP            # only UDP
lsof -i :443           # processes using port 443
lsof -i TCP:443        # TCP port 443
lsof -i @192.168.1.1   # connections to specific IP
lsof -i -sTCP:LISTEN   # listening TCP sockets
lsof -i -sTCP:ESTABLISHED  # established connections

# Socket inode tracking (find process by socket inode):
lsof +K                  # show socket inodes (Linux only)

# Find who is reading/writing a file
lsof -r 1 /var/log/access.log
# -r 1 = repeat every 1 second

# Command name:
lsof -c nginx            # all files by processes named nginx
lsof -c '^nginx$'        # exact match (not nginx-worker)

# Mixed:
lsof -u darshan -i TCP:22  # darshan's SSH connections
```

### lsof Output Fields

```
COMMAND  PID   USER   FD   TYPE   DEVICE  SIZE/OFF   NODE   NAME
nginx    1234  root   6u   IPv4  12345   0t0        TCP    *:http (LISTEN)
nginx    1234  root   7u   IPv4  12346   0t0        TCP    *:https (LISTEN)
nginx    1234  root   8w   REG   8,1    12345      67890  /var/log/nginx/access.log
```

- **FD**: file descriptor number + mode (r=read, w=write, u=read+write)
- **TYPE**: REG (regular file), DIR, FIFO, CHR, IPv4, IPv6, UNIX

### Practical lsof Patterns

```bash
# Find processes listening on ports (without ss/netstat):
lsof -i -sTCP:LISTEN -n -P

# Find zombie processes:
lsof 2>&1 | grep -i zombie

# Find deleted but still-open files (log rotation issue):
lsof +L1
# Shows files with link count < 1 (deleted files kernel still holds)

# Check if a file is busy (before deleting/moving):
lsof /var/log/nginx/access.log

# Find processes using deleted libraries:
lsof +D /lib/modules/$(uname -r) | grep deleted
```

## fuser — Find Process Using Files/Sockets

```bash
# Find processes using a file or directory:
fuser /var/log/syslog
# Output: /var/log/syslog:   1234m   5678r
# 1234m = PID 1234 with mmap'd file, 5678r = PID 5678 reading

# Kill all processes accessing a mount point (before unmount):
fuser -km /mnt/usb
# -k = kill processes
# -m = mounted device

# Show PIDs only:
fuser -v /var/log/
#               USER        PID ACCESS COMMAND
# /var/log/:    root       1234 F.... nginx

# Find processes using TCP port:
fuser 443/tcp
# Shows PIDs using port 443

# Kill process on specific port:
fuser -k 443/tcp
# Sends SIGKILL to all PIDs using port 443

# Only show processes with a specific access:
fuser -v -m /home          # any access to /home
```

## pkill, pgrep, killall

These are pattern-based process signal senders.

### pgrep

```bash
# Find processes by name:
pgrep nginx                # returns PIDs
pgrep -f 'nginx -g daemon'  # match against full command line (-f)

# Match multiple patterns:
pgrep -d, 'nginx|postgres|redis'  # -d = delimiter

# Show process details (like ps):
pgrep -a nginx             # show full command line
pgrep -l nginx             # show PID + name

# Match by user:
pgrep -u darshan nginx     # nginx owned by darshan
pgrep -u root,daemon       # belonging to root OR daemon

# Count:
pgrep -c nginx            # number of matches

# Exact match (not substring):
pgrep -x nginx             # exactly "nginx", not "nginx-worker"
```

### pkill

```bash
# Kill by name (sends SIGTERM):
pkill nginx

# Kill by pattern (full command line):
pkill -f 'curl http://'

# Send specific signal:
pkill -SIGKILL nginx      # force kill
pkill -9 nginx             # same
pkill -SIGTERM -u darshan # kill all darshan's processes

# Kill processes on a specific tty:
pkill -t pts/0            # kill processes on pts/0

# Kill by older than:
# (combine with pgrep -T to find):
pkill --older 3600 nginx   # nginx running > 1 hour (Linux 3.11+)

# Kill interactive/SSH processes:
pkill -t pts/0

# Dry run (just show what would be killed):
pkill --dry-run nginx
```

### killall

```bash
# Kill by exact process name:
killall nginx
killall -9 nginx           # force kill

# Kill all processes matching a user:
killall -u darshan         # all darshan's processes
killall -9 -u darshan      # force kill all

# Kill processes with age:
killall -o 10m nginx       # processes running > 10 minutes
killall -y 300 nginx       # processes started < 5 minutes

# Interactive:
killall -i nginx           # ask before each kill
killall -i -v nginx       # verbose interactive

# Match multiple names:
killall nginx postgres redis
```

## Signal Quick Reference

```bash
# These all send SIGTERM (15) by default:
pkill nginx
killall nginx
kill $(pgrep nginx)

# Explicit signals:
pkill -SIGKILL nginx    # or -9
pkill -SIGSTOP nginx     # freeze (Ctrl+Z equivalent)
pkill -SIGCONT nginx     # resume
pkill -SIGHUP nginx     # reload config (nginx, apache, dockerd)

# Common signals:
# 1   HUP   — hangup, reload config
# 9   KILL  — unblockable kill
# 15  TERM  — graceful termination (default)
# 18  CONT  — continue (resume from STOP)
# 19  STOP  — freeze process
# 20  TSTP  — terminal stop (Ctrl+Z)
```

## Finding and Investigating

```bash
# Find PID by name:
pgrep -f nginx
pidof nginx               # (only exact name match)

# Show process tree:
pstree -p                # with PIDs
pstree -a                # show arguments
pstree -u darshan        # processes owned by darshan

# Find zombie processes:
ps aux | grep -w Z
# or
ps -eo pid,stat,cmd | grep ^Z

# Top CPU per process:
ps -eo pid,cmd,%cpu --sort=-%cpu | head -20

# Top memory:
ps -eo pid,cmd,%mem --sort=-%mem | head -20

# How long has it been running:
ps -eo pid,cmd,etime | grep nginx
# ELAPSED column: [[dd-]hh:]mm:ss

# What files does a process have open:
lsof -p $(pgrep -f nginx | head -1)

# What sockets does a process have:
lsof -i -a -p $(pgrep nginx | head -1)

# Environment variables of a running process:
cat /proc/$(pgrep nginx | head -1)/environ | tr '\0' '\n'

# cmdline without being truncated:
cat /proc/$(pgrep nginx | head -1)/cmdline | tr '\0' ' '
```

## Quick Reference

```bash
# lsof
lsof -i :443                   # who uses port 443
lsof -p 1234                   # what process 1234 has open
lsof -u darshan                # files by user
lsof +D /var/log               # processes in directory
lsof +L1                       # deleted but open files

# fuser
fuser 443/tcp                  # PIDs using port 443
fuser -km /mnt                # kill processes on mount

# pgrep / pkill
pgrep -a nginx                # find nginx with cmdline
pkill -f 'pattern'            # kill by pattern
pkill -SIGUSR1 nginx          # reload nginx

# killall
killall nginx                 # kill all nginx
killall -9 -u darshan        # kill all user processes

# find PID
pgrep nginx                   # PIDs of nginx
pidof nginx                   # exact name match only
```