---
title: apt
description: Debian/Ubuntu apt — package management, /etc/apt/sources.list, apt-cache, dpkg, repositories
tags:
  - linux
  - packaging
---

# apt

`apt` (Advanced Package Tool) is the front-end to Debian's package management system. It resolves dependencies, fetches packages from configured repositories, and installs/removes packages. `dpkg` is the lower-level tool that actually installs `.deb` files.

## apt vs apt-get vs apt-cache

```bash
# apt-get: lower-level, scripting-safe
apt-get update
apt-get install nginx
apt-get upgrade
apt-get dist-upgrade

# apt: higher-level, interactive-friendly (what you use day-to-day)
apt update
apt install nginx
apt remove nginx
apt search nginx
apt show nginx
apt list --upgradable
apt autoremove

# apt-cache: query the package cache
apt-cache policy nginx           # show available versions
apt-cache show nginx            # package description
apt-cache depends nginx         # dependencies
apt-cache rdepends nginx        # reverse dependencies
apt-cache madison nginx         # all versions in all repos
```

## sources.list

```bash
# Main sources.list
cat /etc/apt/sources.list

# Additional source files
ls /etc/apt/sources.list.d/
# Per-repository .list files (or .sources for deb822 format)
```

### Format (traditional)

```
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse

deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
```

### Components

| Component    | Meaning                                              |
|-------------|------------------------------------------------------|
| main        | Free software supported by Ubuntu                    |
| restricted  | Proprietary drivers, etc.                           |
| universe   | Community-maintained free software                  |
| multiverse | Restricted by copyright/legal                        |

### deb-src lines

`deb-src` lines provide **source packages** (`.dsc`, `.orig.tar.gz`, `.debian.tar.gz`). You need them for `apt source package` or `dpkg-source`.

```bash
# Enable source packages:
# In /etc/apt/sources.list or via UI:
# deb-src http://archive.ubuntu.com/ubuntu/ jammy main restricted

apt update
apt source nginx   # downloads source package to current directory
```

## Managing Packages

```bash
# Install/remove
apt install nginx
apt install nginx=1.18.0     # specific version
apt install ./package.deb    # local .deb file
apt remove nginx             # remove but keep config
apt purge nginx              # remove AND delete config files
apt autoremove              # remove orphaned dependencies

# Update everything
apt update                   # refresh package lists
apt upgrade                  # safe upgrades only (no new deps)
apt dist-upgrade             # handles dependency changes, removes conflicts

# Hold a package (prevent upgrade)
apt-mark hold nginx
apt-mark showhold
apt-mark unhold nginx
```

## Repositories

### PPA (Personal Package Archive)

```bash
# Ubuntu: add a PPA (hosted on launchpad.net)
add-apt-repository ppa:nginx/stable
apt update
apt install nginx

# The ppa: URI is shorthand for:
# deb http://ppa.launchpad.net/nginx/stable/ubuntu jammy main
```

### Third-Party Repos

```bash
# Example: Kubernetes apt repo
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
apt update
apt install kubelet kubeadm kubectl
```

## Viewing Package Info

```bash
apt show nginx                # detailed package info
apt-cache policy nginx        # versions available
dpkg -l nginx                # installed version (-l = list)
dpkg -L nginx                # files installed by nginx
dpkg -S /etc/nginx/nginx.conf # which package owns a file
```

## /var/lib/dpkg

```bash
# dpkg's database
ls /var/lib/dpkg/
# info/     — postinst/prerm scripts and info
# alternatives/ — alternatives system
# status    — package states (installed, config-files, etc.)
# available  — available package info

# Manual database manipulation (rare, dangerous)
dpkg --configure -a          # fix interrupted install
dpkg --audit                 # show partially installed
```

## Package Dependencies

```bash
# What's needed to install nginx?
apt-cache depends nginx
# nginx Depends: nginx-core
# nginx Depends: libssl3
# nginx Depends: zlib1g
# ...

# What requires nginx?
apt-cache rdepends nginx
```

## apt-key (deprecated, use trusted.gpg.d)

```bash
# Old way (deprecated — keys stored in /etc/apt/trusted.gpg):
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys XXXXXXXX

# New way: put .gpg files in /etc/apt/trusted.gpg.d/
curl -fsSL https://repo.example.com/key.gpg | gpg --dearmor -o /etc/apt/trigned.gpg.d/repo.gpg

# Or use signed-by in sources.list (deb822 format, preferred):
# deb [signed-by=/etc/apt/trusted.gpg.d/repo.gpg] https://repo.example.com stable main
```

## Signed-By Security

Modern apt uses `signed-by` to cryptographically bind a repo to its key:

```bash
# /etc/apt/sources.list.d/myrepo.list (deb822 format)
Types: deb
URIs: https://repo.example.com
Suites: stable
Components: main
Signed-By: /etc/apt/trusted.gpg.d/myrepo.gpg
```

This prevents repo hijacking — if the repo URL is compromised, apt won't accept packages from it without the matching private key.

## Clean Up

```bash
# Remove downloaded .deb packages from cache
apt clean                    # removes all
apt-get clean               # same

# Remove packages no longer needed
apt autoremove

# Remove old kernels (on Ubuntu)
apt autoremove --purge linux-headers-$(uname -r) linux-image-$(uname -r)
```