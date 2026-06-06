---
title: Network Performance Tuning
description: Linux network performance — sysctl tuning, TCP parameters, congestion control, I/O schedulers, ethtool, irqbalance, NIC tuning
tags:
  - linux
  - networking
  - performance
---

# Network Performance Tuning

Network performance tuning covers: kernel TCP/IP parameters (sysctl), NIC offload settings (ethtool), interrupt coalescence, I/O schedulers, and congestion control algorithms.

## sysctl TCP Parameters

Apply via `/etc/sysctl.conf` or `/etc/sysctl.d/99-network-tuning.conf`, then `sysctl -p`.

### TCP Buffers and Windows

```bash
# /etc/sysctl.d/99-network-tuning.conf

# --- TCP buffer sizes (autotuned on most modern kernels) ---
# These are per-connection defaults; kernel auto-tunes around these
net.core.rmem_default = 262144      # default receive buffer
net.core.wmem_default = 262144      # default send buffer
net.core.rmem_max = 16777216        # max receive buffer (16M)
net.core.wmem_max = 16777216        # max send buffer (16M)

# TCP buffer auto-tuning (min, default, max per socket)
net.ipv4.tcp_rmem = 4096 131072 16777216   # min, default, max receive
net.ipv4.tcp_wmem = 4096 16384  16777216   # min, default, max send

# Enable TCP window scaling (extends max window beyond 64K)
net.ipv4.tcp_window_scaling = 1

# Enable timestamps (required for window scaling + PAWS)
net.ipv4.tcp_timestamps = 1

# Enable selective acknowledgements (more efficient than full ACKs)
net.ipv4.tcp_sack = 1

# Increase connection tracking table size (for firewalls/NAT)
net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576
```

### TCP Memory and Connection Limits

```bash
# Increase max socket buffer for all protocols
net.core.optmem_max = 65536

# TCP memory (total buffer for all TCP sockets)
net.ipv4.tcp_mem = 786432 1048576 26777216
# pages: min pressure max

# TCP socket memory pressure thresholds
net.ipv4.tcp_mem = 196608 262144 393216

# Backlog queue length (max pending connections in listen queue)
net.core.somaxconn = 65535

# SYN backlog (max SYN_RECV connections)
net.ipv4.tcp_max_syn_backlog = 65535

# Increase local port range (for outgoing connections)
net.ipv4.ip_local_port_range = 1024 65535

# TCP Fast Open (reduce handshake latency for repeat connections)
net.ipv4.tcp_fastopen = 3          # client + server enabled

# Enable MTU probing (avoid fragmentation)
net.ipv4.tcp_mtu_probing = 1
```

### TCP keepalive (detect dead connections)

```bash
net.ipv4.tcp_keepalive_time = 600      # seconds before first keepalive probe
net.ipv4.tcp_keepalive_intvl = 30      # seconds between probes
net.ipv4.tcp_keepalive_probes = 5      # probes before declaring dead
# Total dead connection detection: 600 + 5*30 = 750 seconds (~12 min)
```

### Connection Tracking (for NAT/firewall-heavy hosts)

```bash
# Increase conntrack table size
net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576

# Hash size (controls memory allocation granularity)
net.netfilter.nf_conntrack_buckets = 262144

# Timeout values (reduce for high-connection hosts)
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 180

# Check current conntrack usage:
cat /proc/sys/net/netfilter/nf_conntrack_count
```

### Congestion Control Algorithms

```bash
# List available algorithms:
sysctl net.ipv4.tcp_available_congestion_control
# Output: reno cubic bbr

# Set default (cubic is default on most Linux)
net.ipv4.tcp_congestion_control = cubic

# BBR (Bottleneck Bandwidth and RTT) — better for high-BDP links
# Enable BBR:
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# For high-latency satellite/multi-Gbps links:
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq_codel

# For low-latency networks:
net.ipv4.tcp_congestion_control = cubic
```

### Queueing Disciplines (qdisc)

```bash
# Default qdisc (applied to all interfaces)
net.core.default_qdisc = fq_codel

# Per-interface override (can also use ethtool):
# fq_codel = fair queue + controlled delay (good for buffers)
# fq = fair queue (good for long-running TCP flows)
# cake = CAKE (more sophisticated than fq_codel)
# noqueue = no queueing (minimal latency, can cause loss)
# sfq = stochastic fair queueing (prevents a single flow hogging)
```

## ethtool — NIC Settings

