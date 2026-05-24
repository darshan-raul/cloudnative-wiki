---
title: Arch Linux
---

# Arch Linux

A comprehensive guide to Arch Linux and Manjaro — rolling release distributions built on the KISS principle.

## Sections

### 1. [[Linux/arch/philosophy|Philosophy & Foundation]]
Rolling release model, KISS principle, Arch Wiki, derivatives comparison, `pacman` deep-dive, repositories.

### 2. [[Linux/arch/installation|Installation & Setup]]
archinstall wizard, manual partitioning, LUKS encryption, boot loaders, Manjaro editions.

### 3. [[Linux/arch/aur|AUR & Software Management]]
AUR workflow, helpers (yay/paru), PKGBUILD, ABS, third-party repos.

### 4. [[Linux/arch/system-administration|System Administration]]
systemd deep-dive, boot process, kernel management, system maintenance.

### 5. [[Linux/arch/networking|Networking]]
NetworkManager, firewall (nftables/iptables), DNS caching, VPN, Samba/NFS.

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `pacman -Syu` | Full system upgrade |
| `pacman -Ss <pkg>` | Search repositories |
| `pacman -S <pkg>` | Install package |
| `pacman -Rns <pkg>` | Remove package + deps |
| `pacman -Qdt` | List orphans |
| `yay -S <pkg>` | Install from AUR |