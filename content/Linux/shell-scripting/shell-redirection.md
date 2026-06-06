---
title: Shell Redirection
description: File descriptors, stdin/stdout/stderr, redirection operators, process substitution, and here-docs in Linux
tags:
  - linux
  - shell
  - bash
---

# Shell Redirection

Linux treats everything as a file — regular files, devices, sockets, and pipes all have file descriptors. Every process starts with three open file descriptors by default. Understanding redirection means understanding file descriptors and how the shell routes data between them.

## File Descriptors

| FD | Name              | Default Destination | Shell Symbol |
|----|-------------------|---------------------|--------------|
| 0  | Standard Input    | Keyboard            | -            |
| 1  | Standard Output   | Terminal            | -            |
| 2  | Standard Error    | Terminal            | -            |

> **FD 0, 1, 2 are inherited from the parent.** The shell doesn't create them — `exec()` just passes them through. When you open a new file descriptor with `>` or `<`, the kernel assigns the next available number (3, 4, 5...).

## Basic Redirection

| Operator   | Meaning                                              | Example                      |
|------------|------------------------------------------------------|------------------------------|
| `>`        | Redirect stdout, overwrite                           | `ls > file.txt`              |
| `>>`       | Redirect stdout, append                             | `echo "x" >> file.txt`       |
| `<`        | Redirect stdin from                                 | `wc -l < file.txt`           |
| `2>`       | Redirect stderr, overwrite                           | `cmd 2> errors.txt`          |
| `2>>`      | Redirect stderr, append                              | `cmd 2>> errors.log`         |
| `&>`       | Redirect both stdout + stderr, overwrite            | `cmd &> output.txt`          |
| `&>>`      | Redirect both stdout + stderr, append               | `cmd &>> output.txt`         |
| `n>&m`     | Redirect FD `n` to the same target as FD `m`        | `2>&1` redirects 2 → 1       |
| `n<&m`     | Redirect FD `n` from the same source as FD `m`      | `0<&5` redirects 0 → 5       |

### Order Matters (Critical)

Redirections are processed left to right. This is the most common mistake:

```bash
# WRONG — stderr still goes to screen, then stdout is redirected
command 2>&1 > /dev/null
#   ^^^ stderr points to screen (target of 1 at this point)
#            ^^^ stdout now points to /dev/null, but stderr still screen

# CORRECT — stdout redirected first, then stderr follows it
command > /dev/null 2>&1
#   ^^^ stdout → /dev/null
#         ^^^ stderr now points to where stdout is (/dev/null)
```

The shell resolves `&1` at the moment it's parsed, not at execution time. So redirect `>` first, then use `&1` to copy that destination.

### Modern Shorthand

Bash 4+ provides `&>` and `&>>` as cleaner alternatives to `> file 2>&1`:

```bash
# These are equivalent:
command > /dev/null 2>&1
command &> /dev/null        # bash 4+

# Append variants:
command >> out.txt 2>&1
command &>> out.txt         # bash 4+
```

## `/dev/null`

The null device is a special file that discards everything written to it and returns EOF on read. It's a sinkhole — writes succeed but data is lost.

```bash
# Silently discard all output (stdout and stderr)
command > /dev/null 2>&1

# Discard only errors, see results:
command 2> /dev/null

# Create an instantly-empty file:
> /path/to/file    # truncates to zero bytes
```

## The `>/dev/null 2>&1` Breakdown

### ELI5: The Two Pipes

Think of a command as a pump with two output pipes:

- **Pipe 1** (stdout): sends clean output
- **Pipe 2** (stderr): sends error messages

Normally both pump into your terminal screen.

```bash
# Step 1: Pipe 1 goes to /dev/null (the shredder)
command > /dev/null
# Step 2: Pipe 2 is taped to Pipe 1's destination
command 2>&1
```

Result: both pipes dump into the shredder → complete silence.

### Real-World Use Cases

```bash
# Cron: run silently, no email on success or failure
0 * * * * /opt/backup.py > /dev/null 2>&1

# Find files but suppress "Permission denied" spam
find / -name "myfile.conf" 2> /dev/null

# Background job: silence output but keep shell responsive
long_running_task > /tmp/log 2>&1 &

# Silent curl (just exit code)
curl -s https://example.com > /dev/null 2>&1
```

