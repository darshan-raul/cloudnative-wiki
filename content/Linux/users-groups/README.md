---
title: Linux Users & Groups
description: Linux user and group management — /etc/passwd, /etc/shadow, /etc/group, useradd, sudo, PAM
tags:
  - linux
  - users
---

# Linux Users & Groups

Linux is a multi-user operating system. Every file, process, and service has an owner. Understanding users and groups is fundamental to managing access, securing systems, and troubleshooting permission problems.

## User Management

**[[user-management|User Management]]** — The three user databases: `/etc/passwd` (username, UID, GID, home, shell), `/etc/shadow` (password hashes and expiry), and `/etc/group` (group membership). Commands: `useradd`, `usermod`, `userdel`, `passwd`, `groupadd`. System accounts (UID 1-999) vs regular accounts (UID 1000+). The GECOS field and `chfn`.

## Authentication and Sudo

**[[../concepts/04-users-and-groups|sudo]]** — `visudo` for safe sudoers editing. The four fields in a sudoers rule: who, host, runas, commands. `NOPASSWD` for automation, `ALL=(ALL)` for full access, and restricting to specific commands. Environment variables preserved (`env_keep`). The difference between `sudo -i`, `sudo -s`, and `sudo command`.

## Service Accounts

**[[nologin-user|Nologin User]]** — System accounts used by services (www-data, mysql, sshd, nobody). Why they exist and why they use `/usr/sbin/nologin` or `/sbin/nologin` instead of `/bin/false`. How to check which services run as which users: `ps aux` and `grep www-data`.

## Pluggable Authentication Modules

**[[../security/pam|PAM]]** — Pluggable Authentication Modules. The four management groups: `auth` (who are you?), `account` (are you allowed?), `password` (update credentials), `session` (setup/teardown). How `/etc/pam.d/` files chain modules. Common modules: `pam_unix.so` (traditional), `pam_systemd.so` (systemd session), `pam_limits.so` (resource limits via `/etc/security/limits.conf`). Misconfigured PAM is a common cause of "I can't log in but the password is correct" problems.