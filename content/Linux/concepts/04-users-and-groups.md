---
title: "04 — Users and Groups"
description: Linux users and groups — /etc/passwd, /etc/shadow, /etc/group, useradd, usermod, sudo, uid, gid
tags:
  - linux
  - concepts
---

# 04 — Users and Groups

Linux is multi-user. Users and groups are the primary mechanism for separating privileges and access. Understanding /etc/passwd, /etc/shadow, and /etc/group is essential for managing access.

## The Three Key Files

### /etc/passwd — User Database

```bash
cat /etc/passwd
# root:x:0:0:root:/root:/bin/bash
# daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
# darshan:x:1000:1000:Darshan,,,:/home/darshan:/bin/bash
# sshd:x:122:65534::/run/sshd:/usr/sbin/nologin

# Format:
# username:password:uid:gid:gecos:home:shell
```

Fields:
- **username** — login name
- **password** — `x` means the real hash is in `/etc/shadow`
- **UID** — numeric user ID (0 = root, 1-999 = system accounts, 1000+ = regular users)
- **GID** — primary group ID
- **GECOS** — full name, room, phone, etc. (comma-separated)
- **home** — home directory path
- **shell** — login shell (usually /bin/bash, /bin/false, or /usr/sbin/nologin)

### /etc/shadow — Password Hashes

```bash
sudo cat /etc/shadow
# root:$6$salt$hash:19452:0:99999:7:::
# darshan:$6$salt$hash:19452:0:99999:7:::
# mysql:!*:19452::::::
# ! means locked, * means no password possible

# Format:
# username:password:last_change:min_age:max_age:warn:expire:disabled
```

Fields:
- **password** — `$algo$salt$hash` or `!` (locked) or `*` (no login)
- **last_change** — days since Jan 1 1970 since password last changed
- **min_age** — days before password can be changed
- **max_age** — days before password must be changed (99999 = never)
- **warn** — days before expiry to warn user
- **expire** — days since epoch when account expires
- **disabled** — days after expiry before account is disabled

### /etc/group — Group Membership

```bash
cat /etc/group
# root:x:0:
# sudo:x:27:darshan,alice
# docker:x:1001:darshan,bob
# developers:x:1002:darshan

# Format:
# groupname:password:gid:members
```

A user can belong to multiple groups. The `members` field lists **secondary** members — the primary group is stored in the GID field in /etc/passwd.

## Adding and Managing Users

```bash
# Create user (with home directory and default settings):
sudo useradd -m darshan

# Create with specific UID, home, shell:
sudo useradd -u 1500 -d /home/custom -s /bin/zsh darshan

# Create system account (no home, no login):
sudo useradd -r -s /usr/sbin/nologin nginx

# Set password:
sudo passwd darshan

# Lock account (disable login):
sudo usermod -L darshan
# Adds ! to front of password hash in /etc/shadow

# Unlock:
sudo usermod -U darshan

# Add to group:
sudo usermod -aG sudo darshan    # -a = append (don't remove from other groups)
sudo usermod -aG docker darshan

# Set expiry:
sudo usermod -e 2025-12-31 darshan  # account expires Dec 31 2025
sudo usermod -e '' darshan            # no expiry

# Change login shell:
sudo usermod -s /bin/zsh darshan

# Change home directory:
sudo usermod -d /new/home -m darshan  # -m moves existing files

# Delete user:
sudo userdel darshan                   # keep home directory
sudo userdel -r darshan               # delete home directory too
```

## The Difference Between nologin and false

```bash
# /usr/sbin/nologin — prints "This account is currently not available"
# Used for service accounts — they exist but can't log in interactively
# /bin/false — just exits immediately with exit code 1
# Never use /bin/false for service accounts — some services check exit code
# Use /usr/sbin/nologin or /sbin/nologin

# Check what a service account uses:
grep sshd /etc/passwd
# sshd:x:122:65534::/run/sshd:/usr/sbin/nologin
```

## Sudo — Temporary Root Privileges

```bash
# Install sudo (on minimal distros):
apt install sudo     # Debian/Ubuntu
pacman -S sudo       # Arch/Manjaro

# Add user to sudo group:
sudo usermod -aG sudo darshan

# Configure sudo access:
sudo visudo
```

### visudo — Editing sudoers Safely

```bash
# /etc/sudoers — NEVER edit directly, use visudo
# visudo locks the file and checks syntax before saving

# Grant user full sudo:
darshan ALL=(ALL:ALL) ALL

# Grant user sudo without password:
darshan ALL=(ALL) NOPASSWD: ALL

# Grant user specific commands only:
darshan ALL=(ALL) /usr/bin/systemctl restart nginx

# Grant group sudo:
%sudo ALL=(ALL:ALL) ALL

# Allow sudo from specific host only:
darshan webserver=(ALL) ALL

# Environment preserved:
Defaults env_keep += "http_proxy https_proxy"
```

## id — Check User and Group Identity

```bash
id darshan
# uid=1000(darshan) gid=1000(darshan) groups=1000(darshan),4(adm),24(cdrom),27(sudo)

id
# shows current user

# Check if user is in a group:
groups darshan
groups     # current user's groups

# Check group members:
getent group sudo
```

## System vs Regular Accounts

```bash
# System accounts (UID 1-999):
# Created automatically, used by services, no home, no login shell
# Examples: root (0), daemon (1), www-data (33), nobody (65534)

# UID ranges:
# 0         = root
# 1-999     = system accounts (services, daemons)
# 1000-99999 = regular user accounts
# 65534     = nobody (used by NFS and services that don't need a real account)

# Regular vs system user in useradd:
useradd -r mysql    # system account (no home, UID in system range)
useradd darshan     # regular user (UID >= 1000)
```

## Quick Reference

```bash
# Read user data
cat /etc/passwd
sudo cat /etc/shadow
cat /etc/group

# Identity
id
id darshan
groups
groups darshan

# User management
useradd -m darshan
passwd darshan
usermod -aG group user    # add to group
usermod -L user           # lock account
usermod -U user           # unlock
userdel -r user           # delete with home dir

# Sudo
sudo command
sudo -u otheruser command
sudo -i                  # become root shell
sudo visudo              # edit sudoers file

# Check who's logged in
who
w
last
lastlog
```