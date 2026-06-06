---
title: DHCP
description: Linux DHCP — DHCP discovery, DORA process, systemd-networkd, NetworkManager, DHCP relay, debugging leases
tags:
  - linux
  - networking
---

# DHCP

DHCP (Dynamic Host Configuration Protocol) automatically assigns IP addresses, netmask, gateway, DNS servers, and other network parameters to hosts. It's the protocol that makes "plug and play" networking work — no manual IP configuration needed.

## The DORA Process

DHCP uses a 4-message exchange:

```
Client                                    Server
  │                                         │
  │─────── DISCOVER (broadcast) ─────────────▶│  "I need an IP"
  │                                         │
  │◀─────── OFFER (broadcast) ──────────────│  "Here's an offer:
  │              yiaddr=192.168.1.100       │   you can have .100"
  │              lease time=3600             │
  │                                         │
  │─────── REQUEST (broadcast) ──────────────▶│  "Yes, I'll take .100"
  │              requested_addr=192.168.1.100 │
  │              server_id=192.168.1.1       │
  │                                         │
  │◀─────── ACK (broadcast) ────────────────│  "OK, .100 is yours
  │              yiaddr=192.168.1.100        │   for 3600 seconds"
  │              lease time=3600             │
```

**DISCOVER**: Client broadcasts looking for DHCP servers
**OFFER**: Server offers an IP address
**REQUEST**: Client says "I want this offer"
**ACK**: Server confirms, lease is active

All broadcast because the client doesn't have an IP yet (uses 0.0.0.0 as source, 255.255.255.255 as destination).

## DHCP on Linux

### systemd-networkd

systemd-networkd is systemd's built-in network manager (minimal, no GUI):

```bash
# /etc/systemd/network/eth0.network
[Match]
Name=eth0

[Network]
DHCP=ipv4
IPv6AcceptRA=yes

# Or static:
[Match]
Name=eth0

[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
DNS=8.8.8.8
DNS=1.1.1.1
```

```bash
systemctl enable --now systemd-networkd
systemctl status systemd-networkd

# View DHCP lease info
cat /var/lib/systemd/network/*lease* 2>/dev/null
# or
networkctl status eth0
```

### NetworkManager

NetworkManager is the default on desktop/server Ubuntu, Fedora, and most distros with a GUI:

```bash
# CLI: nmcli
nmcli device status
nmcli device show eth0
nmcli connection show
nmcli connection modify "Wired connection 1" ipv4.addresses 192.168.1.100/24
nmcli connection modify "Wired connection 1" ipv4.gateway 192.168.1.1
nmcli connection modify "Wired connection 1" ipv4.dns "8.8.8.8,1.1.1.1"
nmcli connection modify "Wired connection 1" ipv4.method manual   # static
nmcli connection modify "Wired connection 1" ipv4.method auto    # DHCP

# Restart the connection
nmcli connection up "Wired connection 1"

# GUI: nmtui (text-based)
nmtui
```

### dhclient

`dhclient` is the classic ISC DHCP client:

```bash
# Request DHCP lease
dhclient eth0

# Release DHCP lease
dhclient -r eth0

# Verbose output
dhclient -v eth0

# Specific config file
dhclient -cf /etc/dhcp/dhclient.conf eth0

# Check lease
cat /var/lib/dhcp/dhclient.leases
```

### DHCP Server (dnsmasq / isc-dhcp-server)

```bash
# dnsmasq as DHCP server (common in home routers, labs)
# /etc/dnsmasq.d/dhcp.conf
dhcp-range=192.168.1.50,192.168.1.150,12h
dhcp-option=option:router,192.168.1.1
dhcp-option=option:dns-server,8.8.8.8
dhcp-host=aa:bb:cc:dd:ee:ff,192.168.1.50,fixed    # static lease by MAC

# ISC dhcpd
# /etc/dhcp/dhcpd.conf
subnet 192.168.1.0 netmask 255.255.255.0 {
  range 192.168.1.50 192.168.1.150;
  option routers 192.168.1.1;
  option domain-name-servers 8.8.8.8;
}
```

## DHCP Lease File

```bash
# NetworkManager lease
cat /var/lib/NetworkManager/internal-*-eth0.lease

# systemd-networkd lease
cat /var/lib/systemd/network/*eth0*

# dhclient lease
cat /var/lib/dhcp/dhclient.leases
# lease {
#   interface "eth0";
#   fixed-address 192.168.1.100;
#   option subnet-mask 255.255.255.0;
#   option routers 192.168.1.1;
#   option dhcp-lease-time 3600;
#   option dhcp-message-type 5;
#   option domain-name-servers 8.8.8.8,1.1.1.1;
#   renew 2 2025/06/06 14:00:00;
#   rebind 2 2025/06/06 15:30:00;
#   expire 2 2025/06/06 16:00:00;
# }
```

## DHCP Options (Option Codes)

```bash
# Common DHCP options:
option routers          # default gateway
option subnet-mask
option domain-name-servers  # DNS servers
option domain-name
option broadcast-address
option ntp-servers
option lease-time
```

## DHCP Relay (for multiple VLANs)

If DHCP servers and clients are on different networks, a **DHCP relay agent** (often the router) forwards DHCP requests:

```
VLAN10 client (broadcast DISCOVER)
  → Router (relay agent) adds giaddr (relay IP)
  → Router forwards to DHCP server at 10.0.0.10
  → Server responds via router to client
```

```bash
# On a Linux router, enable DHCP relay:
# With ISC Kea:
# /etc/kea/kea-agent.conf
{
  "Dhcp4": {
    "relay": {
      "ip-addresses": ["10.0.0.10"]
    }
  }
}

# Or with ISC dhcpd:
# iptables -t nat -A PREROUTING -p udp --dport 67 -j DNAT --to 10.0.0.10:67
```

## Debugging DHCP Issues

```bash
# 1. Is the interface getting an address?
ip addr show eth0

# 2. Check NetworkManager state
nmcli device status
networkctl status eth0

# 3. View lease history
journalctl -u NetworkManager | grep DHCP
journalctl -u systemd-networkd | grep DHCP

# 4. Packet capture
tcpdump -i eth0 port 67 or port 68 -v
# port 67 = BOOTP/DHCP server
# port 68 = BOOTP/DHCP client

# 5. Force renew
nmcli connection up "Wired connection 1"
# or
dhclient -r eth0 && dhclient eth0

# 6. Check firewall (DHCP uses UDP 67/68)
iptables -L -n -v | grep 67
```

## DHCP and Containers

Containers get IP addresses from Docker's internal DHCP server (dnsmasq) or directly from the host's network namespace:

```bash
# Docker's built-in DHCP (in bridge network mode):
# Docker runs dnsmasq as 172.17.0.1, assigns 172.17.0.0/16
# Container: DHCP DISCOVER → dnsmasq on docker0 bridge → offers 172.17.0.x

# Kubernetes pod DHCP (CNI):
# Most CNI plugins don't use DHCP — they assign IPs statically from a CIDR
# Butcilico's macvlan and ipvlan can use DHCP

# Check container's DHCP lease (if using DHCP in container):
docker exec container1 cat /var/lib/dhcp/*lease*
```