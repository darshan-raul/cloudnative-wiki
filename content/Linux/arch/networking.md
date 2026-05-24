---
title: Arch Linux Networking
---

# 5. Networking

## NetworkManager

NetworkManager is the standard for desktop Arch/Manjaro. It handles WiFi, Ethernet, VPN, and mobile broadband.

```bash
# Install
pacman -S networkmanager

# Enable
systemctl enable NetworkManager
systemctl start NetworkManager

# CLI (nmtui for TUI, nmcli for CLI)
nmtui                          # Text UI
nmcli device wifi list         # List WiFi networks
nmcli device wifi connect <SSID> password <pwd>
nmcli connection up <name>     # Connect to saved profile
nmcli connection down <name>   # Disconnect

# Hotspot
nmcli device wifi hotspot <SSID> <password>
```

### NetworkManager Config

```bash
# Connection files: /etc/NetworkManager/system-connections/
# Or via GUI: nmtui -> Edit a connection

# Key files:
# /etc/NetworkManager/NetworkManager.conf
[main]
dns=default
rc-manager=auto

# Disable a specific interface
# /etc/NetworkManager/conf.d/99-unmanaged.conf
[device]
match-device=interface-name:eth0
managed=false
```

## wpa_supplicant (Lightweight Alternative)

For CLI-only or minimal setups without NetworkManager:

```bash
# Install
pacman -S wpa_supplicant

# Config
cat > /etc/wpa_supplicant/wpa_supplicant.conf << EOF
ctrl_interface=/run/wpa_supplicant
ctrl_interface_group=wheel
update_config=1

network={
    ssid="MyNetwork"
    psk="password"
}
EOF

# Run
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
dhcpcd wlan0
```

## dhcpcd

DHCP client for automatic IP assignment.

```bash
# Install
pacman -S dhcpcd

# Enable per interface
systemctl enable dhcpcd@wlan0

# Config: /etc/dhcpcd.conf
interface wlan0
  static ip_address=192.168.1.100/24
  static routers=192.168.1.1
  static domain_name_servers=1.1.1.1 8.8.8.8
```

## netplan (via systemd-networkd)

Arch can use netplan on top of systemd-networkd for declarative config:

```bash
pacman -S systemd-netplan

# /etc/netplan/config.yaml
network:
  version: 2
  renderer: networkd
  wifis:
    wlan0:
      dhcp4: true
      access-points:
        "MySSID":
          password: "secret"
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8

# Apply
netplan generate
netplan apply
```

## Firewalls: nftables

nftables is the modern replacement for iptables on Arch (default in Fedora/Debian).

```bash
# Install
pacman -S nftables

# Enable
systemctl enable nftables

# Config: /etc/nftables.conf
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;

    # Accept established connections
    ct state established,related accept

    # Accept loopback
    iif lo accept

    # Accept ICMP
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

    # Accept SSH (port 22)
    tcp dport 22 accept

    # Accept HTTP/HTTPS
    tcp dport { 80, 443 } accept

    # Log dropped
    counter drop
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}

# Commands
nft -f /etc/nftables.conf   # Load rules
nft list ruleset             # Show current rules
nft flush ruleset            # Clear all rules
```

## iptables (Legacy)

Still common, but Arch recommends nftables going forward.

```bash
pacman -S iptables

systemctl enable iptables

# Save rules
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6
```

## UFW (Uncomplicated Firewall)

Simpler frontend for iptables:

```bash
pacman -S ufw

systemctl enable ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp        # SSH
ufw allow 80/tcp        # HTTP
ufw allow 443/tcp       # HTTPS

ufw enable
ufw status verbose
```

## DNS Caching

### dnsmasq

```bash
pacman -S dnsmasq

# Config: /etc/dnsmasq.conf
listen-address=127.0.0.1
bind-interfaces
cache-size=1000
server=1.1.1.1
server=8.8.8.8

systemctl enable dnsmasq
systemctl restart dnsmasq

# Tell NetworkManager to use it
# /etc/NetworkManager/conf.d/dnsmasq.conf
[main]
dns=127.0.0.1
```

