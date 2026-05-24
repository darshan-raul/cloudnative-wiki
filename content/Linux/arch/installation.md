---
title: Arch Linux Installation & Setup
---

# 2. Installation & Setup

## archinstall CLI Wizard

Arch's official installer is the `archinstall` script — a curses-based CLI wizard.

```bash
# From Arch live ISO
archinstall
```

It handles:
- Disk partitioning (with LUKS encryption option)
- Bootloader selection (systemd-boot or GRUB)
- Profile selection (minimal, desktop, server, etc.)
- Kernel selection (linux, linux-lts, linux-zen)
- User creation

**Profiles available:**
- `desktop` (with Gnome/KDE/Xfce)
- `server`
- `minimal`
- `hardened`

Manual partitioning is recommended even with archinstall — use the guided option but review before confirming.

## Manual Partitioning

### UEFI + GPT (Modern Standard)

```bash
lsblk                                   # Identify disk (e.g., /dev/sda)
cgdisk /dev/sda                         # Partition editor (curses)

# Partitions:
# /dev/sda1  512M   EFI System       # Boot/ESP (flag: boot, esp)
# /dev/sda2  Rest   Linux filesystem  # Root partition (flag: linux)
```

```bash
# Format EFI partition
mkfs.fat -F32 /dev/sda1

# Format root partition
mkfs.ext4 /dev/sda2

# Mount
mount /dev/sda2 /mnt
mkdir /mnt/boot /mnt/boot/efi -p
mount /dev/sda1 /mnt/boot/efi
```

### BIOS + MBR (Legacy)

```bash
cgdisk /dev/sda
# /dev/sda1  100%   Linux filesystem  (type: 83)
mkfs.ext4 /dev/sda1
mount /dev/sda1 /mnt
```

### With LUKS Encryption

```bash
# Create encrypted container
cryptsetup luksFormat /dev/sda2

# Open container
cryptsetup open /dev/sda2 cryptroot

# Format inside container
mkfs.ext4 /dev/mapper/cryptroot

# Mount
mount /dev/mapper/cryptroot /mnt

# Add to /etc/crypttab for unlock at boot
```

## Boot Loaders

### systemd-boot (UEFI only, simpler)

```bash
bootctl install

# Create loader entry /boot/loader/entries/arch.conf
cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=<uuid> rw
EOF
```

### GRUB (UEFI + BIOS)

```bash
pacman -S grub

# UEFI
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# BIOS
grub-install --target=i386-pc /dev/sda

# Generate config
grub-mkconfig -o /boot/grub/grub.cfg
```

## Post-Installation Base Setup

```bash
# Install base packages
pacstrap /mnt base linux linux-firmware nano sudo networkmanager

# Generate fstab
genfstab -U /mnt >> /etc/fstab

# Chroot into new system
arch-chroot /mnt

# Set timezone
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

# Localization
nano /etc/locale.gen   # Uncomment en_US.UTF-8
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "archhost" > /etc/hostname

# Enable NetworkManager
systemctl enable NetworkManager

# Set root password
passwd
```

## Manjaro Editions

| Edition | Desktop | Target |
|---------|---------|--------|
| **Manjaro Gnome** | GNOME 45+ | Modern, feature-rich |
| **Manjaro KDE** | Plasma 5.x/6 | Customizable, familiar |
| **Manjaro Xfce** | Xfce 4.18 | Lightweight, older hardware |
| **Manjaro Cinnamon** | Cinnamon 6 | Traditional desktop feel |
| **Manjaro Architect** | CLI/TUI | Build your own environment |

### Manjaro-Specific Tools

```bash
# Manjaro Hardware Detection (install drivers)
mhwd

# Install LTS kernel
mhwd-kernel -i linux61

# List available kernels
mhwd-kernel -l

# Remove kernel
sudo mhwd-kernel -r linux61

# Manjaro Settings Manager (GUI)
manjaro-settings-manager
```

## Disk Encryption with LUKS + LVM

Full-disk encryption setup:

```bash
# Partition
cgdisk /dev/sda
# /dev/sda1  512M EFI   (ef00 type)
# /dev/sda2  Rest Linux (8e00 type)

# Encrypt root partition
cryptsetup luksFormat --type luks2 /dev/sda2
cryptsetup open /dev/sda2 cryptroot

# Create LVM
pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
lvcreate -L 40G vg0 -n root
lvcreate -L 16G vg0 -n swap
lvcreate -l 100%FREE vg0 -n home

# Format
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/vg0/root
mkswap /dev/vg0/swap
mkfs.ext4 /dev/vg0/home

# Mount
mount /dev/vg0/root /mnt
mkdir /mnt/home
mount /dev/vg0/home /mnt/home
swapon /dev/vg0/swap
```

**mkinitcpio config** (`/etc/mkinitcpio.conf`):
```
HOOKS=(base udev autodetect keyboard keymap encrypt lvm2 resume filesystems)
```

Then run `mkinitcpio -P` after arch-chroot.

## DE/WM Installation After Base

### GNOME
```bash
pacman -S gnome gnome-extra gdm
systemctl enable gdm
```

### KDE Plasma
```bash
pacman -S plasma sddm
systemctl enable sddm
```

### Xfce
```bash
pacman -S xfce4 xfce4-goodies lightdm
systemctl enable lightdm
```

### i3 (tiling WM)
```bash
pacman -S i3 dmenu i3status i3lock terminator
```

## Common Post-Install Steps

```bash
# Add user
useradd -m -G wheel,audio,video,storage -s /bin/bash darshan
passwd darshan

# Enable sudo
EDITOR=nano visudo
# Uncomment: %wheel ALL=(ALL) ALL

# Install common tools
pacman -S git curl wget base-devel \
  neovim bash-completion \
  man-db man-pages texinfo
```