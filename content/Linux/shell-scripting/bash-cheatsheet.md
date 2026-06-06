---
title: Bash Scripting Cheatsheet
description: Quick reference to bash scripting — variables, parameter expansions, conditionals, loops, arrays, functions, globbing, history, and debugging
tags:
  - linux
  - shell
  - cheatsheet
---

# Bash Scripting Cheatsheet

Quick reference for bash scripting. Based on [devhints.io/bash](https://devhints.io/bash).

## Example Script

```bash
#!/usr/bin/env bash

name="John"
echo "Hello $name!"
```

## Variables

```bash
name="John"
echo $name
echo "$name"
echo "${name}!"

# Generally quote your variables unless they contain wildcards to expand.
wildcard="*.txt"
options="iv"
cp -$options $wildcard /tmp
```

## String Quotes

```bash
name="John"
echo "Hi $name"  #=> Hi John
echo 'Hi $name'  #=> Hi $name
```

## Shell Execution

```bash
echo "I'm in $(pwd)"
echo "I'm in `pwd`"  # obsolescent
```

## Conditional Execution

```bash
git commit && git push
git commit || echo "Commit failed"
```

## Functions

```bash
get_name() {
  echo "John"
}

echo "You are $(get_name)"
```

## Conditionals

```bash
if [[ -z "$string" ]]; then
  echo "String is empty"
elif [[ -n "$string" ]]; then
  echo "String is not empty"
fi
```

## Strict Mode

```bash
set -euo pipefail
IFS=$'\n\t'
```

Put at the top of every script. Explanation:
- `set -e` — exit immediately if a command fails
- `set -u` — treat unset variables as an error
- `set -o pipefail` — fail entire pipeline if any command fails
- `IFS=$'\n\t'` — split only on newlines and tabs (not spaces)

## Brace Expansion

```bash
echo {A,B}.js
```

| Expression | Same as |
|------------|---------|
| `{A,B}` | `A B` |
| `{A,B}.js` | `A.js B.js` |
| `{1..5}` | `1 2 3 4 5` |
| `{{1..3},{7..9}}` | `1 2 3 7 8 9` |

## Parameter Expansions

### Basics

```bash
name="John"
echo "${name}"
echo "${name/J/j}"     #=> "john" (substitution)
echo "${name:0:2}"     #=> "Jo" (slicing)
echo "${name::2}"      #=> "Jo" (slicing)
echo "${name::-1}"     #=> "Joh" (slicing)
echo "${name:(-1)}"    #=> "n" (slicing from right)
echo "${name:(-2):1}"  #=> "h" (slicing from right)
echo "${food:-Cake}"   #=> $food or "Cake"
```

```bash
length=2
echo "${name:0:length}"  #=> "Jo"
```

### Path Manipulation

```bash
str="/path/to/foo.cpp"
echo "${str%.cpp}"    # /path/to/foo
echo "${str%.cpp}.o"  # /path/to/foo.o
echo "${str%/*}"      # /path/to

echo "${str##*.}"     # cpp (extension)
echo "${str##*/}"     # foo.cpp (basepath)

echo "${str#*/}"      # path/to/foo.cpp
echo "${str##*/}"     # foo.cpp

echo "${str/foo/bar}" # /path/to/bar.cpp
```

```bash
str="Hello world"
echo "${str:6:5}"    #=> "world"
echo "${str: -5:5}"   #=> "world"
```

```bash
src="/path/to/foo.cpp"
base=${src##*/}   #=> "foo.cpp" (basepath)
dir=${src%$base}  #=> "/path/to/" (dirpath)
dir=${src%/*}     #=> "/path/to" (dirpath)
```

### Prefix Name Expansion

```bash
prefix_a=one
prefix_b=two
echo ${!prefix_*}  # all variables names starting with `prefix_`
#=> prefix_a prefix_b
```

### Indirection

```bash
name=joe
pointer=name
echo ${!pointer}
#=> joe
```

### Substitution

| Expression | Description |
|------------|-------------|
| `${foo%suffix}` | Remove suffix |
| `${foo#prefix}` | Remove prefix |
| `${foo%%suffix}` | Remove long suffix (greedy) |
| `${foo/%suffix}` | Remove long suffix |
| `${foo##prefix}` | Remove long prefix (greedy) |
| `${foo/#prefix}` | Remove long prefix |
| `${foo/from/to}` | Replace first match |
| `${foo//from/to}` | Replace all |
| `${foo/%from/to}` | Replace suffix |
| `${foo/#from/to}` | Replace prefix |

### Length

```bash
${#foo}  # length of $foo
```

### Manipulation

```bash
# Uppercase / lowercase
${foo^} #=> "FOO" (uppercase first)
${foo^^}  #=> "FOO" (uppercase all)
${foo,} #=> "foo" (lowercase first)
${foo,,}  #=> "foo" (lowercase all)
```

## Comments

```bash
# Single line comment
```

```bash
: '
This is a
multi line
comment
'
```

## Substrings

| Expression | Description |
|------------|-------------|
| `${foo:0:3}` | Substring (position, length) |
| `${foo:(-3):3}` | Substring from the right |

## Loops

### For Loop

```bash
for i in {1..5}; do
  echo "Iteration $i"
done
```

```bash
for ((i = 0; i < 10; i++)); do
  echo "$i"
done
```

```bash
for f in *.txt; do
  echo "Processing $f"
done
```

### While Loop

```bash
while [[ $count -lt 10 ]]; do
  echo "$count"
  ((count++))
done
```

### Until Loop

```bash
until [[ $count -ge 10 ]]; do
  echo "$count"
  ((count++))
done
```

### Range-based with step

```bash
for i in {0..10..2}; do
  echo "$i"  # 0, 2, 4, 6, 8, 10
done
```

## Arrays

### Declaration

```bash
fruits=("apple" "banana" "cherry")
fruits[0]="apple"
fruits[1]="banana"
fruits[2]="cherry"
```

### Iteration

```bash
for fruit in "${fruits[@]}"; do
  echo "$fruit"
done
```

### Index iteration

```bash
for i in "${!fruits[@]}"; do
  echo "${fruits[$i]}"
done
```

### Slicing

```bash
${fruits[@]}       # all elements
${fruits[@]:1:2}   # slice: banana cherry
${fruits[@]: -1}   # last element: cherry
```

### Length

```bash
${#fruits[@]}  # number of elements
${#fruits[0]}  # length of first element
```

### Append

```bash
fruits+=("date")
```

### Associative Arrays (Dictionaries)

```bash
declare -A capital
capital[France]="Paris"
capital[Japan]="Tokyo"

echo "${capital[France]}"  #=> Paris

for country in "${!capital[@]}"; do
  echo "$country: ${capital[$country]}"
done
```

## Dictionaries

```bash
declare -A user
user=(
  [name]="John"
  [email]="john@example.com"
  [role]="admin"
)

echo "${user[name]}"  #=> John
echo "${!user[@]}"    #=> name email role
```

## Case Statement

```bash
read -p "Continue? [y/n] " answer
case $answer in
  y|Y|yes|YES)
    echo "Continuing..."
    ;;
  n|N|no|NO)
    echo "Stopping."
    exit 0
    ;;
  *)
    echo "Invalid input"
    exit 1
    ;;
esac
```

## Options

```bash
# Set options
set -euo pipefail
set -x # debug mode (trace)
set -n           # check syntax without executing

# Check options
set -o            # list all options
set -o pipefail # enable pipefail
```

## History

```bash
history # show history
!! # last command
!$ # last argument
!string # last command starting with string
!?string          # last command containing string
^string^new^      # repeat last command, replacing string
```

```bash
# In a script:
set -o history # enable history (on by default in interactive)
fc -l # list history
fc -s string      # re-execute command starting with string
```

## Test / Conditionals

### String Tests

```bash
[[ -z "$var" ]]      # string is empty
[[ -n "$var" ]]      # string is not empty
[[ "$a" == "$b" ]]   # equal
[[ "$a" != "$b" ]]   # not equal
[[ "$a" =~ regex ]]  # regex match
```

### Numeric Tests

```bash
[[ $a -eq $b ]]    # equal
[[ $a -ne $b ]]    # not equal
[[ $a -lt $b ]]    # less than
[[ $a -le $b ]]    # less than or equal
[[ $a -gt $b ]]    # greater than
[[ $a -ge $b ]]    # greater than or equal
```

### File Tests

```bash
[[ -e file ]]      # exists
[[ -f file ]]      # regular file
[[ -d file ]]      # directory
[[ -L file ]]      # symlink
[[ -r file ]] # readable
[[ -w file ]]       # writable
[[ -x file ]]       # executable
[[ file1 -nt file2 ]]  # file1 is newer than file2
[[ file1 -ot file2 ]]  # file1 is older than file2
[[ -z "$var" ]] # empty
[[ -n "$var" ]]    # not empty
```

### Logical Operators

```bash
[[ ... ]] && ...
[[ ... ]] || ...
[[ ! ... ]]
[[ $a && $b ]]     # AND
[[ $a || $b ]]     # OR
```

## Globbing

```bash
# Files matching pattern:
*.txt
file?.log
/home/*/data/*.csv

# Extended globbing:
shopt -s extglob
echo !(*.txt)      # all files except .txt
echo *(foo|bar)    # zero or more of foo or bar
echo +(foo|bar)    # one or more of foo or bar
echo ?(foo|bar)    # zero or one of foo or bar
echo @(foo|bar)    # exactly one of foo or bar
```

## User Input

```bash
read -p "Enter your name: " name
echo "Hello $name"

# Silent input:
read -sp "Password: " password
echo ""

# Split into array:
read -ra words <<< "one two three"
echo "${words[0]}"  #=> one
```

## Reading Files

```bash
while read -r line; do
  echo "$line"
done < file.txt

# With IFS split:
while IFS= read -r line; do
  echo "$line"
done < file.txt

# Into array:
mapfile -t lines < file.txt
printf '%s\n' "${lines[@]}"
```

## Reading Files with delimiters

```bash
# Read null-delimited (find -print0):
while IFS= read -r -d '' line; do
  echo "$line"
done < <(find . -print0)
```

## Heredocs

```bash
cat <<EOF
Hello $name
Current directory: $(pwd)
EOF
```

```bash
# With indentation (<<- strips tabs):
cat <<-EOF
    Indented content
    EOF
```

```bash
# Quoted heredoc (no variable expansion):
cat <<'EOF'
Hello $name
EOF
```

```bash
# String with heredoc:
message=$(cat <<EOF
This is a multi-line
message with $variable expansion.
EOF
)
```

## Debugging

```bash
# Trace mode:
bash -x script.sh

# In script:
set -x # turn on
set +x             # turn off

# Abort on error:
set -e

# Check syntax:
bash -n script.sh

# With shopt:
shopt -p # list all shell options
shopt -s option # enable option
shopt -u option    # disable option
```

## Arithmetic

```bash
# Integer arithmetic:
$((a + b))
$((a - b))
$((a * b))
$((a / b))
$((a % b))
$((a ** b))   # exponentiation (bash 4+)

# Increment:
((count++))
((count--))

# Compound expressions:
((a > 0 && b > 0))
```

## Random Numbers

```bash
echo $RANDOM              # 0-32767
echo $((RANDOM % 100))    # 0-99
echo $((RANDOM % 100 + 1)) # 1-100
```

## Dates

```bash
date                    # Sat Jun  6 10:00:00 UTC 2025
date +"%Y-%m-%d"       # 2025-06-06
date +"%H:%M:%S"       # 10:00:00
date -d "2025-01-01"   # parse date
date -d "yesterday"    # relative dates
date -d "tomorrow"
date -d "next Monday"
date -d "next week"
date -d "2 days ago"
```

## Exit Codes

```bash
# $? = exit code of last command
# 0 = success, 1-255 = error

[[ $? -eq 0 ]] && echo "success"

# Common codes:
# 0   — success
# 1   — general error
# 2   — misuse / missing arguments
# 126 — command not executable
# 127 — command not found
# 130 — Ctrl+C (SIGINT)
```

## Argument Parsing

```bash
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      echo "Usage: $0 [-h] [-v] [-f FILE]"
      exit 0
      ;;
    -v|--verbose)
      verbose=true
      ;;
    -f|--file)
      file="$2"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done
```

## Pipes and Redirection

```bash
# Redirect stdout and stderr:
cmd > file2>&1
cmd &> file
cmd &>> file     # append

# Redirect stdin:
cmd <<< "input"
cmd < file

# Pipe:
cmd1 | cmd2
cmd1 |& cmd2     # pipe stdout and stderr (bash 4+)

# Here string:
cmd <<< "input string"
```

## Trap (Signal Handling)

```bash
trap 'echo "Caught signal"; exit 1' INT TERM
trap 'cleanup; exit' EXIT

cleanup() {
  rm -f /tmp/tmpfile
}
```

## Quick Reference

```bash
# Common set options:
set -e    # exit on error
set -u    # exit on unset variable
set -o pipefail   # fail on pipeline error
set -x    # trace execution
set -n    # syntax check only

# Parameter expansion:
${var:-default}     # default if unset
${var:=default}     # set default if unset
${var:offset:len}   # substring
${#var}             # length
${var#prefix}       # remove prefix
${var%suffix}       # remove suffix
${var//old/new}     # replace all

# Arrays:
${arr[@]}           # all elements
${!arr[@]}          # all indices
${#arr[@]}          # array length
${arr[@]:1:2}       # slice
```