### unbound

```bash
pacman -S unbound

# /etc/unbound/unbound.conf
server:
  port: 53
  interface: 127.0.0.1
  access-control: 127.0.0.0/8 allow
  cache-min-ttl: 3600
  prefetch: yes

  forward-zone:
    name: "."
    forward-addr: 1.1.1.1
    forward-addr: 8.8.8.8

systemctl enable unbound
```

## DNS-over-HTTPS (DoH)

### cloudflared

```bash
pacman -S cloudflared

# Config
cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare DNS over HTTPS
After=network.target

[Service]
ExecStart=/usr/bin/cloudflared proxy-dns --port 53 --upstream https://1.1.1.1/dns-query
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable cloudflared
systemctl start cloudflared
```

## Samba (File Sharing)

```bash
pacman -S samba smbnetfs

# Config: /etc/samba/smb.conf

[global]
  workgroup = WORKGROUP
  server string = Arch Server
  security = user
  encrypt passwords = yes
  dns proxy = no

[public]
  path = /srv/samba/public
  browseable = yes
  read only = no
  create mask = 0664
  directory mask = 0775
  force user = nobody

# Create share directory
mkdir -p /srv/samba/public
chmod 777 /srv/samba/public

# Enable
systemctl enable smb nmb
systemctl start smb nmb

# Add user (must have system account)
smbpasswd -a <username>
```

## NFS (Network File System)

```bash
pacman -S nfs-utils

# Enable
systemctl enable nfs-server
systemctl start nfs-server

# Server exports: /etc/exports
/srv/nfs  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

# Reload exports
exportfs -ra

# Client
mount -t nfs 192.168.1.10:/srv/nfs /mnt/nfs

# Auto-mount: /etc/fstab
192.168.1.10:/srv/nfs  /mnt/nfs  nfs  defaults,_netdev  0  0
```

## VPN: WireGuard

```bash
pacman -S wireguard-tools

# Generate keys
wg genkey | tee privatekey | wg pubkey > publickey

# Server config: /etc/wireguard/wg0.conf
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <client-public-key>
AllowedIPs = 10.0.0.2/32

# Client config
[Interface]
Address = 10.0.0.2/24
PrivateKey = <client-private-key>
DNS = 1.1.1.1

[Peer]
PublicKey = <server-public-key>
Endpoint = <server-ip>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

# Enable
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
```

## OpenVPN

```bash
pacman -S openvpn

# Import config
cp /path/to/config.ovpn /etc/openvpn/client.conf

systemctl enable openvpn-client@client
systemctl start openvpn-client@client

# NetworkManager integration
pacman -S NetworkManager-openvpn
```

## Network Troubleshooting

```bash
# List interfaces
ip link
ip addr show

# Test connectivity
ping 1.1.1.1
curl -I https://archlinux.org

# DNS check
resolvectl status
dig archlinux.org

# Port scan
ss -tlnp              # Listening ports
netstat -tulnp

# Trace route
traceroute 8.8.8.8
tracepath archlinux.org

# Monitor bandwidth
nethogs
iftop

# ARP table
ip neigh show

# Check DNS resolution
getent hosts archlinux.org
cat /etc/resolv.conf
```

## NetworkManager CLI Quick Reference

```bash
nmcli device status                    # Show all devices
nmcli connection show                  # Show all connections
nmcli connection add type ethernet ifname eth0 con-name "Wired connection 1"
nmcli connection modify "Wired connection 1" ipv4.addresses "192.168.1.100/24"
nmcli connection modify "Wired connection 1" ipv4.gateway "192.168.1.1"
nmcli connection modify "Wired connection 1" ipv4.dns "1.1.1.1,8.8.8.8"
nmcli connection modify "Wired connection 1" ipv4.method manual
nmcli connection up "Wired connection 1"
```