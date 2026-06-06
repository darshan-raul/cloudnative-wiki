---
title: "09 — Networking Basics"
description: Linux networking fundamentals — IP addresses, subnets, gateway, DNS, ping, curl, netstat/ss, port basics
tags:
  - linux
  - concepts
---

# 09 — Networking Basics

Every Linux machine is a network node. Understanding IP addresses, DNS, ports, and basic diagnostics is essential for any sysadmin.

## IP Addresses

An IP address identifies a machine on a network.

### IPv4

```
32-bit address, written as 4 decimal octets:
192.168.1.100

Address classes (legacy, rarely used now):
  Class A: 0.0.0.0   – 127.255.255.255   (8-bit network)
  Class B: 128.0.0.0  – 191.255.255.255   (16-bit network)
  Class C: 192.0.0.0  – 223.255.255.255   (24-bit network)

Private ranges (not routed on the internet):
  10.0.0.0/8       — 10.0.0.0 to 10.255.255.255
  172.16.0.0/12    — 172.16.0.0 to 172.31.255.255
  192.168.0.0/16   — 192.168.0.0 to 192.168.255.255

Special addresses:
  127.0.0.1        — loopback (this machine, "localhost")
  0.0.0.0           — "all addresses" (listen on all interfaces)
```

### IPv6

```
128-bit address, written in hexadecimal groups:
2001:0db8:85a3:0000:0000:8a2e:0370:7334

Shorthand:
  2001:db8:85a3::8a2e:370:7334  (:: collapses consecutive zeros)
  fe80::1                        (link-local address)

Every device has a link-local address (fe80::/10)
The loopback in IPv6 is ::1
```

## Subnets and CIDR

CIDR notation: `address/prefix_length`

```
192.168.1.100/24
  → 24 bits = network portion
  → 8 bits = host portion (254 usable: .1 to .254)

/24 = 255.255.255.0    — 254 hosts per network
/16 = 255.255.0.0      — 65,534 hosts per network
/8  = 255.0.0.0        — 16.7 million hosts
/32 = 255.255.255.255  — single host

192.168.1.0 is the network address (all hosts off = network ID)
192.168.1.255 is the broadcast address (all hosts on = broadcast)
```

## Checking Your Network

```bash
# Show all IP addresses:
ip addr
# or:
ifconfig

# Show routing table:
ip route
# default via 192.168.1.1 dev eth0
# 192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100

# Check DNS:
cat /etc/resolv.conf
# nameserver 192.168.1.1
# nameserver 8.8.8.8

# Test connectivity:
ping 8.8.8.8
ping google.com

# Check DNS resolution:
host google.com
dig google.com
nslookup google.com
```

## DNS — Converting Names to IPs

```bash
# Resolve a hostname:
host google.com
# google.com has address 142.250.x.x
# google.com has address 2607:f8b0:x.x

# Query specific DNS server:
dig @8.8.8.8 google.com

# Check what your system uses:
cat /etc/resolv.conf

# Override DNS temporarily:
# Add to /etc/hosts:
echo "1.2.3.4 myapp.local" | sudo tee -a /etc/hosts
ping myapp.local   # resolves to 1.2.3.4
```

## Ports and Services

A port is a number that identifies a specific service on a machine. Services **listen** on ports and clients **connect** to them.

```
Well-known ports (0-1023) — system services:
  22   — SSH
  80   — HTTP
  443  — HTTPS
  53   — DNS
  25   — SMTP
  3306 — MySQL/MariaDB
  5432 — PostgreSQL
  6379 — Redis
  9200 — Elasticsearch
  27017 — MongoDB

Ephemeral ports (49152-65535) — client-side, temporary connections
```

## Checking What's Listening

```bash
# What ports are open and listening?
ss -tlnp
# -t = TCP, -l = listening, -n = numeric, -p = process

# Example output:
# LISTEN 0 128 *:80   *:*    users:(("nginx",pid=1234,fd=6))
# LISTEN 0 128 *:22   *:*    users:(("sshd",pid=987,fd=3))

# Same with netstat (older):
netstat -tlnp

# What process is on a specific port?
ss -tlnp | grep :80
ss -tlnp | grep :443

# Established connections:
ss -tn
# ESTAB 0 0 192.168.1.100:22  192.168.1.50:54321
```

## curl and wget — HTTP Clients

```bash
# Fetch a URL:
curl https://example.com
curl -s https://api.github.com   # -s = silent (no progress meter)

# Save to file:
curl -o filename.html https://example.com
curl -O https://example.com/file.zip  # save with remote filename

# Show headers only:
curl -I https://example.com

# Follow redirects:
curl -L https://example.com

# POST request:
curl -X POST https://api.example.com/data \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}'

# With authentication:
curl -u user:password https://api.example.com

# wget (download):
wget https://example.com/file.zip
wget -O output.zip https://example.com/file.zip
wget -c large-file.iso    # resume partial download
```

## Firewall Basics

Linux has a built-in firewall called **netfilter**. It's controlled by **iptables**, **nftables**, or **firewalld**.

```bash
# Check if firewall is active (Ubuntu):
sudo ufw status
sudo ufw allow 22/tcp    # allow SSH
sudo ufw allow 80/tcp    # allow HTTP
sudo ufw deny 3306/tcp   # block MySQL
sudo ufw enable

# Check rules:
sudo iptables -L -n
sudo ufw status verbose
```

## Quick Reference

```bash
# Show IPs
ip addr
ifconfig

# Routing
ip route

# DNS
cat /etc/resolv.conf
host google.com
dig google.com

# Connectivity
ping 8.8.8.8
curl -I https://example.com

# Ports
ss -tlnp
ss -tn | grep ESTAB

# Firewall
sudo ufw status
sudo ufw allow 22/tcp
```