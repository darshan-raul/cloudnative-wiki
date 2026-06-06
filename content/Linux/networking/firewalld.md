---
title: firewalld
description: Linux firewalld — zones, services, rich rules, NAT, direct rules, podman integration
tags:
  - linux
  - networking
  - firewall
---

# firewalld

`firewalld` is a frontend for iptables/nftables on RHEL/Fedora/CentOS and other systemd-based distros. It provides a **zone-based** firewall model where network interfaces are assigned to zones, and each zone has a set of allowed services and ports.

## Zones

A zone is a **trust level** for a network connection. firewalld ships predefined zones (ordered by trust):

| Zone          | Trust | Description                                |
|--------------|-------|--------------------------------------------|
| block | none | Reject all incoming |
| drop | low   | Drop all incoming (no reply)              |
| external | low   | For external routed networks (NAT)         |
| dmz          | med | DMZ (limited access)                      |
| work         | med | Work network                               |
| home         | med | Home network                               |
| internal     | med   | Internal network                           |
| public | low | Public networks (default)                  |
| trusted      | full  | Allow all                                 |

```bash
# List zones
firewall-cmd --list-all-zones

# Default zone
firewall-cmd --get-default-zone
firewall-cmd --set-default-zone=home

# List active zone (what interface is in what zone)
firewall-cmd --get-active-zones
```

## Services

Services are named combinations of ports and protocols:

```bash
# List predefined services
firewall-cmd --get-services

# List services in a zone
firewall-cmd --zone=public --list-services

# Add/remove a service
firewall-cmd --zone=public --add-service=http
firewall-cmd --zone=public --add-service=https --permanent
firewall-cmd --zone=public --remove-service=http

# Permanent vs runtime:
# --permanent: survives reload, doesn't apply until --reload
# Runtime: applies immediately, lost on reboot
```

## Ports

```bash
# Open a port
firewall-cmd --zone=public --add-port=8080/tcp
firewall-cmd --zone=public --add-port=5000-5010/udp --permanent

# List open ports
firewall-cmd --zone=public --list-ports

# Remove port
firewall-cmd --zone=public --remove-port=8080/tcp
```

## Rich Rules

For complex rules with source IP, logging, etc.:

```bash
# Allow SSH only from 10.0.0.0/8
firewall-cmd --zone=public --add-rich-rule='rule source address="10.0.0.0/8" service name="ssh" accept'

# Allow HTTP, log new connections
firewall-cmd --zone=public --add-rich-rule='rule service name="http" log prefix="http: " level="info" accept'

# Allow port 8080 from specific IP
firewall-cmd --zone=public --add-rich-rule='rule source address="192.168.1.100" port port="8080" protocol="tcp" accept'

# Reject everything from a source IP
firewall-cmd --zone=public --add-rich-rule='rule source address="1.2.3.4" reject'

# List rich rules
firewall-cmd --zone=public --list-rich-rules

# Remove rich rule
firewall-cmd --zone=public --remove-rich-rule='rule source address="1.2.3.4" reject'
```

## NAT and Port Forwarding

```bash
# Enable masquerading (outbound NAT) on a zone
firewall-cmd --zone=external --add-masquerade
firewall-cmd --zone=external --add-masquerade --permanent

# Port forwarding (DNAT)
firewall-cmd --zone=external --add-forward-port=port=8080:proto=tcp:toport=80:toaddr=192.168.1.100

# Permanent
firewall-cmd --zone=external --add-forward-port=port=8080:proto=tcp:toport=80:toaddr=192.168.1.100 --permanent
```

## Direct Rules (iptables passthrough)

For rules that firewalld's abstractions don't cover:

```bash
# Direct iptables rule (pass through to iptables)
firewall-cmd --direct --add-rule ipv4 filter INPUT0 -p tcp --dport 9000 -j ACCEPT

# List direct rules
firewall-cmd --direct --get-all-rules

# Remove
firewall-cmd --direct --remove-rule ipv4 filter INPUT 0 -p tcp --dport 9000 -j ACCEPT
```

## Runtime vs Permanent

```bash
# Changes without --permanent apply immediately, lost on reboot
firewall-cmd --zone=public --add-service=http

# Permanent changes survive reboot but require reload
firewall-cmd --zone=public --add-service=http --permanent
firewall-cmd --reload              # apply permanent changes now

# Panic mode (block all traffic)
firewall-cmd --panic-on
firewall-cmd --panic-off
```

## Rich Rule Syntax Reference

```
rule [family="ipv4|ipv6"]
  [source [NOT] address="CIDR"|mac="XX:XX:XX:XX:XX:XX"]
  [destination [NOT] address="CIDR"]
  [element]
  [log [prefix="PREFIX"] [level="LEVEL"] [limit value="RATE/UNIT"]]
  [audit [limit value="RATE/UNIT"]]
  [action]
```

Actions: `accept`, `reject [type=icmp]`, `drop`, `mark set="MARK"`.

## firewalld and Podman

Podman can integrate with firewalld for network management:

```bash
# When using --network=host, firewalld zones apply
# Podman can manage its own firewall rules:
podman network inspect podman | jq '.[].network_interface'

# For rootless podman with firewall:
# Add podman to firewalld (newer versions):
firewall-cmd --add-interface=cni0 --zone=trusted
```