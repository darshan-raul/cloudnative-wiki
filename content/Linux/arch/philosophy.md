---
title: Arch Linux Philosophy & Foundation
---

# 1. Philosophy & Foundation

## Rolling Release Model

Unlike versioned distributions (Ubuntu, Fedora) that ship discrete releases, Arch is a **rolling release** — the system is always up-to-date. There's no concept of "Ubuntu 22.04" or "Fedora 39". You install once and continuously receive updates via `pacman -Syu`.

**Advantages:**
- Always running latest software (kernel, gcc, python, etc.)
- No planned dist-upgrades — no "do-release-upgrade" moments
- Lower isolation between system and application layers

**Disadvantages:**
- Updates can introduce breakage (mitigated by reading news archlinux.org/news)
- Requires regular maintenance; can't "set and forget"
- Not suitable for systems requiring ABI stability (some production servers)

## KISS Principle

Arch Linux adheres to the **KISS principle** (Keep It Simple, Stupid):
- Ship minimal base system; users add what they need
- Configuration files are hand-edited (no GUIs for core system)
- No opinionated defaults — you build your system from the ground up
- The Arch Way: users are expected to understand how their system works

## The Arch Wiki

The **[Arch Wiki](https://wiki.archlinux.org)** is considered the best Linux documentation on the internet. It covers:
- Installation guides for every DE/WM
- Hardware setup (NVIDIA, audio, printing, etc.)
- Security hardening
- Server configuration
- Troubleshooting

**It's your first stop for any Arch/Manjaro problem.** Even if you're on Manjaro, the Arch Wiki applies ~90% because Manjaro is built on Arch.

## Derivatives Comparison

| Distribution | Base | Target User | Key Feature |
|-------------|------|-------------|--------------|
| **Arch Linux** | — | Intermediate/advanced | Pure rolling, DIY |
| **Manjaro** | Arch | Beginner-friendly | User-friendly installer, LTS kernels, out-of-the-box hardware detection |
| **EndeavourOS** | Arch | Intermediate | Cassini online installer, Arch without the CLI friction |
| **Garuda Linux** | Arch | Power users | Gaming/creative pre-configured, Chaotic-AUR default |
| **ArcoLinux** | Arch | Learners | Learning-oriented, provides ISO variants for different WM experiences |

### Manjaro Specifics
- **OBS** (Open Build Service): Manjaro builds its own packages, holds updates for ~2 weeks to test
- **Pamac** GUI package manager as default (also supports AUR)
- **MHI** (Manjaro Hardware Detection) for driver installation
- LTS kernel options via `mhwd-kernel`

## pacman Deep-Dive

`pacman` is Arch's package manager. All Arch-based distros use it.

### Core Commands

```bash
# Sync, upgrade system
pacman -Syu                  # Full upgrade (sync + update)

# Install packages
pacman -S <pkg>              # Install from repos
pacman -Sy <pkg>             # Sync then install (less safe)
pacman -S --asdeps <pkg>     # Install as dependency

# Remove packages
pacman -R <pkg>              # Remove only
pacman -Rns <pkg>            # Remove + unneeded deps + config
pacman -Rdd <pkg>            # Force remove (skip dependency check)

# Query
pacman -Qs <text>            # Search installed packages
pacman -Qi <pkg>             # Show info about installed package
pacman -Ql <pkg>             # List files owned by package
pacman -Qe                   # List explicitly installed packages
pacman -Qdt                  # List orphans (no longer required)
```

### Repositories

| Repository | Content | Enabled by |
|-----------|---------|------------|
| **core** | Bootloader, kernel, core tools (pacman, glibc) | Default |
| **extra** | GUI apps, server software | Default |
| **community** | Packages from AUR that graduated | Default |
| **multilib** | 32-bit libs for Wine/Steam | `[multilib]` enabled |
| **testing** | Untested updates | Disabled by default |
| **community-testing** | Community packages being tested | Disabled by default |

```bash
# /etc/pacman.conf
[multilib]
Include = /etc/pacman.d/mirrorlist

[testing]
Include = /etc/pacman.d/mirrorlist
```

### pacman Hooks (Automatic Actions on Install/Upgrade)

Hooks run automatically during `pacman -S` transactions. Located in `/usr/share/libalpm/hooks/` (system) or `/etc/pacman.d/hooks/` (user).

```bash
# /etc/pacman.d/hooks/update-grub.hook
[Trigger]
Type = Package
Operation = Install
Target = grub

[Action]
Description = Regenerating GRUB config...
When = PostTransaction
Exec = /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg
```

### Troubleshooting pacman

```bash
# Fix corrupted database
rm -rf /var/lib/pacman/sync/*
pacman -Sy

# Force sync a specific db
pacman -Sf <pkg>

# Ignore package from upgrade (e.g., broken driver)
# In /etc/pacman.conf:
IgnorePkg = nvidia

# View package changelog
pacman -Ch <pkg>
```

## Pacnew & Pacsave Files

When pacman upgrades a config file (e.g., `/etc/pacman.conf`), it doesn't overwrite the old one — it creates `.pacnew` or `.pacsave`:

- **`.pacnew`** — new config file created; old config remains
- **`.pacsave`** — old config backed up before removal
- **`.pacorig`** — rare, original config before pacman modifications

```bash
# Find all .pacnew/.pacsave files
find /etc -name "*.pac*" 2>/dev/null

# Use pacdiff to merge
pacdiff
# Or manually
mv /etc/foo.conf.pacnew /etc/foo.conf
```

## Mirror Management

```bash
# Rank mirrors by speed (install rankmirrors package)
rankmirrors -n 6 /etc/pacman.d/mirrorlist

# Enable specific country's mirrors
# In /etc/pacman.conf:
Server = https://mirror.example.com/$repo/os/$arch
```

### Manjaro's Mirrors
Manjaro uses its own mirrors plus Arch's. Managed via:
```bash
# GUI
pamac preferences -> Mirrors

# CLI
sudo pacman-mirrors -c Germany,France --no-git
```

## System News

Always read [archlinux.org/news](https://archlinux.org/news) before a big upgrade. Key announcements:
- Kernel ABI changes requiring initramfs rebuild
- Package removals from repos
- Security vulnerabilities requiring immediate action

```bash
# pacman can show news (if pacman-news-git installed)
pacnews
```