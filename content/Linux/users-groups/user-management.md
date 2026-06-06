---
title: User Management
description: Linux user management — useradd, usermod, userdel, /etc/passwd, /etc/shadow, /etc/group, UID/GID ranges
tags:
  - linux
---

# User Management

Linux user management is identity control — who can log in, what they can access, and which processes they run. The system maintains user and group identity in flat files (`/etc/passwd`, `/etc/shadow`, `/etc/group`), and each process carries a UID/GID that determines its permissions.

## The Identity Files

### /etc/passwd (world-readable)

```
root:x:0:0:root:/root:/bin/bash
darshan:x:1000:1000:Darshan,,,:/home/darshan:/bin/bash
nginx:x:999:999::/var/lib/nginx:/sbin/nologin
```

Format: `username:password:UID:GID:GECOS:home:shell`
- `password`: `x` means shadow file has the hash
- `UID`: 0=root, 1-999=system accounts, 1000+=regular users
- `GECOS`: full name, office, etc. (comma-separated)
- `shell`: `/sbin/nologin` = cannot log in interactively

### /etc/shadow (root-only)

```
darshan:$6$salt$hash:19000:0:99999:7:::
```

Format: `username:password:last_change:min_age:max_age:warn:expire:reserved`
- `$6$` = SHA-512 hashing (always used on modern Linux)
- Days are from epoch (Jan 1 1970)
- Empty password field = no password needed
- `!!` or `*` = account locked

### /etc/group

```
sudo:x:27:darshan,alice
docker:x:998:darshan
```

Format: `groupname:password:GID:members`

## Managing Users

```bash
# Create user
useradd -m -s /bin/bash -G sudo,docker darshan
#   -m  create home directory
#   -s  login shell
#   -G  supplementary groups
#   -u  specify UID
#   -d  specify home directory
#   -c  GECOS comment

# Modify user
usermod -aG www-data darshan   # append to www-data group (-a is important!)
usermod -s /bin/zsh darshan     # change shell
usermod -L darshan              # lock account (prepend ! to password)
usermod -U darshan              # unlock

# Delete user
userdel -r darshan              # -r removes home directory and mail spool
userdel darshan                 # keep home (if you need the files)

# Set password
passwd darshan
# Non-interactive:
echo "darshan:newpassword" | chpasswd
```

## UID/GID Ranges

| Range       | Purpose                          |
|-------------|----------------------------------|
| 0           | root                             |
| 1-999       | System accounts (daemons, services) |
| 1000-59999  | Regular users (UID_MIN-UID_MAX)  |
| 60000+      | Reserved for users or LDAP/NIS    |

System accounts typically have:
- No login shell (`/sbin/nologin`, `/usr/bin/nologin`, `/bin/false`)
- No real home or `/` as home
- Used by services to run with minimal privileges

## User Private Groups (UPG)

Most Linux distros create a private group for each user (same name as user, GID = UID):

```bash
id darshan
# uid=1000(darshan) gid=1000(darshan) groups=1000(darshan),27(sudo)
```

The primary group is the user's own GID. This makes `umask 0002` safe for shared directories.

## sudo Configuration

```bash
# /etc/sudoers — NEVER edit directly, use visudo

# Basic syntax:
user   host=(runas:group)   commands

# Allow user to run any command as any user
darshan ALL=(ALL:ALL) ALL

# Allow group to run without password
%sudo ALL=(ALL) NOPASSWD: ALL

# Allow user to run specific command as root
darshan ALL=(root) /usr/bin/systemctl restart nginx

# Allow user to run as mysql user without password
darshan ALL=(mysql) NOPASSWD: /usr/bin/mysql

# Same user, no password:
darshan ALL=(ALL) NOPASSWD: ALL
```

## Locked / Nologin Accounts

```bash
# Lock account (can't log in)
usermod -L darshan          # prepends ! to password hash in shadow

# Set nologin shell
usermod -s /sbin/nologin darshan
usermod -s /usr/bin/nologin darshan

# /sbin/nologin vs /bin/false:
# nologin: prints "This account is not available." then exits
# false: just exits with non-zero status (no message)

# Allow nologin user to run specific services:
# (service runs as that user, even if they can't log in)
```

## Listing and Querying

```bash
# Who is logged in?
who
w                     # detailed: what each user is doing
last                  # recent logins (from /var/log/wtmp)
lastb                 # failed login attempts

# User info
id darshan
id                    # current user
whoami                # current username
groups                # current user's groups

# Password aging
chage -l darshan      # show password policy
chage -M 90 darshan   # expire password after 90 days
chage -E 2025-01-01 darshan  # expire account on date
```

## System Users (No Login)

For services, create users without login:

```bash
# Create system account for nginx
useradd -r -s /sbin/nologin -d /var/lib/nginx -c "nginx web server" nginx

# -r: system account (UID in 1-999 range)
# -s: shell (nologin = can't log in)
# -d: home directory
# -c: GECOS comment
```

## The setuid Bit

Some binaries run as the owner UID regardless of who executes them:

```bash
# setuid binary example:
ls -la /usr/bin/sudo
# -rwsr-xr-x 1 root root  27020 ... /usr/bin/sudo
#       ↑ s = setuid bit set

# How it works:
# 1. User "darshan" runs sudo
# 2. Kernel sees setuid bit
# 3. Effective UID becomes 0 (root), real UID stays 1000 (darshan)
# 4. sudo checks if darshan is in /etc/sudoers
# 5. sudo execs the requested command as root
```

Dangerous: setuid binaries are privilege escalation targets. `sudo` itself is the most security-critical setuid binary on Linux.

## LDAP/NIS Integration

In enterprise environments, users come from LDAP (or Active Directory via SSSD):

```bash
# /etc/nsswitch.conf controls where identity comes from:
cat /etc/nsswitch.conf | grep passwd
# passwd:     files systemd mymachines ldap    ← check files first, then LDAP

# When using LDAP:
# - /etc/passwd still exists but has local entries only
# - getpwnam() queries nsswitch: files → LDAP → etc.
# - UID/GID come from LDAP server
```