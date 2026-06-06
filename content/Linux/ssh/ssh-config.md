---
title: SSH Config and Tricks
description: SSH config — ProxyJump, ProxyCommand, Match, ControlMaster, Host patterns, Agent forwarding, ServerAliveInterval, and advanced SSH patterns
tags:
  - linux
  - ssh
  - networking
---

# SSH Config and Tricks

`~/.ssh/config` (or `/etc/ssh/ssh_config`) is the most powerful SSH file most people barely use. It lets you define aliases, proxy jumps, identity files, and connection options per-host — once set up, everything is `ssh myserver` instead of remembering `-i ~/.ssh/key -p 2222 user@host`.

## Basic Config

```bash
# ~/.ssh/config
Host myserver
    HostName 192.168.1.100
    User darshan
    Port 22
    IdentityFile ~/.ssh/id_ed25519

Host web
    HostName web.example.com
    User ubuntu
    Port 2222
    IdentityFile ~/.ssh/prod_key
    StrictHostKeyChecking no    # don't prompt on first connect
    UserKnownHostsFile /dev/null
```

Then just `ssh web` instead of `ssh -p 2222 -i ~/.ssh/prod_key ubuntu@web.example.com`.

## ProxyJump (Jump Host)

Access a server that isn't directly reachable from your machine — go through a jump/bastion host:

```bash
# Manual:
ssh -J bastion.example.com internal-server.local

# Config:
Host internal-server
    HostName 192.168.1.50
    User ubuntu
    ProxyJump bastion.example.com

Host bastion
    HostName bastion.example.com
    User darshan
    Port 2222
```

Now `ssh internal-server` automatically proxies through bastion. Works with `-W` (netcat mode) or ProxyJump `-J`.

## ProxyCommand

For older servers without ProxyJump support, use netcat mode:

```bash
Host internal-server
    HostName 192.168.1.50
    User ubuntu
    ProxyCommand ssh -q bastion.example.com nc %h %p
    # nc = netcat, %h = target host, %p = target port
    # -q suppresses warnings
```

For ProxyJump-capable OpenSSH 7.3+, just use `ProxyJump`.

## ControlMaster (Multiplexing)

Reuse a single SSH connection for multiple sessions to the same host — no new authentication for subsequent connections:

```bash
Host *
    # Master connection lives here:
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlMaster auto
    ControlPersist 10m    # keep master alive 10min after last session closes

# Create sockets directory:
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh/sockets
```

Now your first `ssh web` opens the master connection. Second `ssh web` in another terminal reuses it — instant, no auth.

## Host Patterns

```bash
# Wildcards
Host *.internal
    User admin
    ProxyJump jump.internal

Host 10.0.0.*
    User ubuntu
    StrictHostKeyChecking no

Host dev-* prod-*
    User deploy
    IdentityFile ~/.ssh/deploy_key

# Negation
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host !bastion *     # apply to all except bastion
    ServerAliveInterval 30
```

## Authentication and Keys

```bash
# Add key to agent on first use:
AddKeysToAgent yes

# Specific key per host:
Host gitlab
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/gitlab_ed25519

Host github
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_ed25519
    IdentitiesOnly yes    # only use this key, not ssh-agent keys

# Key forwarding (ssh-agent):
Host target-server
    HostName 192.168.1.50
    ForwardAgent yes      # forward your ssh-agent to this server
    # Now your agent is available on target-server for git push, etc.
```

## Connection Options

```bash
Host remote-server
    HostName remote.example.com
    User darshan

    # Don't disconnect after inactivity:
    ServerAliveInterval 60       # send keepalive every 60s
    ServerAliveCountMax 3       # disconnect after 3 failed keepalives

    # Connection multiplexing keeps the connection alive:
    ControlMaster auto
    ControlPersist 10m

    # Reconnect automatically:
    ConnectionAttempts 3

    # TCP forwarding:
    LocalForward 8080 localhost:80     # forward local 8080 to remote's port 80
    RemoteForward 2222 localhost:22     # forward remote's 2222 to your local SSH

    # Use a different IP/hostname for the local part:
    HostName %h
    LocalForward 127.0.0.1:8080 127.0.0.1:80
```