## Process Substitution `<()` and `>()`

Process substitution replaces a `()` with a file descriptor that points to a pipe. The shell spawns a subshell and connects the command's stdout (or stdin) to that fd.

```bash
# <(cmd) — replaces with a fd containing cmd's stdout
diff <(ls /bin) <(ls /usr/bin)

# >(cmd) — replaces with a fd that feeds cmd's stdin
grep -v "^#" > >(sed 's/^/NoComment: /')

# Practical: compare sorted and unsorted unique counts
comm <(sort file1) <(sort file2)

# See stderr AND stdout separately
cmd > >(tee stdout.log) 2> >(tee stderr.log >&2)
```

> **Limitation:** Process substitution is bash-specific (not POSIX sh). It's not available in `/bin/sh`.

## Here-Docs and Here-Strings

### Here-Document (`<<`)

Reads stdin until a line containing only the delimiter. Commonly used for multi-line strings in scripts.

```bash
cat <<EOF
Inventory Report
Generated: $(date)
Status: $STATUS
EOF

# Quoted delimiter prevents variable expansion:
cat <<'ENDMARKER'
The variable \$STATUS will appear literally.
$HOME will not expand.
ENDMARKER

# Indented here-doc (<<- strips leading tabs):
cat <<-EOF
    This indentation is stripped.
    $VAR still expands.
EOF
```

### Here-String (`<<<`)

Feeds a single string as stdin, useful for single-line input:

```bash
wc -w <<< "hello world how many words"
# Output: 4

# vs piping (subshell not required):
echo "hello world how many words" | wc -w
# Output: 4

# Useful with read:
read -r name age city <<< "Alice 30 London"
```

## Redirecting to Multiple Targets (tee)

`tee` splits stdout — one copy goes to a file, one to stdout (and ultimately the next pipe in the chain):

```bash
# Log output AND see it on screen
command | tee /var/log/command.log

# Append to log (not overwrite)
command | tee -a /var/log/command.log

# Both stdout and stderr:
command 2>&1 | tee output.log

# Pipe only stdout, stderr still silenced:
command | tee /dev/null > /dev/null
```

## Named Pipes (FIFOs)

A named pipe is a file that acts like a pipe — data written to it blocks until data is read from the other end. Unlike `|`, two processes don't need to be started together.

```bash
# Create a named pipe
mkfifo /tmp/my-pipe

# Terminal 1: read from it
cat /tmp/my-pipe

# Terminal 2: write to it
echo "hello" > /tmp/my-pipe

# Real use case: log rotation without losing data
logger -f /var/log/myapp.log &
mkfifo /tmp/log-archive-pipe
compress < /tmp/log-archive-pipe > /var/archive/$(date +%Y%m%d).gz &
mv /var/log/myapp.log /tmp/log-archive-pipe
```

## exec: Manipulating File Descriptors Programmatically

`exec` modifies file descriptors for the current shell (not a subshell):

```bash
# Redirect all future stdout to a file (log accumulation)
exec 1>> /var/log/myscript.log

# Open a file descriptor for reading (use as stdin)
exec 3< /etc/passwd
read line <&3

# Open a file descriptor for writing
exec 4> /tmp/output.txt
echo "hello" >&4

# Close a file descriptor
exec 3<&-

# Redirect stderr to stdout (captured in a variable)
output=$(command 2>&1)
```

## Common Patterns Quick Reference

```bash
# Silent success — discard everything
cmd > /dev/null 2>&1

# Show stdout only (hide errors)
cmd 2> /dev/null

# Show errors only (hide output)
cmd > /dev/null

# Capture both in one variable
result=$(cmd 2>&1)

# Separate streams to different files
cmd > output.log 2> error.log

# Capture status but discard output
cmd > /dev/null 2>&1; status=$?

# tee: see AND log
cmd 2>&1 | tee /var/log/cmd.log

# pipe ONLY stdout, let stderr hit terminal
cmd | other_cmd

# stdin from a string
cmd <<< "input data"
```