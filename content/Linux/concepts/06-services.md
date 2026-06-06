---
title: "06 — System Services"
description: Linux system services — what is a daemon, systemd basics, systemctl start/stop/enable, service files
tags:
  - linux
  - concepts
---

# 06 — System Services

A service (daemon) is a program that runs in the background, waiting to handle requests. Nginx serves web pages, SSH lets you log in remotely, cron runs scheduled jobs — all run as services.

## What is a Daemon?

A daemon is a process that:
1. Starts at boot (usually)
2. Runs in the background
3. Has no attached terminal (detached from /dev/tty)
4. Waits for something to happen (network request, timer, file change)

```
SSH server: sshd  → listens on port 22, spawns shell when you connect
Web server: nginx → listens on port 80/443, serves pages when you request
Database:   postgres → listens on port 5432, runs queries when apps connect
Print:      cupsd   → queues print jobs
DNS:        systemd-resolved → answers DNS queries
```

## systemd — The Service Manager

systemd is the init system on most modern Linux distros. It:
- Starts services at boot
- Keeps services running (restarts on failure)
- Provides logging (journald)
- Manages sockets, timers, mounts

### systemctl — The Main Command

```bash
# Start (run now) / Stop / Restart a service:
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl restart nginx

# Restart only if already running (reload config without full restart):
sudo systemctl reload nginx

# Enable (start at boot) / Disable:
sudo systemctl enable nginx
sudo systemctl disable nginx

# Check status (is it running? any errors?):
sudo systemctl status nginx
# ● nginx.service - A high performance web server
#      Loaded: loaded (/etc/systemd/system/nginx.service; enabled)
#      Active: active (running) since Sat 2025-06-06 10:00:00 UTC; 1 day 3h ago
```

### Enable vs Start

```
enable  = create symlinks so service starts at boot
start   = run it right now

You almost always want BOTH:  enable AND start
```

```bash
# Common pattern when installing nginx:
sudo systemctl enable --now nginx
# Equivalent to:
sudo systemctl enable nginx
sudo systemctl start nginx
```

### Checking Service State

```bash
systemctl status nginx
systemctl is-active nginx   # active or inactive
systemctl is-enabled nginx  # enabled or disabled

# List all services:
systemctl list-units --type=service
systemctl list-units --type=service --state=running

# Show failed services:
systemctl --failed
```

### Viewing Logs for a Service

```bash
# All logs for a service:
sudo journalctl -u nginx

# Follow logs (like tail -f):
sudo journalctl -u nginx -f

# Last 20 lines:
sudo journalctl -u nginx -n 20

# Since a time:
sudo journalctl -u nginx --since "1 hour ago"
sudo journalctl -u nginx --since "2025-06-06 10:00"
```

## Common Service Operations

```bash
# Stop a misbehaving service:
sudo systemctl stop nginx

# Force-restart a hung service:
sudo systemctl kill -s SIGKILL nginx
sudo systemctl restart nginx

# Mask (completely disable, can't be started manually either):
sudo systemctl mask nginx
# Unmask to restore:
sudo systemctl unmask nginx

# Reload systemd after creating a new service file:
sudo systemctl daemon-reload
# (then systemctl restart your-service)
```

## Service Files

A service file tells systemd how to run your service.

```bash
# Location:
/etc/systemd/system/    # user-created services
/run/systemd/system/    # runtime-generated
/lib/systemd/system/    # packages install here (symlinked to /etc/systemd/system)

# View an existing service file:
systemctl cat nginx
```

### Anatomy of a Service File

```ini
[Unit]
Description=My Web Application
# Start after network is ready:
After=network.target
# Required by:
Wants=network.target

[Service]
Type=simple           # simple = one process (most common)
# Type=oneshot        # runs once and exits (like a cron job)
# Type=forking        # parent exits after spawning child (legacy)
ExecStart=/usr/local/bin/myapp
WorkingDirectory=/opt/myapp
Restart=always        # restart on failure
RestartSec=5          # wait 5 seconds before restarting
User=myapp
Group=myapp
# Environment:
Environment=NODE_ENV=production PORT=3000

[Install]
WantedBy=multi-user.target
# graphical.target = boot to GUI
# multi-user.target = boot to CLI
```

### Useful Service File Options

```ini
[Service]
# Restart policies:
Restart=no              # never restart
Restart=on-success      # restart only on clean exit (exit code 0)
Restart=on-failure      # restart on non-zero exit
Restart=always          # always restart

# Environment:
Environment=PORT=3000
EnvironmentFile=/etc/myapp/env

# Resource limits:
MemoryMax=512M
CPUQuota=50%
LimitNOFILE=65536

# Security hardening:
NoNewPrivileges=true
ProtectSystem=strict
ReadOnlyPaths=/
ReadWritePaths=/var/log/myapp
PrivateTmp=true

# Logging:
StandardOutput=journal
StandardError=journal
```

## Timers (cron Alternative)

systemd timers trigger services on a schedule, like cron but with journal integration and dependencies.

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Run backup daily at 3am

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true    # catch up if system was off

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl enable --now backup.timer
systemctl list-timers
```

## Quick Reference

```bash
# Core commands
systemctl start nginx
systemctl stop nginx
systemctl restart nginx
systemctl reload nginx
systemctl status nginx
systemctl enable nginx
systemctl disable nginx
systemctl enable --now nginx     # enable + start
systemctl disable --now nginx   # disable + stop
systemctl mask nginx             # cannot be started
systemctl unmask nginx          # restore
systemctl daemon-reload        # reload unit files

# Check state
systemctl is-active nginx
systemctl is-enabled nginx
systemctl --failed

# Logs
journalctl -u nginx
journalctl -u nginx -f
journalctl -u nginx --since "1 hour ago"

# List services
systemctl list-units --type=service
systemctl list-units --type=service --state=running
```