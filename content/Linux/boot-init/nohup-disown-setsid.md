---
title: nohup, disown, and setsid
description: Linux process detachment — nohup, disown, setsid, SIGHUP, terminal control, running processes in background
tags:
  - linux
  - shell
  - processes
---

# nohup, disown, and setsid

These three tools handle the problem of **detaching processes from the terminal** — making them immune to SIGHUP (the signal sent when a terminal disconnects). They're essential for long-running tasks that must survive disconnects.

## The Problem: SIGHUP

When a terminal disconnects (logout, network drop, SSH timeout), the kernel sends **SIGHUP** to all processes in the session:

```
Terminal disconnects
        ↓
Kernel sends SIGHUP to session leader
        ↓
SIGHUP propagates to all processes in the session
        ↓
Default SIGHUP handler: terminate the process
```

This is why your `scp largefile` dies when your SSH session drops.

## nohup — Survive SIGHUP

`nohup` runs a command with SIGHUP ignored:

```bash
# Basic usage
nohup ./long-running-script.sh &
# Output goes to nohup.out by default
nohup ./script.sh > /tmp/output.log 2>&1 &

# Key point: the process ignores SIGHUP
# It will survive terminal disconnect
```

**What nohup does:**
1. Signals the kernel to ignore SIGHUP for this process
2. Redirects stdin from `/dev/null` (can't read from terminal anyway)
3. Redirects stdout/stderr to `nohup.out` (unless you redirect)

**Limitation:** nohup only ignores SIGHUP. If the process is a **session leader** with a controlling terminal, it may still receive SIGHUP via the controlling terminal (not just the signal). `nohup` fixes this by calling `setsid` internally on some systems.

## disown — Remove from Job Table

`disown` is a **bash/zsh builtin** that removes a running job from the shell's job table:

```bash
# Start a job
./long-running-script.sh &
# [1] 12345

# Disown it (removes from job table, keeps running)
disown %1

# Disown all jobs
disown -a

# Disown the most recent job
disown %%

# Disown without % — by PID
disown 12345
```

**What disown does:**
- Removes the job from the shell's job table
- The shell won't send SIGHUP to it on exit
- Process keeps running

**Unlike nohup**, disown can remove an already-running process from the shell's control without restarting it.

## setsid — New Session

`setsid` creates a **new session** (new SID, no controlling terminal):

```bash
# Run in a completely new session (detached from terminal)
setsid ./long-running-script.sh &

# With output redirection
setsid bash -c './script.sh > /tmp/out.log 2>&1'

# From an interactive shell:
# 1. setsid forks a new process
# 2. That new process becomes session leader
# 3. The original shell's terminal is NOT the controlling terminal
# 4. Even if original shell exits, the new session survives
```

**What setsid does:**
1. `fork()` — creates a new process
2. `setsid()` — makes it a session leader with no controlling terminal
3. `exec()` — runs the command

**The result:** The process is in its own session, completely detached. Even root killing the original shell won't affect it.

## Comparison

| Feature           | nohup              | disown             | setsid            |
|-----------------|--------------------|--------------------|-------------------|
| Scope           | Per-command        | Removes existing job | New session    |
| Works on shells  | Any               | bash/zsh only      | Any              |
| Removes TTY     | No (may still have) | Yes (job table)   | Yes (new session)|
| Survives HUP    | Yes               | Yes                | Yes               |
| Can detach existing | No             | Yes                | Via setsid -c    |
| Complexity      | Simplest           | Simple             | Medium            |

## Practical Patterns

### Pattern 1: Run and disconnect immediately

```bash
# Run long job, nohup it, background it
nohup ./long-job.sh > /tmp/long-job.log 2>&1 &
disown %1

# Or simpler:
nohup ./long-job.sh > /tmp/long-job.log 2>&1 &
# nohup already backgrounds and ignores SIGHUP
```

### Pattern 2: Detach an already-running job

```bash
# Job is running in foreground (Ctrl+Z to pause, then bg)
bg
# [1]+ ./long-job.sh &

# Now disown it
disown %1

# Now log out — it keeps running
```

### Pattern 3: Completely new session (most robust)

```bash
# Create new session, redirect output
setsid bash -c 'exec ./long-job.sh > /tmp/out.log 2>&1'

# Or with nohup + setsid combo:
# (nohup handles signal, setsid handles session)
nohup setsid ./long-job.sh > /tmp/out.log 2>&1 &
```

### Pattern 4: tmux/screen (best for long sessions)

```bash
# tmux handles disconnects natively
tmux new -s mysession
# Inside tmux:
./long-job.sh
# Detach: Ctrl+b d
# Reattach: tmux attach -t mysession
```

## Why tmux/screen is Often Better

```
Problem with nohup/disown/setsid:
  You close the terminal
  → Process keeps running
  → But you have no way to see its output or bring it back

tmux/screen:
  You close the terminal
  → tmux keeps running
  → You reattach and see live output
  → Full terminal emulation preserved
```

## Exit Codes and the Controlling Terminal

```bash
# Check if a process has a controlling terminal:
ps -o pid,tty,cmd | grep long-job

# ? means no TTY (detached)
# pts/0 means attached to terminal

# In a new session (setsid):
ps -o pid,tty,cmd | grep long-job
# ?       # no controlling terminal
```