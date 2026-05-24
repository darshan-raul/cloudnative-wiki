---
title: AUR & Software Management
---

# 3. AUR & Software Management

## AUR (Arch User Repository) Overview

The **AUR** is a community-driven repository of ~80,000+ package build scripts (PKGBUILDs) for software not in the official repos. It powers Arch's massive software availability.

**How it works:**
- AUR packages are `PKGBUILD` scripts — instructions to compile software from source
- Anyone can submit a PKGBUILD; popular ones get "trusted" status and move to the `community` repo
- AUR is NOT a binary repo — packages are built on your machine (via `makepkg`)

**Key terms:**
- **AUR** — Arch User Repository (untrusted, user-submitted)
- **community** — Trusted AUR packages (maintained by TU, treated like official)
- **ABS** — Arch Build System (infrastructure to rebuild official packages with modifications)

## AUR Helpers

AUR helpers automate: finding packages, cloning repos, resolving dependencies, building, and installing. Manual PKGBUILD workflow is also available.

### yay (Yet Another Yogurt) — Most Popular

```bash
# Install yay
pacman -S yay

# Search
yay -Ss <pkg>

# Install from AUR
yay -S <pkg>

# Upgrade everything (including AUR)
yay -Syu

# Remove package
yay -Rns <pkg>

# Show package info
yay -Si <pkg>
```

### paru — Modern Alternative

```bash
# Install paru
pacman -S paru

# Same commands as yay (CLI is similar)
paru -S <pkg>
paru -Syu

# paru-specific: news before upgrade
paru -Syu --devel
```

### pamac — GUI (Manjaro's Default)

- Integrated into Manjaro's Gnome/KDE edition
- Tabs for: Installed, Available, AUR, Updates
- Built-in package search
- Settings → AUR to enable AUR support

## PKGBUILD and makepkg (Manual Workflow)

If you prefer not to use a helper, or want to inspect a package before building:

```bash
# Clone AUR repo
git clone https://aur.archlinux.org/<pkgname>.git
cd <pkgname>

# View PKGBUILD (ALWAYS review before building!)
cat PKGBUILD

# Build package (creates .pkg.tar.zst)
makepkg -si

# Components of a PKGBUILD:
# pkgbase / pkgname / pkgver / pkgrel
# arch=()
# depends=()
# makedepends=()
# source=()
# build() { }
# package() { }
```

### Key PKGBUILD Variables

```
pkgname = package-name
pkgver = 1.2.3
pkgrel = 1
arch = ('x86_64')
url = "https://example.com"
license = ('GPL3')
depends = ('glibc>=2.25' 'gtk3')
makedepends = ('cmake' 'ninja')
source = ("https://example.com/${pkgname}-${pkgver}.tar.gz")
md5sums = ('SKIP')

build() {
  cd "$pkgname-$pkgver"
  ./configure --prefix=/usr
  make
}

package() {
  make DESTDIR="$pkgdir" install
}
```

## ABS (Arch Build System)

ABS lets you rebuild official packages with custom modifications (e.g., adding a patch, changing compile flags).

```bash
# Install abs
pacman -S abs

# Sync ABS tree
sudo abs

# Example: rebuild nginx with custom config
mkdir ~/abs
cp /var/abs/core/nginx PKGBUILD ~/abs/nginx-custom/
cd ~/abs/nginx-custom
# Edit PKGBUILD as needed
makepkg -si
```

## Third-Party Repositories

### chaotic-aur

A fast mirror of popular AUR packages as pre-built binaries. Used by Garuda, can be added to Manjaro.

```bash
# /etc/pacman.conf
[chaotic-aur]
Server = https://aur.chaotic.cx/x86_64

# Update
pacman -Syu
```

### archlinuxcn (Chinese Community Repo)

Popular in China; contains many Chinese apps and tools as binaries.

```bash
# Add to /etc/pacman.conf
[archlinuxcn]
Server = https://repo.archlinuxcn.org/$arch

# Install
pacman -S archlinuxcn-keyring
pacman -S <pkg>
```

## Flatpak and Snap

Some software is also available as Flatpak or Snap (not exclusive to Arch):

### Flatpak
```bash
pacman -S flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub <app>
```

### Snap
```bash
pacman -S snapd
systemctl enable --now snapd.socket
snap install <app>
```

## Managing Package Conflicts and Issues

```bash
# Check what owns a file
pacman -Qo /path/to/file

# List files in a package
pacman -Ql <pkg>

# Get package by file (if not installed)
pkgfile <file>           # Install: pacman -S pkgfile

# View package dependencies
pacman -Qi <pkg>         # Installed
pacman -Si <pkg>         # In repos

# Dependency tree
pactree <pkg>

# Check for package updates in AUR
yay -Sua                 # AUR only upgrade
```

## Cleaning Up

```bash
# Remove cached packages (keep last 1 version)
paccache -r

# Or manually
rm -rf /var/cache/pacman/pkg/*

# Remove all cached packages
pacman -Sc

# List size of largest packages
pacman -Qi | awk '/^Name/{name=$3} /^Installed Size/{print $4$5}' | sort -rh | head -20

# Remove orphans
pacman -Rns $(pacman -Qdtq)
```

## Useful Tools

```bash
# pkgstats — send anonymous package stats to Arch (helps prioritize)
pacman -S pkgstats

# aurvote — vote for AUR packages to become official
# (discontinued but still works)

# namcap — lint-check PKGBUILDs for common mistakes
pacman -S namcap
namcap PKGBUILD
namcap <package-file>.pkg.tar.zst
```

## Security Notes on AUR

- AUR packages are UNTRUSTED by default — always review PKGBUILD before building
- Never run `makepkg` as root if you can avoid it (use `makepkg --asroot` if needed)
- AUR helpers that auto-install without review are a risk — use `yay -S --edit` to review before installing
- Trusted packages in `[community]` have been vetted by Trusted Users (TUs)