---
title: iptables
description: Linux iptables — tables, chains, targets, NAT, masquerading, FORWARD, filter rules
tags:
  - linux
  - networking
  - firewall
---

# iptables

iptables is the legacy Linux firewall interface. It programs the **netfilter** kernel subsystem, which inspects and modifies packets as they flow through the kernel's networking stack. Modern systems often use `nftables` (the successor) or `firewalld` (a frontend), but iptables is still everywhere and worth understanding deeply.

## Architecture: Tables → Chains → Rules

```
Tables (4):
  ┌──────────────────────────────────────────────────────┐
  │ filter    — accept/drop packets (INPUT, FORWARD, OUTPUT) │
  │ nat       — NAT, DNAT, SNAT, masquerade              │
  │ mangle    — TOS, TTL, MARK, delay packets            │
  │ raw       — NOTRACK, disable connection tracking      │
  └──────────────────────────────────────────────────────┘

Each table has chains (built-in):
  ┌──────────────────────────────────────────────────────┐
  │ filter:  PREROUTING, INPUT, FORWARD, OUTPUT, POSTROUTING
  │ nat:     PREROUTING, INPUT, OUTPUT, POSTROUTING
  │ mangle:  PREROUTING, INPUT, FORWARD, OUTPUT, POSTROUTING
  │ raw:     PREROUTING, OUTPUT
  └──────────────────────────────────────────────────────┘

Packet flow through FORWARD chain:
  ┌────────┐    ┌──────────┐   ┌────────┐    ┌───────────┐
  │ NIC    │───►│ PREROUT  │──►│ FORWARD │───►│ POSTROUTE │
  │ packet │    │ (nat)    │    │(filter) │    │  (nat)    │
  └────────┘    └──────────┘   └────────┘    └───────────┘

Each chain has rules evaluated top-to-bottom. First match wins.
```

## The Filter Table (Packet Filtering)

```bash
# Syntax: iptables [-t table] -A chain -s source -d dest -p protocol --dport port -j target

# Block all incoming SSH from 192.168.1.100
iptables -A INPUT -s 192.168.1.100 -p tcp --dport 22 -j DROP

# Allow SSH from 10.0.0.0/8, block from everywhere else
iptables -A INPUT -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP

# Allow established connections (stateful firewall)
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Default policy (last resort)
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
```

## Targets (Actions)

| Target        | What it does                                          |
|---------------|------------------------------------------------------|
| ACCEPT        | Allow the packet                                     |
| DROP          | Silently discard (no response)                      |
| REJECT        | Send ICMP error back (e.g., port unreachable)        |
| LOG           | Log to syslog (then continue to next rule!)         |
| MASQUERADE    | NAT: replace source IP with egress interface IP       |
| SNAT          | NAT: replace source IP with specified IP             |
| DNAT          | NAT: replace dest IP with specified IP               |
| REDIRECT      | NAT: redirect to local port or another port           |
| MARK          | Mark packet (for tc/routing policy)                  |
| RETURN        | Stop traversing this chain, return to calling chain   |

## Connection Tracking (Stateful Firewall)

```bash
# The conntrack module tracks connection state
# States: NEW, ESTABLISHED, RELATED, INVALID

# Allow all established/related (return traffic)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow new SSH connections from trusted subnet
iptables -A INPUT -m conntrack --ctstate NEW -s 10.0.0.0/8 -p tcp --dport 22 -j ACCEPT

# View connection tracking table
cat /proc/net/nf_conntrack
# ipv4     2 tcp      6 431999 ESTABLISHED src=10.0.0.1 dst=10.0.0.2 sport=54321 dport=22 src=10.0.0.2 dst=10.0.0.1 sport=22 dport=54321 [ASSURED]
```

**ESTABLISHED/RELATED is critical** — without it, return traffic for outbound connections gets blocked.

## NAT and Masquerading

### SNAT (Source NAT) — outbound traffic

```bash
# SNAT: rewrite source IP to a fixed IP
iptables -t nat -A POSTROUTING -s 192.168.1.0/24 ! -d 192.168.1.0/24 -j SNAT --to-source 203.0.113.10
```

### MASQUERADE — dynamic SNAT (for dynamic IPs)

```bash
# Masquerade: rewrite source IP to whatever the egress interface has
# Used when your IP is assigned by DHCP
iptables -t nat -A POSTROUTING -s 192.168.1.0/24 ! -d 192.168.1.0/24 -j MASQUERADE

# This is what Docker uses for container-to-internet
# (applied to the docker0 bridge)
```

### DNAT (Destination NAT) — port forwarding

```bash
# Forward port 8080 → port 80 on 192.168.1.100 (DNAT)
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.100:80

# Also need to allow the forwarded traffic in filter
iptables -A FORWARD -d 192.168.1.100 -p tcp --dport 80 -j ACCEPT
```

## The FORWARD Chain (Critical for Containers)

The FORWARD chain is where most container networking decisions happen. By default, it's ACCEPT or DROP depending on your policy.

```bash
# Docker's default FORWARD policy is ACCEPT
# But it sets up these rules per container network:
iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT
iptables -A FORWARD -i docker0 ! -o docker0 -j ACCEPT

# When --icc=false (inter-container communication disabled):
iptables -A FORWARD -i docker0 -o docker0 -j DROP

# Kubernetes pods on a bridge: same pattern
iptables -A FORWARD -i cni0 -o cni0 -j ACCEPT
```

**If FORWARD is DROP and no rules allow container traffic, containers can't reach each other.**

## Listing and Debugging Rules

```bash
# List all rules (filter table)
iptables -L -n -v        # verbose, with packet/byte counts
iptables -L -n -v --line-numbers   # with rule numbers

# List specific table
iptables -t nat -L -n -v

# List INPUT chain
iptables -L INPUT -n --line-numbers

# Delete a rule by number
iptables -D INPUT 3

# Flush a chain
iptables -F INPUT

# Flush all rules (reset)
iptables -F
iptables -t nat -F
iptables -X    # delete user-created chains
iptables -Z    # zero counters
```

## iptables-save and iptables-restore

Rules don't persist across reboots. Save and restore:

```bash
# Save current rules
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

# Restore on boot (systemd service):
# /etc/systemd/system/iptables-restore.service
[Unit]
After=networking.service
[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
[Install]
WantedBy=multi-user.target

# Or on Debian/Ubuntu:
apt install iptables-persistent
# rules saved to /etc/iptables/rules.v4 automatically
```

## Important: Order Matters

```bash
# WRONG: generic DROP then specific ACCEPT (ACCEPT never reached)
iptables -A INPUT -j DROP
iptables -A INPUT -p tcp --dport 22 -j ACCEPT   # NEVER MATCHES

# CORRECT: specific ACCEPT first, then generic DROP
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -j DROP
```

## Common Docker iptables Rules

```bash
# Docker sets these up automatically:
# NAT/masquerade for containers:
iptables -t nat -A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE

# Allow established connections:
iptables -A FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i docker0 -j ACCEPT

# Container-to-container on same network:
iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT

# If inter-container comm disabled:
iptables -A FORWARD -i docker0 -o docker0 -j DROP
```

## nftables: The Modern Alternative

nftables (successor to iptables) uses a single tool with cleaner syntax:

```bash
# nftables equivalent of the iptables rules above:
nft add table ip filter
nft add chain ip filter INPUT { type filter hook input priority 0 \; }
nft add rule ip filter INPUT ct state established,related accept
nft add rule ip filter INPUT tcp dport 22 accept
nft add rule ip filter INPUT drop
```

nftables has performance advantages for large rule sets and replaces iptables/ip6tables/ebtables/arptables with one tool.