---
title: Netplan
description: Netplan — YAML network configuration for systemd-networkd and NetworkManager, networkd backend, renderer
tags:
  - linux
  - networking
---

# Netplan

Netplan is Ubuntu's declarative network configuration layer. You write YAML configs describing what network state you want, and Netplan generates the corresponding configuration for either **systemd-networkd** or **NetworkManager** (the "renderer").

## The Idea

```
Traditional:  /etc/network/interfaces → ifupdown → kernel
Modern:       Netplan YAML → netplan generate → systemd-networkd OR NetworkManager
```

Netplan appeared in Ubuntu 17.10 and replaced the old `/etc/network/interfaces` approach.

## Config Files

```bash
# Where configs live:
ls /etc/netplan/
# 00-installer-config.yaml   # created by Ubuntu installer
# 50-cloud-init.yaml         # cloud-init networking

# Additional drop-in directories (less common):
/etc/netplan/
/run/netplan/
/lib/netplan/
```

Files are processed in **lexicographic order**, later files override earlier ones.

## Basic YAML Format

```yaml
# /etc/netplan/01-config.yaml
network:
  version: 2
  renderer: networkd     # or: NetworkManager
  ethernets:
    eth0:
      dhcp4: yes
      # or for static:
      # addresses:
      #   - 192.168.1.100/24
      # gateway4: 192.168.1.1          # deprecated, use routes
      # nameservers:
      #   addresses:
      #     - 8.8.8.8
      #     - 1.1.1.1
```

## Netplan and systemd-networkd (Server/Headless)

Best for servers — minimal, no GUI dependency:

```yaml
# /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.1.100/24
      gateway4: 192.168.1.1               # deprecated, use routes:
      # routes:
      #   - to: 0.0.0.0/0
      #     via: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
        search:
          - home.local
```

## Netplan and NetworkManager (Desktop)

Best for desktops/laptops — NM handles WiFi, VPN, etc.:

```yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    eth0:
      dhcp4: yes
      dhcp6: yes
    wlan0:
      dhcp4: no
      addresses:
        - 192.168.2.100/24
      gateway4: 192.168.2.1
      nameservers:
        addresses:
          - 8.8.8.8
```

## Generating and Applying

```bash
# Generate backend configs from YAML (dry run)
sudo netplan generate

# Apply configuration (replaces current network config)
sudo netplan apply

# Debug
sudo netplan apply --debug

# If something breaks:
# 1. Check generated config:
ls /run/systemd/network/
cat /run/systemd/network/10-netplan-eth0.network

# 2. Revert to previous (reboot or systemctl restart)
systemctl restart systemd-networkd
```

## Routes in Netplan

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses:
        - 10.0.0.10/24
      routes:
        - to: 0.0.0.0/0
          via: 10.0.0.1
          metric: 100                    # lower = preferred
        - to: 192.168.0.0/16
          via: 10.0.0.254
          metric: 200
```

## VLANs in Netplan

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses:
        - 192.168.1.10/24
  vlans:
    eth0.100:
      id: 100
      link: eth0
      addresses:
        - 10.0.100.10/24
```

## Bonds in Netplan

```yaml
network:
  version: 2
  renderer: networkd
  bonds:
    bond0:
      interfaces: [eth0, eth1]
      addresses:
        - 192.168.1.100/24
      gateway4: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
      parameters:
        mode: 802.3ad                    # LACP
        transmit-hash-policy: layer2
        mii-monitor-interval: 100ms
```

## WiFi in Netplan (with NetworkManager)

```yaml
network:
  version: 2
  renderer: NetworkManager
  wifis:
    wlan0:
      dhcp4: true
      access-points:
        "MyHomeWiFi":
          password: "supersecret"
      nameservers:
        addresses:
          - 8.8.8.8
```

## Complete Example: Two NICs, Different Networks

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
    eth1:
      addresses:
        - 10.0.0.10/24
      routes:
        - to: 0.0.0.0/0
          via: 10.0.0.1
          metric: 100
      nameservers:
        addresses:
          - 10.0.0.53
        search:
          - internal.corp
```

## Common Gotchas

```bash
# 1. IP not applying — netplan generate + apply
# netplan apply doesn't always reload; generate first
sudo netplan generate && sudo netplan apply

# 2. YAML indentation matters (2 spaces, no tabs!)
# Indent with spaces only

# 3. Missing routes — gateway4 is deprecated
# Use the routes: - to: 0.0.0.0/0 via: X.X.X.X

# 4. NetworkManager vs networkd mismatch
# If renderer is NetworkManager but NM isn't running:
systemctl enable --now NetworkManager
```