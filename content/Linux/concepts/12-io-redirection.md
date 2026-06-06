---
title: "12 — Input/Output Redirection"
description: Linux I/O redirection — stdin, stdout, stderr, pipes, tee, xargs, here-docs, here-strings
tags:
  - linux
  - concepts
---

# 12 — Input/Output Redirection

Every command has three standard streams:
- **stdin (0)** — input (keyboard, pipe)
- **stdout (1)** — normal output (terminal)
- **stderr (2)** — error messages (terminal)

Redirection lets you control where these streams go.

## The Three Streams

```
stdin  (0) ←  keyboard, pipe, here-doc
stdout (1) →  terminal (by default)
stderr (2) →  terminal (by default)
```

## Basic Redirection

```bash
# Redirect stdout to a file:
ls > filelist.txt          # overwrite
ls >> filelist.txt         # append

# Redirect stderr to a file:
find / -name nginx 2> errors.txt

# Redirect both stdout and stderr:
command > all.txt 2>&1    # redirect stderr to stdout, then write stdout
command &> all.txt        # shorthand (bash 4+)
command &>> all.txt       # append both

# Discard output:
command > /dev/null        # discard stdout
command 2> /dev/null       # discard stderr
command > /dev/null 2>&1  # discard everything

# Redirect stderr to stdout, then discard:
command > /dev/null 2>&1
```

## Pipes — Chain Commands

```bash
# stdout of cmd1 becomes stdin of cmd2:
ps aux | grep nginx
ls -la | head -20
cat /var/log/syslog | grep sshd | tail -50

# pipe both stdout and stderr:
command |& grep pattern   # bash 4+

# chain multiple:
cat /var/log/auth.log | grep Failed | awk '{print $NF}' | sort | uniq -c | sort -rn
```

## tee — Write and Pass Through

`tee` reads stdin, writes to a file AND passes to stdout — useful when you want to see output while also saving it.

```bash
# Show output AND save to file:
ls -la | tee filelist.txt

# Append to file:
ls -la | tee -a filelist.txt

# tee to multiple files:
ls -la | tee file1.txt file2.txt file3.txt

# With sudo (tee to a file owned by root):
command | sudo tee /etc/app/config.txt > /dev/null
# Equivalent to: command > /etc/app/config.txt (but requires sudo)
```

## xargs — Build Commands from stdin

`xargs` reads items from stdin and passes them as arguments to a command.

```bash
# Find files and delete them:
find /tmp -name "*.tmp" | xargs rm

# Find and copy:
find . -name "*.jpg" | xargs cp -t /backup/photos/

# Confirm before running (interactive):
find . -name "*.log" | xargs -p rm

# Limit items per command:
find . -name "*.tmp" | xargs -n 10 rm
# runs 'rm file1 file2 ... file10', 'rm file11 ...', etc.

# Run with arguments in a specific location:
find . -name "*.txt" | xargs -I{} mv {} /archive/

# Use null as delimiter (safer for filenames with spaces):
find . -name "*.txt" -print0 | xargs -0 rm
```

## here-doc — Inline Input

A here-doc feeds a block of text into a command's stdin.

```bash
# Basic here-doc:
cat <<EOF
Hello $name
Current directory: $(pwd)
EOF

# Indented here-doc (<<- strips tabs):
cat <<-EOF
    This is indented
    EOF

# No variable expansion (single quotes):
cat <<'EOF'
Hello $name
Current directory: $(pwd)
EOF
# prints: Hello $name and $(pwd) literally

# with sudo:
sudo tee /etc/app.conf <<EOF
port=3000
host=0.0.0.0
EOF
```

## here-string — String as stdin

```bash
# Feed a string as stdin:
echo "one two three" | wc -w
# 3

# Read string into variable:
read -r a b c <<< "hello world foo"
echo "$a $b $c"
# hello world foo

# Use with grep:
grep "pattern" <<< "this line has pattern in it"
```

## Combining Redirections

```bash
# stdout to file, stderr to stdout (console):
command > output.txt 2>&1

# stdout to /dev/null, stderr to file:
command 2> errors.txt > /dev/null

# stdout to file, stderr to same file (append):
command >> output.txt 2>&1

# Both to separate files:
command > stdout.txt 2> stderr.txt

# Discard errors, keep output:
command 2>/dev/null

# Keep errors, discard output:
command > /dev/null
```

## Process Substitution

```bash
# Use output of a command as a file argument:
diff <(ls /dir1) <(ls /dir2)
# Compares directory listings without temp files

# Read from a command as input:
while read -r line; do
  echo "Line: $line"
done < <(grep pattern /var/log/syslog)

# Write to a command:
tee >(gzip > output.gz) largefile
# Writes to both stdout and a gzip compression
```

## Common Patterns

```bash
# Suppress all output (silent):
command > /dev/null 2>&1

# Log output with timestamp:
command 2>&1 | while read -r line; do
  echo "[$(date)] $line"
done | tee /var/log/output.log

# Split output (console + file):
command | tee /var/log/output.log

# Build a file with here-doc:
cat > /tmp/config.txt <<EOF
option1=value1
option2=value2
EOF

# Find and operate:
find . -type f -name "*.bak" | xargs rm -f

# xargs with sudo:
cat /etc/passwd | xargs -I{} echo "User: {}"
```

## Quick Reference

```bash
# Redirect
cmd > file.txt           # stdout to file
cmd >> file.txt          # append stdout
cmd 2> errors.txt        # stderr to file
cmd > file.txt 2>&1      # both to same file
cmd &> file.txt         # both (bash 4+)
cmd &>> file.txt        # append both
cmd > /dev/null 2>&1    # discard everything

# Pipe
cmd1 | cmd2             # pipe stdout
cmd1 |& cmd2            # pipe both (bash 4+)

# tee
cmd | tee file.txt      # write + pass through
cmd | tee -a file.txt   # append + pass through

# xargs
find . | xargs cmd      # pass filenames to cmd
find . -print0 | xargs -0 cmd  # safe with spaces
find . | xargs -n1 cmd   # one arg at a time
find . | xargs -p cmd    # confirm before running

# here-doc
cat <<EOF
text
EOF

# here-string
cmd <<< "string input"

# process substitution
diff <(cmd1) <(cmd2)
```