## Match Blocks

`Match` blocks apply settings conditionally — by user, host, or address:

```bash
Host myserver
    HostName 192.168.1.100
    User darshan

# Apply to all hosts, but only when connecting as root:
Match User root
    IdentityFile ~/.ssh/root_key
    AllowAgentForwarding no   # don't allow agent forward as root

# Match by host:
Match Host "10.0.*"
    StrictHostKeyChecking accept-new

Match Host "192.168.*"
    User admin

# Match by address:
Match LocalAddress 192.168.1.*
    Gateway yes

# Match all:
Match all
    ForwardAgent no
```

## Port Forwarding

```bash
# Local forward: local port → remote target
Host app
    HostName app.example.com
    LocalForward 8080 localhost:8080      # access app's port 8080 via localhost:8080
    LocalForward 5432 localhost:5432      # local postgresql client

# Dynamic forward (SOCKS proxy):
Host vpn
    HostName jump.example.com
    DynamicForward 1080                    # SOCKS proxy on localhost:1080
    # Then: curl --socks5 localhost:1080 https://example.com

# Remote forward: remote port → local target
Host home
    HostName home.example.com
    RemoteForward 2222 localhost:22      # from home, ssh to :2222 → your local SSH
```

## Useful Global Options

```bash
# /etc/ssh/ssh_config or ~/.ssh/config

# Global defaults:
Host *
    # Security:
    StrictHostKeyChecking ask
    UserKnownHostsFile ~/.ssh/known_hosts

    # Performance:
    Compression yes          # compress data (slow links)
    TCPKeepAlive yes        # detect dead connections
    ServerAliveInterval 120

    # Security (modern cipher suites):
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
    KexAlgorithms curve25519-sha256,ecdh-sha2-nistp521
```

## Known Hosts Management

```bash
# Remove a known host (when server IP changes or rebuild):
ssh-keygen -R hostname
ssh-keygen -R 192.168.1.100
ssh-keygen -R "[server]:2222"

# Add without prompt:
ssh-keyscan -H hostname >> ~/.ssh/known_hosts
ssh-keyscan -H -p 2222 hostname >> ~/.ssh/known_hosts

# Show fingerprint:
ssh-keygen -lf ~/.ssh/known_hosts
ssh-keygen -lf ~/.ssh/id_ed25519.pub

# Hash a hostname (obfuscate known_hosts):
ssh-keygen -H -f ~/.ssh/known_hosts
```

## SSH Over Proxy

```bash
# Through HTTP proxy:
Host external
    HostName server.com
    ProxyCommand connect -H proxy.company.com:8080 %h %p

# Through SOCKS5:
Host external
    HostName server.com
    ProxyCommand connect -S proxy.company.com:1080 %h %p

# connect tool: apt install connect-proxy
```

## Quick Reference

```bash
# ~/.ssh/config key options:
Host              # hostname alias
HostName          # actual hostname/IP
User              # username
Port              # port
IdentityFile      # key file
ProxyJump         # jump host (-J)
ProxyCommand      # custom connection command
LocalForward      # local port forward
RemoteForward     # remote port forward
DynamicForward    # SOCKS proxy
ServerAliveInterval  # keepalive seconds
ServerAliveCountMax  # max missed keepalives
ControlMaster     # connection sharing
ControlPath       # socket path for multiplexing
ControlPersist    # master connection lifetime
ForwardAgent      # forward ssh-agent
StrictHostKeyChecking  # yes/ask/no
UserKnownHostsFile     # known_hosts path
AddKeysToAgent        # add key to agent on use
IdentitiesOnly        # only use specified identity
Match                # conditional settings
```