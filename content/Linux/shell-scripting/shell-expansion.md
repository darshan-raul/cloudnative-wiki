---
title: Shell Expansion
description: Linux shell expansion — brace, tilde, parameter, variable, command, arithmetic, and filename expansion in bash
tags:
  - linux
  - shell
---

# Shell Expansion

When you type a command, the shell performs **multiple rounds of expansion** before executing it. Understanding the order prevents bugs and helps write efficient shell scripts.

## Expansion Order

```
1. Brace Expansion     {a,b,c}        → a b c
2. Tilde Expansion     ~user          → /home/user
3. Parameter Expansion $var, ${var}   → value
4. Command Substitution $(cmd), `cmd` → command output
5. Arithmetic Expansion $((expr))     → result
6. Word Splitting      (split on IFS) → multiple words
7. Glob/Pathname       *, ?, [...]    → filenames
8. Quote Removal       \ ' "          → stripped
```

**Important:** Expansion happens **left to right**, and each result becomes input for the next. This is why `*` expansion happens AFTER variable expansion — not before.

## Brace Expansion

```bash
# Generate sequences
echo {1..5}           # 1 2 3 4 5
echo {01..10}         # 01 02 03 04 05 06 07 08 09 10
echo {a..z}           # a b c ... z
echo {1,2,3}{a,b}     # 1a 1b 2a 2b 3a 3b

# Practical uses
cp file.txt{,.bak}   # file.txt file.txt.bak
mkdir -p project/{src,lib,tests,docs}
touch page{1..10}.html

# WARNING: empty expansion if {} is empty
echo {}.txt           # {}.txt (literal if no match)
```

## Tilde Expansion

```bash
~             → /home/currentuser
~user         → /home/user's home
~root         → /root
~+            → $PWD (current directory)
~-            → $OLDPWD (previous directory)

# Useful in PATH or CDPATH
export CDPATH=~-/projects
cd myproject  # cd ~-/projects/myproject
```

## Parameter and Variable Expansion

```bash
# Basic
echo $USER             # value of USER
echo ${USER}           # same (braces needed for delimiting)
echo ${USER:-default}  # use default if unset
echo ${var:=default}   # set default if unset
echo ${var:+alt}       # use alt if set
echo ${var:?error}     # error if unset

# String operations
${#var}               # length of var
${var:offset}         # substring from offset
${var:offset:len}     # substring length len
${var#pattern}        # remove shortest match from start
${var##pattern}       # remove longest match from start
${var%pattern}        # remove shortest match from end
${var%%pattern}       # remove longest match from end
${var/pattern/string} # replace first match
${var//pattern/string} # replace all matches

# Examples
path="/usr/local/bin/myapp"
echo ${path##*/}      # myapp (basename)
echo ${path%/*}        # /usr/local/bin (dirname)
echo ${#path}         # 18 (length)
echo ${path/bin/BIN}   # /usr/local/BIN/myapp
```

## Command Substitution

```bash
# Two forms
$(command)              # modern, recommended
`command`               # legacy, backticks

# Examples
now=$(date +%s)        # store command output in variable
files=$(ls *.txt)      # all .txt files
uptime=$(uptime)
cpu=$(cat /proc/cpuinfo | grep "model name" | head -1)

# Nesting
tar -czf "$(hostname)-$(date +%F).tar.gz" /home

#Pitfall: trailing newlines stripped
result=$(echo -e "a\nb\n")  # result = "a" + "b", no trailing newline
```

## Arithmetic Expansion

```bash
echo $((2 + 3))        # 5
echo $((10 / 3))       # 3 (integer division)
echo $((10 % 3))       # 1 (modulo)
echo $((2 ** 10))      # 1024 (power)

# Variables
a=5
b=3
echo $((a * b))        # 15

# Increment/decrement
((i++))               # post-increment, returns old value
((++i))               # pre-increment, returns new value
```

## Word Splitting

After expansion, the shell splits results on **IFS** (Internal Field Separator, default: space, tab, newline):

```bash
var="a b c"
echo $var              # a b c (split into 3 words)
set -f                 # disable glob
set -- a b c
# IFS matters:
var="a:b:c"
IFS=: read -r a b c <<< "$var"  # read with : delimiter
```

## Glob / Pathname Expansion

```bash
# * = any string (except leading .)
ls /etc/*.conf         # all .conf in /etc
ls /etc/???.conf       # exactly 3-letter .conf files
ls /etc/[a-z]*.conf    # a through z then anything

# ? = any single character
ls /dev/tty?

# Character classes
ls -la ~/[Dd]ocuments
ls /usr/bin/[a-zA-Z]*

# ls -d */  # directories only
```

**Important**: If no files match, the glob is passed literally (not expanded):

```bash
ls /nonexistent/*.txt
# ls: cannot access '/nonexistent/*.txt': No such file or directory
# On newer shells: literal * passed if no match
```

To force nullglob (treat no-match as empty):
```bash
shopt -s nullglob
```

## Quote Removal

```bash
# Backslash escapes
echo \$HOME            # $HOME (literal dollar)
echo \\                # \ (literal backslash)
echo \$((2+2))         # $((2+2)) (no expansion)

# Double quotes: $ \ ` remain active
echo "$USER"           # value of USER
echo "Home: $HOME"     # variable expanded
echo "Backtick: `date`" # command substitution works
echo "Cost: \$100"      # literal $

# Single quotes: everything literal
echo '$USER costs $100'
# Output: $USER costs $100

# Double vs single
var=hello
echo "$var"            # hello
echo '$var'            # $var
```

## Practical Patterns

### Safe filename with spaces

```bash
# WRONG:
files=$(ls "$dir")     # breaks on spaces
for f in $files; do    # each SPACE-sep word
# RIGHT:
while IFS= read -r file; do
    echo "Found: $file"
done < <(ls -1 "$dir")
```

### Parameter expansion for defaults

```bash
# Use default if not set
PORT=${PORT:-8080}
CONFIG=${CONFIG:-/etc/myapp.conf}
```

### Batch rename

```bash
# Rename .txt to .bak
for f in *.txt; do
    mv "$f" "${f%.txt}.bak"
done
# ${f%.txt} removes .txt suffix
```