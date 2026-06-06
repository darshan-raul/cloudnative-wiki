---
title: tmux
description: tmux — terminal multiplexer, sessions, windows, panes, keybindings, copy mode, scripting, and productivity tricks
tags:
  - linux
  - tools
---

# tmux

tmux (Terminal Multiplexer) lets you run multiple terminal sessions in one window, detach and reattach them, split panes, and share sessions between users. It's essential for remote work, long-running processes, and working across multiple tasks simultaneously.

## Sessions, Windows, Panes

```
tmux hierarchy:
  Session    → tmux new -s mysession
    Window   → Ctrl+b c
      Pane   → Ctrl+b %  (vertical split)
                Ctrl+b "  (horizontal split)
```

- **Session**: a persistent running environment
- **Window**: like a terminal tab (one per task/workflow)
- **Pane**: split view within a window

## Core Commands

```bash
# Start tmux (new session, default naming)
tmux

# New named session
tmux new -s webserver

# Attach to existing session
tmux attach -t webserver
tmux attach          # attach to last session

# List sessions
tmux ls
tmux list-sessions

# Detach from session
Ctrl+b d

# Kill session
tmux kill-session -t webserver

# Kill all tmux
tmux kill-server
```

## Key Bindings (Prefix = `Ctrl+b`)

| Action | Key |
|--------|-----|
| Send prefix | `Ctrl+b` |
| New window | `Ctrl+b c` |
| Next window | `Ctrl+b n` |
| Previous window | `Ctrl+b p` |
| List windows | `Ctrl+b w` |
| Rename window | `Ctrl+b ,` |
| Kill window | `Ctrl+b &` |
| Split vertical | `Ctrl+b %` |
| Split horizontal | `Ctrl+b "` |
| Switch pane | `Ctrl+b arrow` |
| Cycle pane | `Ctrl+b o` |
| Swap panes | `Ctrl+b {` `Ctrl+b }` |
| Zoom pane | `Ctrl+b z` |
| Kill pane | `Ctrl+b x` |
| Detach | `Ctrl+b d` |
| Command prompt | `Ctrl+b :` |

## Panes Deep Dive

```bash
# Split current pane horizontally
Ctrl+b "

# Split current pane vertically
Ctrl+b %

# Switch to pane by direction
Ctrl+b arrow-key

# Cycle through panes
Ctrl+b o

# Swap pane with next/prev
Ctrl+b }
Ctrl+b {

# Make pane full screen (zoom)
Ctrl+b z
# Repeat to un-zoom

# Convert pane to window
Ctrl+b !

# Break pane into window
Ctrl+b : break-pane

# Join window into pane
Ctrl+b : join-pane -s -t mywindow

# Resize pane (hold Ctrl+b, then arrow)
Ctrl+b : resize-pane -D 10   # resize down 10
Ctrl+b : resize-pane -U 5    # resize up 5
Ctrl+b : resize-pane -L 20   # resize left 20
Ctrl+b : resize-pane -R 20   # resize right 20
```

## Copy Mode (Scrolling, Searching)

```bash
# Enter copy mode
Ctrl+b [

# Navigation in copy mode
# Arrow keys or vim-style:
h j k l         # left/down/up/right
Ctrl+b          # page up
Space           # start selection
Enter           # copy selection and exit
q               # exit copy mode

# Search
Ctrl+b /         # search forward
?               # search backward (in copy mode)

# Copy to clipboard (if using set-clipboard):
# In tmux 3.0+:
set -g set-clipboard on
# Then in copy mode: select text, Enter to copy, Ctrl+v to paste in any app
```

## Vim-style pane navigation

```bash
# Add to ~/.tmux.conf for vim-style pane switching:
cat >> ~/.tmux.conf << 'EOF'
# Vim-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Mouse support (optional)
set -g mouse on

# Longer prefix escape delay (fixes Esc delay in vim)
set -g escape-time 0
EOF

tmux source-file ~/.tmux.conf
```

## Status Bar

```bash
# Current status bar config:
tmux show-options -g status

# Example custom status bar:
set -g status-bg colour235
set -g status-fg colour255
set -g status-left "#[fg=green]#S #[fg=blue]»"
set -g status-right "#[fg=blue]%Y-%m-%d %H:%M"
set -g status-right-length 50
set -g window-status-format "#I:#W"
set -g window-status-current-format "#[fg=cyan,bold]#I:#W"

# Show activity in other windows:
setw -g monitor-activity on
set -g visual-activity off
```

