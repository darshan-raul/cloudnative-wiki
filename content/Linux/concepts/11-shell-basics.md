---
title: "11 — Shell Basics"
description: Linux shell basics — bash, environment, PATH, aliases, history, tab completion, pipes, job control
tags:
  - linux
  - concepts
---

# 11 — Shell Basics

The shell is your primary interface to Linux. It's a program that interprets commands, manages processes, and provides scripting capabilities. Most Linux systems use **bash** (Bourne Again Shell).

## Running Commands

```bash
# Basic command syntax:
command argument1 argument2

# Examples:
ls /home
cp file.txt /tmp/
rm -rf /tmp/build

# Multiple commands on one line:
make && ./build.sh        # run make, then if it succeeds, run build.sh
make || ./fallback.sh   # run make, if it fails run fallback
```

## Environment and Variables

```bash
# Create a variable:
name="Darshan"
version=42

# Use it:
echo $name
echo "Hello $name"
echo "Version: ${version}"

# Environment variables (inherited by child processes):
export EDITOR="vim"
export PATH="/opt/myapp/bin:$PATH"
# Add to ~/.bashrc to persist across sessions:
echo 'export PATH="/opt/myapp/bin:$PATH"' >> ~/.bashrc

# Show environment:
env
printenv HOME
printenv USER

# One-off environment for a command:
FOO=bar myscript.sh
```

## PATH — Where the Shell Looks for Commands

```bash
# Check your PATH:
echo $PATH
# /usr/local/bin:/usr/bin:/bin

# When you type 'ls', shell searches each PATH directory in order
# until it finds ls and executes it

# Add a directory to PATH:
export PATH="/opt/myapp/bin:$PATH"

# Current directory is NOT in PATH by default (intentional security)
# To run a script in current directory:
./myscript.sh
```

## Aliases — Shortcuts for Long Commands

```bash
# Create an alias:
alias ll='ls -la'
alias gs='git status'
alias ..='cd ..'
alias ...='cd ../..'

# Show all aliases:
alias

# Remove alias:
unalias ll

# Make aliases permanent (add to ~/.bashrc):
echo "alias ll='ls -la'" >> ~/.bashrc
```

## History — Command History

```bash
# Show history:
history

# Repeat last command:
!!

# Repeat last command starting with 'git':
!git

# Repeat command #123:
!123

# Last argument of previous command:
ls /long/path/to/file.txt
cat !$
# expands to: cat /long/path/to/file.txt

# Search history:
Ctrl+R
# type to search, Enter to run, Ctrl+R again to cycle

# History expansion:
!!         # last command
!$         # last argument
!^         # first argument
!n         # nth command
!-n        # nth command ago
```

## Tab Completion

```bash
# Press Tab once: completes if unambiguous
# Press Tab twice: shows all possibilities

# Complete commands:
ls<Tab>
ls -<Tab>

# Complete files:
cat my<Tab>

# Complete variables:
echo $HO<Tab>

# Complete hostnames (from ~/.ssh/known_hosts):
ssh de<Tab>
```

## Pipes and Redirection

```bash
# Pipe — send output of one command as input to another:
ls -la | less           # paginate long directory listings
ps aux | grep nginx    # find nginx in process list
df -h | grep sda       # find disk usage for specific disk

# Redirect output to file:
ls > filelist.txt      # overwrite
ls >> filelist.txt     # append

# Redirect stderr (2):
find / -name nginx 2>/dev/null   # suppress errors
command > output.txt 2>&1       # stdout and stderr to file

# /dev/null — discard output:
command > /dev/null              # discard stdout
command 2>/dev/null             # discard errors
command > /dev/null 2>&1       # discard everything
```

## Job Control — Background and Foreground

```bash
# Run in background:
./long-running-script.sh &

# List background jobs:
jobs
# [1]+  Running    ./build.sh &
# [2]-  Stopped    vim notes.md

# Bring to foreground:
fg %1

# Send to background (while running):
Ctrl+Z        # suspends (stops) the job
bg %1         # resumes it in background

# Kill a background job:
kill %1
```

## Shell Configuration

```bash
# ~/.bashrc — runs for interactive non-login shells
# ~/.bash_profile or ~/.profile — runs for login shells

# Common ~/.bashrc additions:
alias ll='ls -la'
export EDITOR=vim
export VISUAL=vim
export PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '

# Apply without logging out:
source ~/.bashrc
```

## Quick Reference

```bash
# Command basics
command arg1 arg2
cmd1 && cmd2   # cmd2 only if cmd1 succeeds
cmd1 || cmd2   # cmd2 only if cmd1 fails

# Variables
name="value"
echo $name
export VAR=value

# PATH
echo $PATH
export PATH="/new/path:$PATH"

# Aliases
alias ll='ls -la'
unalias ll

# History
history
!!
!string
Ctrl+R

# Pipes and redirects
cmd1 | cmd2
cmd > file.txt
cmd 2>/dev/null

# Job control
Ctrl+Z   # suspend
bg        # background
fg        # foreground
jobs      # list jobs
kill %1   # kill job 1
```