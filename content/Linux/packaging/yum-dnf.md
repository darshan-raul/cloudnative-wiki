---
title: YUM and DNF Package Managers
tags: [linux, packaging, yum, dnf, rhel, fedora, rpm]
date: 2026-09-06
description: "YUM and DNF package management on RHEL, CentOS, Rocky Linux, and Fedora: repository configurations, rpm transactions, plugins, and module streams."
---

# YUM and DNF Package Managers 📦

DNF (Dandified YUM) is the next-generation package manager replacing YUM on RPM-based distributions (RHEL 8/9, Rocky Linux, AlmaLinux, Fedora, and Amazon Linux 2023). It resolves dependencies faster using `libsolv`, consumes less memory, and provides modular repository controls.

---

## 1. YUM vs DNF Comparison

| Feature                   | YUM (v3 - Legacy)                      | DNF (v4 / v5 - Modern)                                  |
| :------------------------ | :------------------------------------- | :------------------------------------------------------ |
| **Dependency Resolver**   | Python-based internal solver (slow)    | `libsolv` C library (SAT-solver algorithm)              |
| **Memory Footprint**      | High (loads entire metadata into RAM)  | Low (shared metadata caches)                            |
| **Python API**            | Poorly documented Python 2/3 internals | Clean, stable C/Python API                              |
| **Default Distributions** | RHEL 7, CentOS 7, Amazon Linux 2       | RHEL 8/9, Rocky, Fedora, Amazon Linux 2023              |
| **Command Compatibility** | `yum install pkg`                      | Fully backward compatible (`yum` is a symlink to `dnf`) |

---

## 2. Core DNF Command Workflows

```bash
# Update repository metadata and upgrade installed packages
sudo dnf check-update
sudo dnf upgrade -y

# Search for packages by keyword or file path
dnf search nginx
dnf provides /usr/sbin/semanage   # Find which package supplies a file

# Install and remove packages
sudo dnf install -y htop
sudo dnf remove -y httpd

# Clean cached metadata and packages
sudo dnf clean all
sudo dnf makecache

# Transaction History & Rollbacks
dnf history
sudo dnf history info 12
sudo dnf history undo 12          # Roll back specific installation transaction
```

---

## 3. Repository Configuration (`/etc/yum.repos.d/`)

DNF reads `.repo` files from `/etc/yum.repos.d/`:

```ini
[custom-repo]
name=Custom Enterprise Repository
baseurl=https://packages.example.com/rhel/$releasever/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://packages.example.com/RPM-GPG-KEY-custom
metadata_expire=6h
sslverify=1
```

### Managing Repositories via CLI

```bash
# List active repositories
dnf repolist

# Enable or disable repository on the fly
sudo dnf config-manager --set-enabled epel
sudo dnf config-manager --set-disabled crb

# Add a remote repo file
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
```

---

## 4. DNF Modules & Application Streams

RHEL 8+ uses AppStreams to allow installing multiple versions of the same software (e.g., Node.js 18 vs 20):

```bash
# List available module streams
dnf module list nodejs

# Enable and install specific stream
sudo dnf module enable -y nodejs:20
sudo dnf module install -y nodejs:20/default

# Switch stream
sudo dnf module reset -y nodejs
sudo dnf module enable -y nodejs:22
sudo dnf distro-sync
```

---

## Related Notes in Wiki

- [[Linux/packaging/README|Linux Packaging Hub]]
- [[Linux/packaging/dpkg|dpkg & Low-Level Packaging]]
- [[Linux/packaging/package-repos|Linux Package Repositories]]
- [[Linux/packaging/apt|APT (Advanced Package Tool)]]