## Synchronize Panes

```bash
# Type in all panes simultaneously (e.g., run same command on multiple servers)
Ctrl+b :
set synchronize-panes on
# Now everything you type goes to all panes
# Repeat to disable:
set synchronize-panes off

# Practical use: tail logs on multiple servers
# Split into 4 panes, SSH to each, then sync
```

## Scripts and Automation

### Send commands to a session from outside

```bash
# Run command in session (detached)
tmux send-keys -t webserver 'cd /var/log' Enter
tmux send-keys -t webserver 'tail -f nginx/access.log' Enter

# Run full shell script in pane
tmux send-keys -t webserver 'bash -c "ls -la"' Enter

# Capture pane output to file
tmux capture-pane -t webserver:0.1 -p > /tmp/pane-output.txt

# List all panes:
tmux list-panes -t webserver
```

### tmux in scripts (non-interactive)

```bash
# Create session if it doesn't exist
tmux new-session -d -s deploy -c /home/darshan/projects

# Split into panes and run commands
tmux split-window -h -t deploy
tmux send-keys -t deploy:0.0 'cd /home/darshan/projects && git pull' Enter
tmux send-keys -t deploy:0.1 'docker-compose up -d' Enter

# Wait for command to finish:
tmux send-keys -t deploy:0.0 'make build' Enter
tmux pipe-pane -t deploy:0.0 -t /tmp/build.log

# Attach when done:
tmux attach -t deploy
```

### Multi-session startup script

```bash
#!/bin/bash
# ~/.local/bin/tmux-startup

SESSION="work"

# Create if doesn't exist
tmux new-session -d -s "$SESSION" -c ~/projects

# Window 1: editor
tmux new-window -t "$SESSION:1" -n vim -c ~/projects
tmux send-keys -t "$SESSION:1" 'nvim' Enter

# Window 2: servers
tmux new-window -t "$SESSION:2" -n servers -c ~/projects
tmux split-window -h -t "$SESSION:2"
tmux send-keys -t "$SESSION:2.0" 'ssh server1' Enter
tmux send-keys -t "$SESSION:2.1" 'ssh server2' Enter

# Window 3: monitoring
tmux new-window -t "$SESSION:3" -n logs -c /var/log
tmux send-keys -t "$SESSION:3" 'htop' Enter

# Attach
tmux attach -t "$SESSION"
```

## Useful Options

```bash
# ~/.tmux.conf — commonly useful settings

# Enable mouse (click to select, resize panes)
set -g mouse on

# Start window numbering at 1 (not 0)
set -g base-index 1
setw -g pane-base-index 1

# Renumber windows when one is closed
set -g renumber-windows on

# Don't rename windows automatically
set -g allow-rename off

# Set terminal colors
set -g default-terminal "tmux-256color"
set -g default-terminal "screen-256color"

# Faster key repeat
set -g repeat-time 500

# History limit
set -g history-limit 50000

# Focus events (for vim inside tmux)
set -g focus-events on

# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded"
```

## Sessions across SSH

```bash
# On remote server:
ssh server
tmux new -s work

# Detach (Ctrl+b d), logout

# Later, SSH back and reattach:
ssh server
tmux attach -t work

# Or directly attach without creating new:
ssh -t server 'tmux attach'
```

## Share Session (Pair Programming)

```bash
# User A:
tmux -S /tmp/shared new -s pair
chmod 777 /tmp/shared

# User B:
tmux -S /tmp/shared attach

# Both see the same terminal. Anything either types appears to both.
# Warning: both have full control.
```

## Quick Reference

```bash
# Basics
tmux new -s name              # new session
tmux attach -t name            # attach
tmux ls                        # list sessions
Ctrl+b d                       # detach

# Panes
Ctrl+b %                       # vertical split
Ctrl+b "                       # horizontal split
Ctrl+b arrow                   # navigate panes
Ctrl+b z                       # zoom pane

# Windows
Ctrl+b c                       # new window
Ctrl+b n/p                     # next/prev window
Ctrl+b w                       # list windows
Ctrl+b ,                       # rename window

# Copy mode
Ctrl+b [                       # enter copy mode
q                             # exit copy mode
Space                          # start selection
Enter                          # copy

# Scripts
tmux send-keys -t session 'cmd' Enter   # send command
tmux capture-pane -t session:0.0 -p    # capture output
tmux pipe-pane -t session:0.0 -t log   # log pane to file
```