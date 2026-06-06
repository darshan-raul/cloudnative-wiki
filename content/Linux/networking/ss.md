---
title: ss and netstat
description: ss — socket statistics, replacing netstat — TCP/UDP/Unix socket state, connections, listening ports, process info
tags:
  - linux
  - networking
  - tools
---

# ss and netstat

`ss` (socket statistics) is the modern replacement for `netstat`. It's faster, shows more detail, and is the standard tool for investigating network connections on modern Linux.

## Why ss over netstat

```
netstat:  reads /proc/net/tcp → slow on high connections
ss:       reads netlink socket → fast, even with 100K connections
ss is the standard on modern Linux (net-tools package is deprecated)
```

## Basic Usage

```bash
# All connections:
ss -a                 # all sockets (listening + established + more)
ss                    # equivalent to ss -a -g (without kernel sockets)

# Listening sockets only:
ss -l                 # listening TCP/UDP/Unix sockets
ss -lt                # listening TCP
ss -lu                # listening UDP
ss -lx                # listening Unix sockets

# Show process:
ss -ltp               # with process name/PID
ss -lntp              # with PID (numeric ports, no resolution)

# Numeric (don't resolve IPs or ports):
ss -n                 # numeric IP and port

# Show summary:
ss -s                 # summary of socket counts

# Resolve hostnames:
ss -r                 # resolve IPs
```

## Socket States (TCP)

```
ss -t state established   # show established TCP
ss -t state listening      # show listening TCP
ss -t state time-wait     # show TIME_WAIT sockets
ss -t state syn-sent       # show SYN_SENT (connection attempts)
ss -t state syn-recv       # show SYN_RECV (incoming handshakes)
ss -t state fin-wait-1     # show FIN_WAIT_1
ss -t state fin-wait-2     # show FIN_WAIT_2
ss -t state close-wait     # show CLOSE_WAIT
ss -t state last-ack       # show LAST_ACK
ss -t state closing        # show CLOSING
ss -t state closed         # show CLOSED
```

### Common States

```bash
# All non-listening sockets:
ss -t state connected    # established + close-wait + time-wait

# All sockets related to HTTP/HTTPS:
ss -t state listening | grep -E ':80|:443'

# Connections to a specific IP:
ss dst 192.168.1.100
ss src 192.168.1.50:80

# Show only IPv4 or IPv6:
ss -4                   # IPv4 only
ss -6                   # IPv6 only
```

## Filters

```bash
# Filter by address and port:
ss dst 192.168.1.100:443          # connections to 192.168.1.100:443
ss src 10.0.0.1                  # connections from 10.0.0.1

# Filter by port (exact or range):
ss sport = :80                   # source port 80
ss dport = :443                  # dest port 443
ss dport gt 1024                 # dest port > 1024
ss dport lt 1024                 # dest port < 1024
ss dport eq 22                   # dest port == 22
ss sport ne 22                   # source port != 22

# Combined:
ss state established '( sport = :443 or dport = :443 )'

# Quick HTTP/HTTPS check:
ss -tn state established | grep ':80\|:443'

# Show all connections to port 22:
ss -tnp | grep ':22'

# UDP sockets:
ss -unap                     # UDP with process info
```

## Process Information

```bash
# Show process:
ss -ltp                     # listening with PID/command
ss -tnp                     # numeric TCP with PID

# Find what process is on a port:
ss -ltnp | grep ':443'
# Output: LISTEN 0 128 *:443 *:* users:(("nginx",pid=1234,fd=6))

# Find process using specific port:
ss -lntp | grep ':80'

# Show inode (for /proc/*/fd/* tracking):
ss -n | grep 12345           # find socket by inode
```

## Memory and Timer Info

```bash
# Show memory usage per socket:
ss -m

# Show timer info (for TCP state):
ss -ti
# Output: 1234  ESTAB  0  192.168.1.10:22  192.168.1.100:54321  timer:(on,240min,0)

# ss -ti output fields:
# wmem: write memory buffer
# rmem: read memory buffer
# oql: OS Q len (listen queue)
# bbr: BBR algorithm in use
# rtt: round-trip time
# cwnd: congestion window
```

## Extended Output

```bash
# Extended info:
ss -e                      # show extended socket info
ss -ee                     # very extended

# Example output with -e:
# ESTAB 0 0 192.168.1.10:22 192.168.1.100:54321 users:(("sshd",pid=1234,fd=3)) uid:1000 ino:12345 sk:abc123
#   ts sack坊wscale:7,7

# Timer info:
ss -ti
# 1234  ESTAB  0  192.168.1.10:22  192.168.1.100:54321
#     rtt:0.163/0.015s  cwnd:10  lastsnd:123456  lastrcv:123789
```

## Practical Patterns

```bash
# 1. What's listening on what port?
ss -ltnp
ss -ltnp | grep -v '127.0.0.1'  # exclude localhost

# 2. How many connections per state?
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn

# 3. Top connection counts by IP:
ss -tn | grep ESTAB | awk '{print $4}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10

# 4. Any suspicious connections?
ss -tn state established | grep -v '192.168.\|10.\|172.1[67].'

# 5. Find TIME_WAIT accumulation:
ss -tn state time-wait | wc -l
# If high, investigate: net.ipv4.tcp_fin_timeout tuning

# 6. Listen queue overflow (SYN flood):
ss -ltn | grep 'ServCall'  # 'ServCall' = syscall failed (listen queue full)
# Or check:
ss -ltn | awk '$2 ~ /LISTEN/ && $4 ~ /:80$/{print}'

# 7. UDP listeners:
ss -unlp

# 8. Unix domain sockets:
ss -lx
# Shows X11, systemd, docker, containerd sockets
```

## ss vs netstat equivalents

```bash
# netstat -tuln          → ss -ltn
# netstat -tun           → ss -tn
# netstat -an            → ss -a -n
# netstat -p             → ss -p
# netstat -r             → ip route
# netstat -i             → ip -s link
# netstat -s             → ss -s
# netstat -ltpn          → ss -ltnpe (extended)
```

## netstat (legacy)

```bash
# Still useful for:
netstat -i               # interface statistics
netstat -r               # routing table (but 'ip route' is better)

# Use netstat when ss not available:
netstat -tulnp | grep :80
netstat -anp | grep :443
```

## Quick Reference

```bash
# Summary
ss -s               # socket count summary

# Listening
ss -ltn            # TCP listening (numeric)
ss -ltnp           # with process
ss -lunp           # UDP listening

# Established
ss -tn             # established TCP
ss -tnp            # with process
ss -ti             # with TCP info (RTT, window, timer)

# Filters
ss dst 10.0.0.1:443
ss sport = :80
ss dport gt 1024
ss state established
ss -4              # IPv4 only
ss -6              # IPv6 only

# Process
ss -p             # show PID/command
ss -e              # extended info
```