```bash
# Show NIC info and current settings
ethtool eth0

# Show driver info
ethtool -i eth0
# driver: ixgbe
# version: 5.19.0
# firmware-version: 0x80000000

# Check offload features
ethtool -k eth0
# tcp-segment-offload: on
# generic-receive-offload: on
# generic-segment-offload: on
# rx-checksumming: on
# tx-checksumming: ip: on

# Enable/disable offload features
ethtool -K eth0 gro on gso on tso on
ethtool -K eth0 sg on

# Set ring buffer sizes (receive/transmit descriptors)
ethtool -G eth0 rx 4096 tx 4096

# Show ring sizes
ethtool -g eth0
# RX: 4096
# TX: 4096

# Set interrupt coalescence (reduce IRQ frequency, increase latency)
# Adaptive RX IRQ coalescence:
ethtool -C eth0 adaptive-rx on
# Or fixed values:
ethtool -C eth0 rx-frames 128 tx-frames 128

# Show port speed/duplex/negotiation
ethtool eth0
# Speed: 10Gb/s
# Duplex: Full
# Auto-negotiation: on

# Force speed (hard-coding):
ethtool -s eth0 speed 1000 duplex full autoneg off

# Pause frames (flow control):
ethtool -A eth0 rx on tx on

# Get statistics
ethtool -S eth0
# rx_packets: 12345678
# tx_packets: 9876543
# rx_errors: 0
# tx_errors: 0
```

### Persistent ethtool settings

```bash
# ethtool settings don't persist across reboot
# Add to a startup script or systemd service:

# /etc/systemd/system/ethtool@.service
[Unit]
Description=Ethtool settings for %I
Wants=network-pre.target
Before=network-pre.target
After=sys子系统.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ethtool -G %i rx 4096 tx 4096
ExecStart=/usr/bin/ethtool -C %i adaptive-rx on rx-frames 128
ExecStart=/usr/bin/ethtool -K %i gso on gro on tso on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target

# Enable:
systemctl enable ethtool@eth0
```

## IRQ (Interrupt Request) Tuning

```bash
# Show IRQ affinity (which CPU handles each IRQ)
cat /proc/interrupts | head -30

# List network IRQs:
grep -E "eth|mlx|ixgbe" /proc/interrupts

# Set IRQ affinity (pin NIC IRQ to specific CPU):
# eth0 IRQ is 59:
echo 2 > /proc/irq/59/smp_affinity    # CPU 1 (binary 0010)
echo 4 > /proc/irq/59/smp_affinity    # CPU 2 (binary 0100)
echo 8 > /proc/irq/59/smp_affinity    # CPU 3 (binary 1000)

# Multiqueue NIC: spread IRQs across cores:
for irq in $(grep eth0 /proc/interrupts | cut -d: -f1 | tr -d ' '); do
    cpu=$((irq % $(nproc)))
    echo $((1 << cpu)) > /proc/irq/$irq/smp_affinity
done

# irqbalance daemon (auto-distributes IRQs):
systemctl enable --now irqbalance

# Check irqbalance:
cat /proc/irq/default_smp_affinity
```

## ss — Socket Statistics

```bash
# ss replaces netstat — shows socket state
ss -tulnp              # TCP and UDP listening sockets with process
ss -tunlp              # UDP
ss -s                  # summary statistics
ss -ti                 # TCP info (RTT, congestion window)
ss -t state established  # only established connections

# Show all connections with timers:
ss -ti

# Show socket memory usage:
ss -m

# Show process using a port:
ss -tlnlp | grep :443
```

## High-Connection Host Tuning

For hosts with 100K+ concurrent connections (load balancers, proxies):

```bash
# /etc/sysctl.d/99-high-conn.conf

# File descriptors
fs.file-max = 2097152
fs.nr_open = 2097152

# TCP connection tracking
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_buckets = 524288

# Increase local port range
net.ipv4.ip_local_port_range = 1024 65535

# Socket backlog
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# TCP reuse (for servers handling many short-lived connections)
net.ipv4.tcp_tw_reuse = 1

# TCP fast recycle of TIME_WAIT
net.ipv4.tcp_fin_timeout = 15

# Increase max orphan sockets (sockets not attached to a process)
net.ipv4.tcp_max_orphans = 262144

# Increase TCP memory
net.ipv4.tcp_mem = 786432 1048576 26777216
```

## Quick Reference

```bash
# Apply tuning
sysctl -p /etc/sysctl.d/99-network-tuning.conf

# Verify settings
sysctl net.ipv4.tcp_window_scaling
sysctl net.ipv4.tcp_sack
sysctl net.core.default_qdisc

# NIC info
ethtool eth0
ethtool -i eth0
ethtool -k eth0
ethtool -S eth0

# IRQ affinity
cat /proc/interrupts | grep eth0
cat /proc/irq/*/smp_affinity 2>/dev/null | head -5

# Socket stats
ss -s
ss -tulnp
ss -ti state time-wait
```