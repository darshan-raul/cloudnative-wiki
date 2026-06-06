---
title: systemd
description: Linux systemd — units, targets, systemctl, service files, socket activation, timers, journal integration
tags:
  - linux
  - init
---

# systemd

systemd is the init system and service manager for most Linux distributions. It replaces the older sysvinit shell script approach with a declarative unit-file-based model. PID 1 is systemd, and it manages the entire boot process, services, sockets, timers, mounts, and more.

## Unit Files

Units are declarative configuration files that describe a resource or service:

```bash
# Unit file locations:
/etc/systemd/system/    # system administrator units (highest priority)
/run/systemd/system/    # runtime units
/lib/systemd/system/     # vendor units (installed by packages)
```

### Unit Types

| Type    | File suffix    | Purpose                                    |
|---------|---------------|-------------------------------------------|
| Service | `.service`    | Daemon/process management                  |
| Socket | `.socket`     | Listen on socket, start service on connect |
| Target | `.target`     | Group of units (like a runlevel)          |
| Timer   | `.timer`      | cron-like scheduling                      |
| Mount   | `.mount`      | Filesystem mount                          |
| Path    | `.path`       | Trigger service when path changes         |
| Slice   | `.slice`      | Resource management (cgroups)             |

## Service Units

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application
After=network.target          # start after network is up
Wants=network.target          # want it but don't require
PartOf=myapp.slice           # if this unit stops, stop this too

[Service]
Type=simple                   # main process is PID 1 in cgroup
# Type=forking: parent exits after fork (traditional daemon)
# Type=oneshot: exits before next unit runs (single-run tasks)
ExecStart=/usr/bin/myapp --config /etc/myapp.conf
ExecStartPost=/usr/bin/sleep 1
ExecStop=/usr/bin/pkill -TERM myapp
ExecReload=/usr/bin/kill -HUP $MAINPID
Restart=on-failure            # restart on non-zero exit
RestartSec=5                  # wait 5s before restart
StandardOutput=journal        # log to journal
StandardError=journal

# Resource limits
LimitNOFILE=65536
MemoryMax=512M

# cgroup placement
Slice=myapp.slice

[Install]
WantedBy=multi-user.target   # enable at this target
```

## Common Commands

```bash
systemctl start nginx
systemctl stop nginx
systemctl restart nginx
systemctl reload nginx         # sends SIG HUP to nginx
systemctl status nginx
systemctl is-active nginx
systemctl is-enabled nginx

# Enable at boot (creates symlink in default target)
systemctl enable nginx
systemctl disable nginx

# Daemon-reload (after editing unit files)
systemctl daemon-reload

# List all units
systemctl list-units --type=service --state=running
systemctl list-units --type=service --state=failed

# Show dependencies
systemctl list-dependencies nginx
systemctl list-dependencies --reverse nginx    # what requires nginx
```

## Targets

Targets group units and provide synchronization points:

```bash
# Key targets
systemctl get-default          # show current default target
systemctl set-default multi-user.target

# Switch target at runtime
systemctl isolate multi-user.target
systemctl isolate graphical.target

# Boot into target
# Add to kernel params: systemd.unit=multi-user.target
```

### Key Targets

| Target          | Description                           |
|----------------|---------------------------------------|
| `emergency.target` | Emergency shell, minimal boot      |
| `rescue.target`   | Single-user, basic services         |
| `multi-user.target` | Multi-user, no GUI                 |
| `graphical.target` | Multi-user with GUI                |
| `default.target`   | What boots by default              |
| `halt.target`     | Halt the system                     |
| `reboot.target`   | Reboot                              |

## Socket Activation

Instead of a service running all the time, systemd can start it on first connection:

```ini
# /etc/systemd/system/myapp.socket
[Unit]
Description=My App Socket

[Socket]
ListenStream=/run/myapp.sock
Accept=no              # no, one instance handles all connections
# Accept=yes → fork a new process per connection (like inetd)
```

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My App
Requires=myapp.socket     # don't start without socket
After=myapp.socket

[Service]
ExecStart=/usr/bin/myapp
```

```bash
# Enable socket activation
systemctl enable myapp.socket
systemctl start myapp.socket
# No myapp.service running yet — it starts on first connection
```

## Timers (cron Replacement)

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Run backup every night at 2am

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true        # run missed jobs after boot
RandomizedDelaySec=30  # jitter to avoid thundering herd
```

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Backup Service

[Service]
ExecStart=/usr/local/bin/backup.sh
```

```bash
systemctl enable backup.timer
systemctl list-timers
systemctl list-timers --all
```

Timers can also use `OnBootSec=` and `OnUnitActiveSec=` for relative timing.

## journald

systemd's logging component. All services log to journald (binary, structured):

```bash
# View logs
journalctl -u nginx              # specific unit
journalctl -u nginx --since "1 hour ago"
journalctl -u nginx -f           # follow
journalctl -b                   # current boot
journalctl -b -1                 # previous boot
journalctl --since "2024-01-01"
journalctl -p err                # priority: emerg/alert/crit/err/warning/notice/info/debug

# Tail the journal
journalctl -f

# Disk usage
journalctl --disk-usage
journalctl --vacuum-size=500M   # keep last 500MB
journalctl --vacuum-time=7d      # keep last 7 days

# Ensure persistence (default on most distros)
# /etc/systemd/journald.conf: Storage=persistent|volatile|auto
```

## Managing Resources with Slices

Slices are cgroup hierarchies for resource isolation:

```bash
# Slices on a running system
systemd-cgls

# Create a slice with limits
# /etc/systemd/system/limited.slice
[Unit]
Description=Limited resources slice

[Slice]
MemoryMax=512M
CPUQuota=50%
TasksMax=50
```

## Troubleshooting

```bash
# Why did a unit fail?
systemctl status nginx
journalctl -u nginx -n 50
journalctl -xe                 # tail of journal, with context

# What is the boot timeline?
systemd-analyze
systemd-analyze blame         # slowest services
systemd-analyze critical-chain nginx

# Reset a failed unit
systemctl reset-failed

# Force kill a service
systemctl kill nginx

# Mask (completely disable, can't start)
systemctl mask nginx
systemctl unmask nginx
```

## systemd-run: Transient Units

Create and run a temporary unit without a file:

```bash
# Run a command with its own cgroup and limits
systemd-run --scope -p MemoryMax=100M /bin/bash -c 'stress --vm 1'

# Run as a service (starts now, not at boot)
systemd-run --on-startup="date" --on-unit-active-sec=3600 /usr/bin/backup.sh

# Run a service now
systemd-run --unit=myname --scope -p MemoryMax=1G python3 myapp.py
```

## Environment Variables in Units

```ini
[Service]
Environment="HOME=/var/lib/myapp"
Environment="PORT=8080"
EnvironmentFile=/etc/myapp/env    # load from file
```