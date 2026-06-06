---
title: systemd-tmpfiles.d
description: Linux systemd-tmpfiles.d — volatile runtime directories, /run, /tmp cleanup, tmp.conf
tags:
  - linux
  - boot-init
---

# systemd-tmpfiles.d

systemd-tmpfiles manages the creation, deletion, and cleanup of **volatile runtime directories** like `/tmp`, `/run`, `/var/run`, `/var/tmp`. It runs early in boot to set up the runtime filesystem hierarchy and periodically to clean up old files.

## Why It Exists

```
/tmp    — shared temp space (user can write anything)
          Needs to be cleared on reboot, cleaned periodically

/run    — runtime data (pid files, sockets, lock files)
          Must exist before services start

/var/run — symlinked to /run on modern systems
           Same purpose as /run
```

Before tmpfiles, `/tmp` was a mess of stale files. Services had to create their directories at startup (race condition prone). tmpfiles.d provides a declarative way.

## Configuration Files

```bash
# Config locations (processed in order):
/etc/tmpfiles.d/*.conf      # admin overrides (highest priority)
/run/tmpfiles.d/*.conf      # runtime-generated configs
/lib/tmpfiles.d/*.conf      # vendor defaults (lowest priority)
```

## Syntax

```
Type  Path                  Mode UID    GID    Age    Argument
d     /run/myapp            0755 root   root   -      -
f     /run/myapp/pid        0644 root   root   -      1234
D     /tmp/myapp-cache      0755 darshan darshan 1d   -
L     /run/app.sock         -    -      -      -      /dev/null
C     /run/config           -    -      -      -      /etc/default/config
```

### Types

| Type | Action |
|------|--------|
| `d` | Create directory if it doesn't exist |
| `D` | Create directory, delete on boot (clean start) |
| `f` | Create regular file |
| `F` | Create regular file, truncate if exists |
| `w` | Write the Argument string to the file |
| `L` | Create symlink |
| `c` | Create character device |
| `b` | Create block device |
| `p` | Create named pipe (FIFO) |
| `C` | Copy directory tree recursively |

### Fields

```
d  /run/example  0755  root  root  -
│  │              │     │     │    │
│  │              │     │     │    └─ Age: cleanup if not accessed for N days
│  │              │     │     └─ GID
│  │              │     └─ UID
│  │              └─ Mode (octal)
│  └─ Path
└─ Type
```

## Common Examples

### /tmp cleanup (default config)

```bash
cat /lib/tmpfiles.d/tmp.conf
# See the system defaults for /tmp
```

### Create runtime directory for your app

```bash
# /etc/tmpfiles.d/myapp.conf
# Create /run/myapp on boot, clean if unused for 30 days
d  /run/myapp  0755  myapp  myapp  30d
```

### Pre-create PID file

```bash
# /etc/tmpfiles.d/myapp.conf
# Create /run/myapp.pid with content "1234"
f  /run/myapp.pid  0644  root  root  -  1234
```

### Create symlink

```bash
# /etc/tmpfiles.d/socket.conf
# Link /run/app.sock → /dev/null (useful for nulling a socket)
L  /run/app.sock  -  -  -  -  /dev/null
```

## Managing tmpfiles

```bash
# Run manually (creates/cleans now)
systemd-tmpfiles --create
systemd-tmpfiles --clean
systemd-tmpfiles --remove    # DELETE everything matching configs!

# Full cycle (create dirs, then clean)
systemd-tmpfiles --create --clean

# Dry run
systemd-tmpfiles --create --dry-run
systemd-tmpfiles --clean --dry-run

# Remove a specific path
systemd-tmpfiles --remove /tmp/myapp-cache
```

## systemd-tmpfiles.timer (Automatic Cleanup)

tmpfiles cleanup is triggered by a systemd timer:

```bash
# The timer runs tmpfiles --clean periodically
systemctl list-timers tmpfiles-clean.timer
# NEXT                        LEFT     LAST                        PASSED   UNIT              ACTIVATES
# Sun 2025-06-08 00:00:00 UTC  12h left  Sat 2025-06-07 00:00:00 UTC  12h ago  tmpfiles-clean.timer tmpfiles-clean.service
```

The timer runs daily at `00:00:00`. The service runs:
```
systemd-tmpfiles --clean
```

Files not accessed in the `Age` period are deleted.

## /tmp vs /var/tmp

```
/tmp — cleared on every reboot (-volatile)
/var/tmp — persists across reboots (semi-persistent)
```

Default tmpfiles for both:
```bash
# From /lib/tmpfiles.d/tmp.conf (Ubuntu default):
q  /tmp  1777  root  root  -
q  /var/tmp  1777  root  root  -

# q = create with sticky bit (only owner can delete)
/var/tmp is NOT cleared on reboot by default, only by tmpfiles-clean timer
```

## Custom /tmp on tmpfs

Many distros mount /tmp as tmpfs (in-memory, faster, cleared on reboot):

```bash
# /etc/fstab entry:
tmpfs  /tmp  tmpfs  defaults,noatime,mode=1777  0 0

# systemd equivalent (in /etc/tmpfiles.d/):
# On some systems tmpfiles.d handles tmpfs mounting:
w  /proc/self/mountinfo  -  -  -  -  ...
```

Note: tmpfs is controlled by `/etc/fstab` or `/proc/self/mountinfo`, not by tmpfiles.d.

## Use Cases

### 1. Your service needs /run/myapp before it starts

```bash
# /etc/tmpfiles.d/myapp.conf
d  /run/myapp  0755  myapp  myapp  -
```

```ini
# myapp.service
[Service]
RuntimeDirectory=myapp      # systemd creates /run/myapp automatically
# Equivalent to the tmpfiles.d above
```

systemd's `RuntimeDirectory=` directive replaces tmpfiles.d for simple directory creation in services.

### 2. Clean up old files in /tmp after 7 days

```bash
# /etc/tmpfiles.d/cleanup.conf
r  /tmp/old-app-cache  -  -  -  7d  -
# r = remove file if older than Age
```

## Permissions Note

tmpfiles runs as **root** early in boot (before services). So it can create files with any ownership. Regular users can't use tmpfiles.d to create files as root — only root can write to `/etc/tmpfiles.d/`.

## Verification

```bash
# List all tmpfiles.d configs
find /etc/tmpfiles.d /run/tmpfiles.d /lib/tmpfiles.d -name "*.conf"
systemd-tmpfiles --cat-config
```