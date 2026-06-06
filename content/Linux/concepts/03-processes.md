---
title: "03 — Processes"
description: Linux processes — what they are, PID, parent/child, zombie, daemon, process states, ps basics
tags:
  - linux
  - concepts
---

# 03 — Processes

A process is a running program. Every time you run a command, start a service, or open a terminal, you're creating a process. Linux can run thousands of them simultaneously — the kernel decides which gets CPU time via the scheduler.

## What is a Process?

A process is a container that holds:
- **PID** — a unique Process ID number
- **Memory** — its own address space (code, stack, heap, data)
- **Environment** — environment variables, working directory
- **Open files** — file descriptors for open files, sockets, pipes
- **Threads** — one or more threads of execution
- **Parent** — the process that started it

## Inspecting Processes

### ps — Static Snapshot

```bash
# Most common:
ps aux              # all processes, full format (BSD style)
ps -ef              # all processes, standard format (SysV style)
ps -ef --forest     # show parent/child tree

# Filter:
ps aux | grep nginx          # find nginx processes
ps -ef | grep 1234          # find process by PID
ps -u darshan              # processes for user 'darshan'

# Custom format:
ps -eo pid,user,%cpu,%mem,comm,state,etime
# pid   = process ID
# user  = owner
# %cpu  = CPU usage
# %mem  = memory usage
# comm  = command name (without path)
# state = process state (R/S/Z/T/D)
# etime = elapsed time since process started
```

### top — Live View

```bash
top                  # live process monitor
top -u darshan      # only your processes
top -p 1234         # monitor specific PID
```

In top:
- `M` — sort by memory
- `P` — sort by CPU (default)
- `T` — sort by time
- `k` — kill a process
- `r` — renice a process
- `1` — toggle per-CPU view
- `h` — help

### htop — Better top

```bash
htop                 # prettier, interactive top
htop -u darshan     # filter by user
htop -p 1234,5678   # monitor specific PIDs
```

## Process States

Every process is in one of these states:

```
R — Running or Runnable      # on CPU or waiting to be scheduled
S — Sleeping (interruptible) # waiting for an event (most common)
D — Sleeping (uninterruptible) # waiting for I/O, cannot be killed
Z — Zombie                   # dead process, waiting for parent to reap
T — Stopped                  # suspended (Ctrl+Z)
I — Idle                     # idle kernel thread
```

```bash
# See states in ps output:
ps -eo pid,stat,cmd | head -20
# STAT column:
# R  = running
# S+ = sleeping (foreground process, terminal attached)
# S  = sleeping (background)
# Sl = sleeping with multi-threaded
# D  = uninterruptible sleep (usually I/O)
# Z  = zombie
# T  = traced/stopped
```

## Parent and Child Processes

Every process (except PID 1) has a parent. When you run a command in a terminal, the shell is the parent.

```bash
# See parent-child relationships:
ps -ef --forest | head -30
# PID  PPID CMD
# 1     0   /sbin/init
# 1234  1   /usr/sbin/sshd
# 5678  1234  \_ sshd: darshan [priv]
# 5690  5678      \_ sshd: darshan@pts/0
# 5691  5690          \_ -bash
# 6000  5691              \_ ps -ef --forest
```

### Killing by PID

```bash
kill 1234              # send SIGTERM (15) — polite "please stop"
kill -TERM 1234        # same
kill -SIGKILL 1234     # force kill (9) — cannot be caught or blocked
kill -9 1234           # same as SIGKILL
kill -STOP 1234        # pause/suspend (like Ctrl+Z)
kill -CONT 1234        # resume a stopped process

# Send a different signal:
kill -HUP 1234         # SIGHUP — reload config (common for services)
kill -USR1 1234        # SIGUSR1 — user-defined, often used for log rotation

# Check what signals a process accepts:
kill -l                # list all signal names and numbers
```

## Daemons

A daemon is a process that runs in the background, detached from any terminal. They're how servers work — SSH, nginx, PostgreSQL all run as daemons.

Rules for daemons:
1. **No controlling terminal** — stdin/stdout/stderr point to /dev/null
2. **Parent is PID 1** — started by init/systemd, not a shell
3. **Run in the background** — detached from the terminal session
4. **Survive the terminal closing** — if terminal dies, daemon keeps running

```bash
# How to daemonize a process manually:
(./long-running-script.sh &)          # run in subshell background
nohup ./script.sh &                   # survives SIGHUP when terminal closes
./script.sh & disown                  # run and detach from shell

# Systemd handles this automatically:
# /etc/systemd/system/mydaemon.service
[Unit]
Description=My Background Service

[Service]
Type=simple
ExecStart=/usr/local/bin/mydaemon
Restart=always

[Install]
WantedBy=multi-user.target
```

## Zombie Processes

A zombie is a process that has finished running but can't be fully cleaned up — its parent hasn't read its exit code yet. A zombie has a PID and an entry in the process table, but no code is running.

**Normal cleanup:** when a child exits, the parent reads its exit status via `wait()`. The kernel then frees the process entry.

**Problem:** if the parent process dies without reading the child's exit status, or if the parent is poorly written and never calls `wait()`, the zombie stays in the process table.

```bash
# Find zombies:
ps aux | grep Z
ps -eo pid,stat,cmd | grep ^Z

# See parent of a zombie:
ps -eo pid,ppid,stat,cmd | grep Z

# Kill a zombie:
# You CANNOT kill a zombie (it's already dead)
# You must kill its parent — killing the parent re-parents the zombie to PID 1 (systemd/init)
kill -9 <parent_pid>
# or
kill -9 $(ps -eo pid,ppid,stat,cmd | grep Z | awk '{print $2}')
```

## Orphan Processes

An orphan is a process whose parent has died. The orphan is immediately **reparented to PID 1** (systemd/init), which then waits for it properly. Orphans are normal and harmless — systemd takes care of them.

```bash
# See orphaned processes (PPID = 1):
ps -eo pid,ppid,cmd | awk '$2 == 1'
```

## Foreground vs Background

```bash
# Run in foreground (blocks terminal):
./my-script.sh

# Run in background (returns immediately):
./my-script.sh &

# Background jobs in current shell:
jobs                    # list background jobs in this terminal
fg %1                  # bring job 1 to foreground
bg %1                  # resume stopped job 1 in background
Ctrl+Z                 # suspend foreground job (sends SIGTSTP)
```

## Quick Reference

```bash
# View processes
ps aux                 # all processes
ps -ef                 # with PPID
ps -ef --forest        # tree view

# Live monitoring
top
htop

# Find a process
pgrep nginx            # PIDs of nginx
pidof nginx            # PID (exact name match only)

# Kill
kill 1234              # SIGTERM (polite)
kill -9 1234           # SIGKILL (force)
kill -HUP 1234         # reload config
kill -STOP 1234        # suspend
kill -CONT 1234        # resume

# Background
./script.sh &          # run in background
nohup ./script.sh &    # survives terminal close
disown                  # detach from shell

# Check state
ps -eo pid,stat,cmd | grep R    # running
ps -eo pid,stat,cmd | grep Z    # zombies
ps -eo pid,stat,cmd | grep D    # uninterruptible sleep
```