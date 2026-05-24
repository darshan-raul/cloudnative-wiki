---
title: Forensics
tags: [incident-response, forensics, malware, memory-analysis, disk-imaging]
date: 2025-05-24
description: Digital forensics procedures - memory acquisition, disk imaging, log analysis, and evidence preservation
---

# Forensics 🔬

Digital forensics for preserving evidence and reconstructing events.

## Core Principles

- **Write blocking** — Never write to the evidence drive directly
- **Chain of custody** — Document every person who touches the evidence
- **Hash everything** — Verify integrity with SHA-256 hashes at every step
- **Order of volatility** — Collect most volatile data first: CPU registers, memory, then disk

## Order of Volatility

```
1. CPU registers, cache
2. Memory (RAM)
3. Network connections, process table
4. Disk
5. Logs, remote systems
6. Paper documents
```

## Memory Acquisition

```bash
# Linux: acquire memory with LiME
sudo insmod lime.ko "path=/mnt/memory.lime format=lime"

# Or via AVML (Azure VM Memory)
avml memory.lime

# Calculate hash
sha256sum memory.lime > memory.lime.sha256
```

## Disk Imaging

```bash
# Create raw image (use write blocker)
sudo dd if=/dev/sda of=/mnt/evidence/disk.image bs=4M status=progress

# Create compressed E01 image with FTK Imager
ftkimager /dev/sda evidence.e01 --compress 9

# Verify hash
sha256sum disk.image
```

## Memory Analysis

### Volatility

```bash
# Identify memory profile
vol -f memory.lime imageinfo

# List processes
vol -f memory.lime pslist

# Network connections
vol -f memory.lime netscan

# Find malicious processes
vol -f memory.lime malfind -p <pid>
```

## Log Analysis

```bash
# Timeline creation
cat /var/log/syslog /var/log/auth.log | sort > timeline.txt

# Find suspicious commands
grep -E "wget|curl|nc|bash" auth.log | sort | uniq -c | sort -rn

# Find persistence mechanisms
grep -rE "cron|systemd|init" /etc/ /var/spool/cron/
```

## Evidence Preservation

```bash
# Create evidence manifest
find /mnt/evidence -type f -exec sha256sum {} \; > manifest.sha256

# Export relevant logs
tar -czvf logs.tar.gz /var/log/syslog /var/log/auth.log /var/log/kern.log

# Screenshot original state (for cloud VMs)
aws ec2 describe-instance-status --instance-id <id>
```

## Related

- [[Security/incident-response/README|IR Hub]]
- [[Security/endpoint-security/README|Endpoint Security]]