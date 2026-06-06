---
title: Linux Troubleshooting
description: Linux troubleshooting methodology and common issues — network, disk, services, processes, OOM, systematic debugging framework
tags:
  - linux
---

# Linux Troubleshooting

When something breaks on a Linux system, having a repeatable methodology matters more than knowing every command. The systematic approach in [[systematic-debugging]] gives you a framework that works for any problem — from a failing service to a network outage to mysterious CPU spikes.

## Methodology

**[[systematic-debugging|Systematic Debugging]]** — A five-phase approach: gather information, form a hypothesis, design a test, execute and observe, document and resolve. How to narrow down the problem space quickly by asking "what changed recently?" and "does it work in isolation?" The importance of having baselines — knowing what "normal" looks like before something breaks.

## Common Issues

**[[common-issues|Common Issues]]** — The problems every sysadmin hits eventually, and how to solve them:

- **Disk full** — `df -h` to find which partition, `du -sh /*` to find the biggest directories, `lsof +L1` for deleted files still held open by processes
- **OOM kills** — `dmesg | grep -i "out of memory"` or `journalctl -xb | grep -i "killed process"`, what oom_score_adj controls
- **Service won't start** — `systemctl status`, `journalctl -u service -n 50`, check the PID file, check the socket (for socket-activated services)
- **Network unreachable** — `ip addr`, `ip route`, `ping 8.8.8.8`, `ping gateway`, `ss -tlnp`, `journalctl -u NetworkManager`
- **High CPU** — `top` or `htop`, find the runaway process, check if it's expected or a fork bomb
- **Permission denied** — `ls -la`, check ACLs with `getfacl`, verify the service user has access, check SELinux/AppArmor
- **Can't SSH** — `systemctl status sshd`, `journalctl -u sshd`, `ss -tlnp | grep ssh`, check `/etc/ssh/sshd_config`, check `/var/log/auth.log` for failed attempts
- **Package broken** — `dpkg --configure -a`, `apt --fix-broken install`, `apt-get -f install`

## Tools Reference

Every troubleshooting session uses the same toolkit:

```
journalctl -u service   # service logs
ss -tlnp              # listening ports and the process using them
lsof -i -P -n         # all network connections + process
lsof +L1              # files deleted but still open (disk full investigation)
fuser -v 80/tcp       # what process is using port 80
ip addr              # interface state and IPs
ip route             # routing table and gateway
ping 8.8.8.8         # basic connectivity test
curl -I http://...    # test HTTP when ping works but browser doesn't
strace -p PID         # what is this process actually doing
dmesg -T             # kernel ring buffer with human-readable timestamps
```