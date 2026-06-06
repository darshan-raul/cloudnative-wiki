---
title: Exit Codes
description: Linux exit codes — $?, set -e, set -u, error handling, ||, &&, exit
tags:
  - linux
  - shell
---

# Exit Codes

Every command returns an **exit code** (status) when it finishes. 0 = success, non-zero = failure. Understanding exit codes is the foundation of robust shell scripting.

## Basics

```bash
# Exit code of last command
echo $?
# 0 = success
# 1 = general error
# 2 = misuse of shell builtin
# 126 = command not executable
# 127 = command not found
# 128 + N = signal N (e.g., 130 = SIGINT/Ctrl+C)

# Check exit code explicitly
command
result=$?
if [ $result -eq 0 ]; then
    echo "Success"
else
    echo "Failed with code $result"
fi

# In conditional:
if grep -q pattern file; then
    echo "Found"
else
    echo "Not found"
fi
```

## Common Exit Codes

| Code | Meaning | Common cause |
|------|---------|--------------|
| 0 | Success | All good |
| 1 | General error | grep finds nothing, mild failure |
| 2 | Misuse of shell builtin | Syntax error in built-in |
| 126 | Not executable | Missing `+x`, wrong shebang |
| 127 | Command not found | Typo, PATH issue |
| 128 | Invalid exit arg | `exit "string"` |
| 130 | Ctrl+C (SIGINT) | User interrupt |
| 137 | SIGKILL (128+9) | `kill -9` |
| 139 | SIGSEGV (128+11) | Segmentation fault |

## Logical Operators and Exit Codes

```bash
# && — run second only if first succeeds (exit code 0)
cd /tmp && tar czf /backup.tar.gz .

# || — run second only if first fails (non-zero)
cd /tmp || echo "cd failed"

# ; — always run (ignore exit code)
cd /tmp ; echo "always runs"

# Combining:
cd /tmp && tar czf backup.tar.gz . || { echo "Backup failed"; exit 1; }

# ! — negate (success→failure, failure→success)
if ! grep -q pattern file; then
    echo "Pattern not found"
fi
```

## set -e and set -u

```bash
# -e: exit immediately if any command fails
set -e
cd /tmp
./failing-script    # script exits non-zero → shell exits immediately
echo "Never reached"

# -u: treat unset variables as error
set -u
echo $UNDEFINED_VAR   # bash: UNDEFINED_VAR: unbound variable → exit

# Combine:
set -eu

# -e is subtle: &&, ||, conditionals don't trigger exit
set -e
true                 # exit code 0 — continue
false || true        # || — doesn't trigger -e (right side runs)
false && true        # && — continues if right succeeds
if false; then       # if conditionals — don't trigger -e
    echo "no"
fi
```

## trap — Catch Signals and Errors

```bash
# Run code on EXIT (any reason)
trap 'echo "Cleaning up"; rm -f /tmp/lock' EXIT

# Run on ERR (command returned non-zero in -e mode)
trap 'echo "Error on line $LINENO"' ERR

# Run on SIGINT
trap 'echo "Interrupted"; exit 1' INT

# Cleanup function pattern:
cleanup() {
    rm -f /tmp/pid
    echo "Done"
}
trap cleanup EXIT

# Better: save old trap, restore
old_trap=$(trap -p EXIT)
trap 'cleanup; eval "$old_trap"' EXIT
```

## Getting Exit Codes from Pipelines

```bash
# In bash, $? is the EXIT CODE of the LAST command in a pipeline
# To get exit code of any command in a pipeline, use PIPESTATUS

# Example: grep fails but cat succeeds
cat file | grep pattern
echo $?        # 0 (cat succeeds, grep fails — but $? is cat's exit)

# PIPESTATUS array:
cat file | grep pattern
echo "${PIPESTATUS[0]}"  # cat's exit = 0
echo "${PIPESTATUS[1]}"  # grep's exit = 1
echo "${PIPESTATUS[*]}"   # all as array

# check all pipeline stages:
cat file | grep pattern | head
all_ok=true
for code in "${PIPESTATUS[@]}"; do
    [ "$code" -eq 0 ] || all_ok=false
done
$all_ok && echo "All succeeded"
```

## Functions and Exit Codes

```bash
# Function return sets $?
check_user() {
    if id "$1" &>/dev/null; then
        return 0    # success
    else
        return 1    # failure
    fi
}

check_user bob && echo "Bob exists"

# Or return a numeric value (0-255)
get_status() {
    systemctl is-active nginx
}

get_status
# $? = 0 (active) or 3 (inactive) — systemctl is-active returns 3 for inactive
```

## The exit Command

```bash
exit            # exit with status of last command
exit 0          # exit successfully
exit 1          # exit with error
exit 255        # max value (higher wraps)

# In a script: reaching end of script = exit 0
# Explicit exit is better
```

## Debugging with set -x

```bash
#!/bin/bash
set -x    # trace execution: print command with expansion
set -v    # print raw input lines
set -xv   # both

# Or on command line:
bash -x script.sh
```

## set -o Pipefail

```bash
# By default, pipeline $? is last command
# With pipefail, $? is the LAST NON-ZERO exit code:
set -o pipefail

cat file | grep pattern | head
# $? = grep's exit, not head's (grep is last non-zero, head exits 0)
# Without pipefail, $? would be head's exit (0)
```

## Robust Script Template

```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Optional: better error reporting
trap 'echo "Error on line $LINENO"' ERR

# Cleanup on exit
cleanup() { ... }
trap cleanup EXIT

# Your code here
```