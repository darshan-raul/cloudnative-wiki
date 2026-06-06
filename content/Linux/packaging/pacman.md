---
title: pacman
description: Arch Linux / Manjaro pacman — package management, /etc/pacman.conf, AUR, trizen, paru
tags:
  - linux
  - packaging
---

# pacman

`pacman` is the package manager for Arch Linux and Manjaro. It's known for its simplicity, speed, and keeping the system minimal. Packages are `.pkg.tar.zst` (zstd-compressed tarballs). The AUR (Arch User Repository) provides thousands of community-maintained packages.

## Core Commands

```bash
# Sync package databases and install
pacman -S nginx                  # install nginx
pacman -Syu                      # sync, update everything (THE command)
pacman -Syu go minecraft-server  # update + install in one

# Remove
pacman -R nginx                  # remove package
pacman -Rns nginx               # remove + dependencies + config (-n = don't save backup)

# Search
pacman -Ss nginx                # search in repos
pacman -Qs nginx                # search installed
pacman -F nginx                 # which package provides 'nginx' binary

# Info
pacman -Qi nginx                # installed package info
pacman -Si nginx                # repo package info
pacman -Ql nginx                # list files in package
pacman -Qo /etc/nginx/nginx.conf # which package owns a file
```

## Package Groups

```bash
# Install all packages in a group
pacman -S base-devel            # essential build tools (gcc, make, etc.)

# Remove all packages in a group
pacman -Rsc base-devel

# See what group a package is in
pacman -Qg base-devel
```

## pacman.conf

```bash
cat /etc/pacman.conf
```

Key settings:
```
[options]
Architecture = auto           # x86_64, i686
Color                             # colored output
TotalDownload                    # show download progress
ILoveCandy                       # pacman is anime (optional)

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
```

### Enable multilib (32-bit packages on 64-bit)

```bash
# In /etc/pacman.conf, uncomment:
[multilib]
Include = /etc/pacman.d/mirrorlist

pacman -Syu
```

## Mirrorlist

```bash
# Mirror list location
cat /etc/pacman.d/mirrorlist

# Pick fastest mirror (reflector)
pacman -Syu reflector
reflector --country US --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

# Or manually: uncomment the best server near you (geographically close = faster)
```

## Database Locations

```bash
# Package info
ls /var/lib/pacman/sync/
# core.db   extra.db   multilib.db   (repo databases)

# Local package database
ls /var/lib/pacman/local/
# nginx-1.24.0-1/
#   desc       # package description
#   files       # installed files list
#   install     # pre-install / post-install scripts
#   depends     # dependencies
```

## /etc/pacman.d/hooks/

Hooks run scripts at specific package events (replacement for `dpkg-divert`):

```bash
# /etc/pacman.d/hooks/update-mkinitcpio.hook
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = linux

[Action]
Description = Updating mkinitcpio...
When = PostTransaction
Exec = /usr/bin/mkinitcpio -P
```

## AUR (Arch User Repository)

The AUR is a community repository. AUR packages are `PKGBUILD` scripts — shell scripts that download source, compile, and package:

```bash
# Manual AUR build:
git clone https://aur.archlinux.org/trizen.git
cd trizen
makepkg -si
#   -s: install dependencies
#   -i: install the resulting package

# trizen (AUR helper — similar to yay):
trizen -S minecraft-launcher

# paru (Rust-based, fastest AUR helper):
paru -S minecraft-launcher
```

### AUR Helpers Comparison

| Helper   | Language | Features                            |
|---------|----------|-------------------------------------|
| yay     | Go       | Default in EndeavourOS, interactive |
| paru    | Rust      | Fastest, --leaf, -Qm for foreign    |
| trizen  | Perl      | Minimal, pacman-like                 |

### AUR Safety

AUR packages are **unsigned** — they run arbitrary shell scripts as root. Only use trusted packages (read the PKGBUILD first):

```bash
# Always inspect before building:
git clone https://aur.archlinux.org/package.git
cd package
cat PKGBUILD
# Read the install/upgradepkg function — check for malicious curl|sudo patterns
makepkg -s
```

## pacman Commands Quick Reference

```bash
pacman -S package            # install
pacman -R package            # remove
pacman -Syu                 # full system update
pacman -Ss term             # search
pacman -Qs term             # search installed
pacman -Si package          # repo info
pacman -Qi package          # installed info
pacman -Ql package          # list files
pacman -Qo file             # who owns file
pacman -F binary            # which package has binary
pacman -Sc                  # clean cache (remove old .pkg.tar.zst)
pacman -Scc                 # clean ALL cached packages
pacman -Qdt                 # list orphaned dependencies
pacman -Rns $(pacman -Qdtq) # remove orphaned dependencies
pacman -D --asdeps package   # mark as dependency (not explicitly installed)
pacman -D --asexplicit package # mark as explicitly installed
```

## pacman.conf Advanced Options

```bash
# IgnorePackage — prevent accidental upgrades
IgnorePkg = linux
IgnorePkg = linux-headers

# SkipPackage — skip specific packages during -Syu
# (same effect but per-session)

# NoUpgrade / NoExtract — prevent specific files from being upgraded/extracted
NoUpgrade = etc/nginx/nginx.conf
NoExtract = usr/lib/systemd/system/*
```

## Manjaro-Specific

Manjaro ships pamac (GUI) and `pacman` works identically. Manjaro also has:

```bash
# Manjaro's package search (Pamac backed):
pamac search nginx

# Manjaro settings manager:
manjaro-settings-manager   # kernel, bootloader, display
```