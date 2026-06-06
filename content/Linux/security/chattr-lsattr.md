---
title: chattr and lsattr
description: Linux chattr and lsattr — immutable files, append-only, file attributes, filesystem attributes
tags:
  - linux
  - security
---

# chattr and lsattr

`chattr` changes **filesystem attributes** (not permissions), and `lsattr` displays them. These attributes control special behaviors like immutability (can't delete even as root) and append-only mode.

## The Attributes

| Attribute | Letter | Meaning |
|-----------|--------|---------|
| Immutable | `i` | Cannot delete, rename, or modify (even as root) |
| Append-only | `a` | Can only append (write at end of file) |
| No dump | `d` | Excluded by `dump(8)` backup |
| Compressed | `c` | Kernel auto-compresses on write, decompress on read |
| Synchronous | `s` | Writes are synchronous (written to disk immediately) |
| Undeletable | `u` | File contents saved when deleted (undelete possible) |
| No atime | `A` | Don't update atime on access |
| No copy on write | `C` | CoW disabled (btrfs only) |
| Indexed directory | `I` | Directory uses HTree indexed (ext4) |
| No update of dir atime | `D` | Synchronous dir updates |

## Viewing: lsattr

```bash
lsattr file.txt
# -------------e- file.txt
# ----a-------e- file.txt   ← append-only
# ---i---------e- file.txt  ← immutable

# Recursive
lsattr -R /var/log/
lsattr -a /etc/shadow
```

## Changing: chattr

### Immutable (`+i`)

The most important attribute. Once set, **even root cannot modify, delete, or rename** the file until immutable is removed:

```bash
# Make immutable
chattr +i /etc/resolv.conf
# Now even root can't change it:
echo "nameserver 8.8.8.8" > /etc/resolv.conf
# bash: /etc/resolv.conf: Operation not permitted

# Remove immutable
chattr -i /etc/resolv.conf

# Recursive
chattr -R +i /etc/important/
```

Use cases:
- `/etc/resolv.conf` after configuring DNS (prevents accidental or malicious changes)
- `/etc/passwd` and `/etc/shadow` after hardening (prevents privilege escalation)
- Boot-critical files
- Logs you want to protect from tampering (in conjunction with auditd)

### Append-only (`+a`)

File can only be opened in append mode — data can only be added, not overwritten:

```bash
# Append-only log
chattr +a /var/log/mylog.log

# Now:
echo "line 1" > /var/log/mylog.log     # PERMISSION DENIED
echo "line 1" >> /var/log/mylog.log    # WORKS

# Useful for audit logs — can only grow, not be edited
```

### Combining Attributes

```bash
# Append-only AND immutable (immutable overrides — nothing can change)
chattr +i +a /var/log/secure.log
# This is quite extreme — you can only remove +i first

# Useful: no atime update
chattr +A /var/log/app.log
# Access time not updated = better performance on frequently-read files
```

## Root and Immutability

Even root is blocked by immutable:

```bash
chattr +i /etc/shadow
# As root:
rm /etc/shadow
# rm: cannot remove '/etc/shadow': Operation not permitted
chattr -i /etc/shadow
# Now removable
```

**This is a security feature** — ransomware can't encrypt immutable files if you set them before the attack.

## Common Use Cases

### Protect /etc/shadow

```bash
chattr +i /etc/shadow
chattr +i /etc/passwd
# (Note: some systems need to modify these — test first!)
```

### Protect resolv.conf (DHCP overwrite prevention)

```bash
# After configuring static DNS:
chattr +i /etc/resolv.conf

# Now DHCP won't overwrite it (DHCP client needs to be configured to respect this)
```

### Secure audit logs

```bash
# Make audit logs append-only
chattr +a /var/log/audit/audit.log
# auditd can still append, but attacker can't modify past entries
```

### Recovery: accidentally set immutable on system file

```bash
# If you accidentally make a system file immutable:
# Boot from recovery media or single user mode
chattr -i /path/to/file

# Or if you can still run commands:
sudo chattr -i /etc/passwd
```

## Security Note

chattr does NOT protect against some attacks:
- **Root can still remove +i** — if root account is compromised, attacker removes immutable
- **Does not prevent deletion of parent directory** (only the file itself)
- **Does not encrypt** — just prevents modification
- **btrfs has additional attributes** like `C` (no CoW) for SSD alignment

## Quick Reference

```bash
# View
lsattr file
lsattr -R .    # recursive
lsattr -a .    # include hidden files

# Set attributes
chattr +i file       # immutable
chattr -i file       # remove immutable
chattr +a file       # append-only
chattr -a file       # remove append-only
chattr +A file       # no atime update
chattr +s file       # synchronous writes
chattr +u file       # undeletable

# Combine
chattr +i +a file    # immutable + append-only
```