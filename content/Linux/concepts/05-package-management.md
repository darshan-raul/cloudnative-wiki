---
title: "05 — Package Management"
description: Linux package managers — apt, pacman, dnf — how packages work, installing, updating, removing, repositories
tags:
  - linux
  - concepts
---

# 05 — Package Management

Linux software comes in packages — compressed archives containing binaries, libraries, configs, and metadata. The package manager installs, updates, and removes them, and tracks dependencies so everything works together.

## The Two Biggest Ecosystems

```
Debian/Ubuntu    →  apt, dpkg
Arch/Manjaro     →  pacman
RHEL/CentOS/Fedora →  dnf (formerly yum)
Alpine            →  apk
Slackware         →  pkgtools
```

All package managers do the same thing, just with different commands and package formats.

## apt (Debian/Ubuntu)

### Basics

```bash
# Update package lists (always run before installing):
sudo apt update

# Install a package:
sudo apt install nginx

# Remove a package:
sudo apt remove nginx
sudo apt purge nginx       # remove + config files

# Update all packages:
sudo apt upgrade

# Full distribution upgrade (can remove packages):
sudo apt full-upgrade

# Search:
apt search nginx
apt-cache search nginx

# Show package info:
apt show nginx
apt-cache show nginx

# Which package provides this file?
dpkg -S /usr/bin/ls
apt-file search /usr/bin/ls

# Install a .deb file directly:
sudo dpkg -i package.deb
sudo apt install ./package.deb   # resolves dependencies
```

### Dependency Resolution

```bash
# apt resolves dependencies automatically.
# Package A depends on B and C → apt installs all three.

# Check what would be installed without installing:
apt install --simulate nginx

# Fix broken dependencies:
sudo apt install -f
# Or:
sudo dpkg --configure -a
```

### Clean Up

```bash
sudo apt autoremove          # remove packages installed as dependencies but no longer needed
sudo apt autoclean           # remove downloaded .deb files from cache
sudo apt clean               # clear entire apt cache
```

### Package Cache

```bash
# /var/cache/apt/archives/ — downloaded .deb files live here
ls /var/cache/apt/archives/

# apt keeps multiple versions — clear old ones:
sudo apt clean
sudo apt-get clean
```

## pacman (Arch/Manjaro)

### Basics

```bash
# Sync databases:
sudo pacman -Sy

# Install:
sudo pacman -S nginx

# Remove:
sudo pacman -R nginx
sudo pacman -Rns nginx    # remove + unnecessary dependencies + config

# Update all packages:
sudo pacman -Syu

# Search:
pacman -Ss nginx          # search remote
pacman -Qs nginx          # search installed locally

# Show package info:
pacman -Qi nginx
pacman -Si nginx

# Which package owns this file?
pacman -Qo /usr/bin/ls
```

### Groups

```bash
# Install a group (collection of related packages):
sudo pacman -S gnome
sudo pacman -S base-devel   # essential build tools

# List group members:
pacman -Sg gnome
```

### Package Cache

```bash
# /var/cache/pacman/pkg/ — downloaded packages
ls /var/cache/pacman/pkg/

# Clean cache (keep last 3 versions):
sudo pacman -Sc

# Clean everything:
sudo pacman -Scc
```

## dnf (Fedora/RHEL 8+)

```bash
sudo dnf install nginx
sudo dnf remove nginx
sudo dnf update
sudo dnf search nginx
dnf info nginx
dnf autoremove
dnf clean all
```

## What Packages Actually Contain

A package is a tar archive (`.deb`, `.pkg.tar.zst`, `.rpm`) containing:

```
package/
  DEBIAN/
    control        # package metadata (name, version, deps, size)
    preinst        # script run BEFORE installation
    postinst       # script run AFTER installation
    prerm          # script run BEFORE removal
    postrm         # script run AFTER removal
  usr/bin/         # executables
  usr/lib/         # libraries
  etc/             # config files
  usr/share/doc/   # documentation
```

## Repositories

Packages come from repositories — servers hosting package lists and package files.

### apt Sources (Debian/Ubuntu)

```bash
# Repository config:
cat /etc/apt/sources.list
# deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse

# /etc/apt/sources.list.d/ — additional repo files
ls /etc/apt/sources.list.d/
```

### pacman Repositories (Arch)

```bash
cat /etc/pacman.conf
# [core]
# SigLevel = PackageRequired
# Server = https://mirror.archlinux.org/$repo/$arch

# Official repos:
# [core]      — base system
# [extra]     — everything else
# [community] — AUR packages that became official

# Enable multilib (32-bit support):
# In /etc/pacman.conf:
[multilib]
Include = /etc/pacman.d/mirrorlist
```

### AUR (Arch User Repository)

Arch's community-driven package collection. Not in official repos — install with an AUR helper:

```bash
# Using yay:
yay -S google-chrome

# Or manually:
git clone https://aur.archlinux.org/google-chrome.git
cd google-chrome
makepkg -si
```

## Dependency Trees

```bash
# apt — show dependencies:
apt-cache depends nginx
# nginx
#   Depends: nginx-core
#   Depends: libc6
#   ...

# Reverse dependencies (what depends on this):
apt-cache rdepends nginx

# pacman — show dependencies:
pacman -Qi nginx | grep Depends

# dpkg — what installed this package:
dpkg -S /usr/sbin/nginx
```

## Quick Reference

```bash
# Debian/Ubuntu
sudo apt update
sudo apt install nginx
sudo apt remove nginx
sudo apt upgrade
apt search nginx
apt show nginx
sudo apt autoremove
sudo apt clean

# Arch/Manjaro
sudo pacman -Sy
sudo pacman -S nginx
sudo pacman -R nginx
sudo pacman -Syu
pacman -Ss nginx
pacman -Qi nginx
sudo pacman -Sc

# General
dpkg -l             # list installed packages
dpkg -S /path/to/file  # which package owns this file
apt-file update      # update apt-file cache
apt-file search file # find which package provides a file
```