---
title: Process Substitution
description: Linux process substitution — <(), >(), using command output as a file, paste, diff, while read loops
tags:
  - linux
  - shell
---

# Process Substitution

Process substitution feeds command output into a **named pipe (FIFO)** or `/dev/fd/*`, so it can be used where a filename is expected. It's a bash/ksh/zsh feature that makes some operations much cleaner.

## The Syntax

```bash
<(command)   # creates a FIFO, runs command, makes FIFO readable as a filename
>(command)   # creates a FIFO, runs command, makes FIFO writable as a filename
```

The shell replaces `<(command)` with a path like `/dev/fd/63` (or `/dev/fd/pipe:[12345]`), which is a file descriptor pointing to a pipe connected to the command's stdout.

## Common Uses

### Diff two command outputs

```bash
# Compare sorted file1 and file2 without temp files
diff <(sort file1.txt) <(sort file2.txt)

# Compare outputs of two commands
diff <(kubectl get pods -o wide) <(sleep 5 && kubectl get pods -o wide)

# Compare df output
diff <(df -h) <(df -h)
```

### While read with a command

```bash
# Process each line of a command's output
# Instead of: command | while read line; do ...; done
# which creates a SUBSHELL (can't modify parent variables)

# Process substitution keeps while loop in main shell:
while IFS= read -r line; do
    echo "$line"
done < <(grep pattern file.txt)
#  ↑               ↑
# redirect stdin  process sub (provides the data)

# More practical:
while IFS= read -r user uid shell; do
    echo "User $user uses shell $shell"
done < <(cut -d: -f1,3,7 /etc/passwd)
```

### Paste files side by side

```bash
# Paste two files column-wise
paste <(ls -1) <(wc -l *)
```

### tee to multiple commands

```bash
# Write to two files at once (tee-like with process sub):
# Not directly possible with >() but:
command > >(tee file1.log) 2>&1 | tee file2.log
# More practical: use tee
command | tee file1.log | tee file2.log
```

## How It Works Internally

```bash
# The path is a named pipe
ls -la <(echo hello)
# lr-xr-x 1 darshan darshan 64 ... /dev/fd/63 -> pipe:[12345]

# The command is running in background:
# bash runs: echo hello > /dev/fd/63
# /dev/fd/63 is a FIFO

# You can read from it:
cat <(echo "hello from subshell")
# Output: hello from subshell
```

## >() — Writing to a Process

```bash
# Sort file in-place using sort's output as input to something:
# (actually this isn't quite right — >() is for redirecting stdout OF a command)

# Real use case: write to two processes simultaneously
tee >(process1) >(process2) > /dev/null
# Output goes to process1, process2, and is discarded

# Practical: send output to two files
some_command > >(grep pattern > matches.txt) 2>&1 | grep -v pattern > no-match.txt
```

## Comparison: Pipe vs Process Substitution

```bash
# PIPE: creates subshell — variables don't persist
cat file | while read line; do
    ((count++))
done
echo $count   # 0 — count is gone (subshell)

# Process Substitution: main shell — variables persist
while read line; do
    ((count++))
done < <(cat file)
echo $count   # actual count — works!
```

## Combining with Arrays

```bash
# Read command output into array
mapfile -t lines < <(ls -1 *.txt)
echo "${lines[0]}"

# Or:
while IFS= read -r line; do
    lines+=("$line")
done < <(ls -1 *.txt)
```

## Error Handling Gotchas

```bash
# Process substitution runs in a SUBSHELL — wait for it if needed
# The PID is the background job managing the FIFO

# In a script:
{
    while read -r line; do
        echo "$line"
    done
} < <(command)

# The process substitution creates a background job
# Bash waits for it implicitly when the redirect closes
```

## Real-World Examples

### Compare current process list to snapshot

```bash
diff <(ps -eo pid,stat,cmd --sort=pid) <(cat /tmp/ps-snapshot.txt)
```

### Run SQL against a CSV without importing

```bash
# sqlite can read from stdin but not multiple CSVs easily
# Process sub gives each CSV as a "file":
sqlite3 :memory: \
  -cmd '.mode csv' \
  -cmd '.import /dev/fd/63 t1' \
  < <(gunzip -c file1.csv.gz)
```

### Parallel processing trick

```bash
# Feed same input to multiple commands:
# (GNU parallel is better for this, but process sub can help)
cat largefile.txt > >(wc -l > linecount.txt) \
               > >(md5sum > md5.txt)
wait  # wait for background processes
```

## Comparison with Named Pipes (FIFO)

```bash
# Manual FIFO approach:
mkfifo /tmp/myfifo
command1 > /tmp/myfifo &
command2 < /tmp/myfifo
rm /tmp/myfifo

# Process substitution is syntactic sugar:
command2 < <(command1)
# Bash creates the FIFO, runs command1 in background, feeds it to command2
```