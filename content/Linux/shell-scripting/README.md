---
title: Shell Scripting
description: Linux shell scripting — bash, functions, arrays, process substitution, redirection, here-docs, exit codes, shell expansion
tags:
  - linux
  - shell
  - bash
---

# Shell Scripting

Bash scripting turns sequences of commands into repeatable, automatable scripts. This section covers the bash features beyond interactive use: functions, arrays, process substitution, redirection tricks, here-docs, exit code handling, and the various shell expansion modes.

## Quick Reference

**[[bash-cheatsheet|bash cheatsheet]]** — A dense quick reference covering all bash syntax: variables, parameter expansions, conditionals, loops, functions, arrays, case statements, globbing, history, debugging. Modeled on devhints.io/bash — bookmark this one.

## Input/Output

**[[shell-redirection|Shell Redirection]]** — The complete guide to file descriptors: stdin (0), stdout (1), stderr (2). Redirecting and combining them: `>`, `>>`, `2>`, `&>`, `&>>`. Redirecting stderr to stdout or vice versa. The `/dev/null` special file. Why `2>&1` must follow the redirect it's merging.

**[[here-docs|here-docs and here-strings]]** — Feeding multi-line input to a command with `<<EOF`. Indented here-docs with `<<-`. Preventing variable expansion with `<<'EOF'`. Here-strings (`<<<`) for single-line input. Practical uses: generating config files inline, feeding multi-line strings to `cat` or `grep`, `sudo tee` pattern for writing to protected files.

**[[process-substitution|Process Substitution]]** — `<(command)` and `>(command)` — treating command output as a file. Common uses: diffing directory listings (`diff <(ls dir1) <(ls dir2)`), feeding output of a command as input to another (`while read < <(cmd)`), the `tee >(gzip > out.gz)` pattern.

## Shell Expansion

**[[shell-expansion|Shell Expansion Order]]** — The eight types of expansion bash applies, in order: brace expansion → tilde expansion → parameter/variable expansion → command substitution → arithmetic expansion → word splitting → pathname expansion → quote removal. Why `${var:-default}` and `$((i++))` behave the way they do.

## Exit Codes and Error Handling

**[[exit-codes|Exit Codes and set -e]]** — Every command returns an exit code: 0 for success, 1-255 for failure. How `$?` captures it. `set -e` (exit on error), `set -u` (error on undefined variable), `set -o pipefail` (fail if any command in a pipe fails), and `set -x` (trace execution). `trap` for running cleanup on exit or signal.

## Concepts Reference

**[[../concepts/12-io-redirection|I/O Redirection]]** — Part of the beginner curriculum, covers the foundational concept of stdin/stdout/stderr, pipes, tee, and xargs.

**[[../concepts/11-shell-basics|Shell Basics]]** — Part of the beginner curriculum, covers environment variables, PATH, aliases, history, and job control.