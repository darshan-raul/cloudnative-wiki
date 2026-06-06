---
title: Here-Docs and Here-Strings
description: Linux here-docs and here-strings — <<, <<<, inline text in shell scripts, heredoc delimiters, quoting
tags:
  - linux
  - shell
---

# Here-Docs and Here-Strings

Here-docs and here-strings let you embed inline text in a shell script without external files. They're ideal for config files, multi-line strings, and feeding data to commands.

## Here-Doc (`<<`)

```bash
# Basic: feed multiple lines to a command
cat << 'EOF'
This is line 1
This is line 2
Variable: $HOME
EOF

# Output:
# This is line 1
# This is line 2
# Variable: /home/darshan
```

The delimiter (`EOF` above) marks the end. The shell reads everything between `<<EOF` and a line containing only `EOF`.

## Delimiter quoting

```bash
# 'EOF' — single quotes = no expansion
cat << 'EOF'
$HOME is $HOME
$(date) is $(date)
EOF
# Output:
# $HOME is $HOME
# $(date) is $(date)

# Unquoted EOF = expansions happen
cat << EOF
$HOME is $HOME
$(date) is $(date)
EOF
# Output:
# /home/darshan is /home/darshan
# Mon Jun  6 12:00:00 UTC 2025 is Mon Jun  6 12:00:00 UTC 2025

# Double quotes work too
cat << "EOF"
$HOME is literal
EOF
```

## Leading Tab Stripping

```bash
# - with <<- (dash): leading tabs are stripped from each line
# This lets you indent your here-doc inside a script:
cat <<- 'EOF'
	line one (leading tab stripped)
	line two
	EOF

# Note: only TABs are stripped, not spaces
```

## Practical Use: Config Files

```bash
# Generate nginx config inline
cat > /tmp/nginx.conf << 'CONF'
server {
    listen 80;
    server_name example.com;
    root /var/www/html;

    location / {
        try_files $uri $uri/ =404;
    }
}
CONF

# Use it
nginx -t -c /tmp/nginx.conf
```

## Multiple Here-Docs in Sequence

```bash
cat << 'EOF1'
Config file 1
EOF1

cat << 'EOF2'
Config file 2
EOF2
```

## Here-Strings (`<<<`)

Here-strings feed a **single string** (not multi-line) to stdin:

```bash
# Feed string to a command
grep pattern <<< "some text with pattern in it"
# Equivalent to: echo "some text..." | grep pattern

# Read into variable
read -r line <<< "hello world"
echo "$line"   # hello world

# Word splitting happens (like unquoted):
read -r a b c <<< "one two three"
echo "$a $b $c"   # one two three

# No word splitting (quoted):
read -r line <<< "hello    world"
echo "$line"   # hello    world (preserved)

# Common: bc arithmetic
bc <<< "2^10"
# 1024

# Read with IFS:
while IFS=: read -r user pass uid; do
    echo "$user has UID $uid"
done <<< "$(cat /etc/passwd)"
```

## Combining Here-Doc with Commands

```bash
# Feed here-doc to a running command
docker exec -i container_name bash << 'EOF'
ps aux | grep nginx
cat /etc/nginx/nginx.conf
EOF

# SSH with inline script
ssh server << 'EOF'
hostname
uptime
df -h
EOF

# mysql
mysql -u root -p << 'EOSQL'
USE mydb;
SELECT * FROM users WHERE active=1;
EOSQL
```

## Here-Doc with Variable Expansion

```bash
# Set variables inside the script for use in here-doc
SERVER="web-01"
PORT=8080

# Use cat to write a script that contains the values
cat > /tmp/start.sh << EOF
#!/bin/bash
SERVER=$SERVER
PORT=$PORT
echo "Starting \$SERVER on port \$PORT"
EOF

bash /tmp/start.sh
# Starting web-01 on port 8080
```

## Security: Watch for Expansion

```bash
# Dangerous: user input in here-doc can cause expansion
# If user input contains $(cmd) or $var, it gets executed:
read -r user_input << EOF
$user_input    # if user types $(rm -rf /), it executes!
EOF

# Safer: quote the delimiter
read -r user_input << 'EOF'
$user_input    # literal $user_input
EOF
```

## Common Patterns

### Generate SQL

```bash
psql -u postgres << 'EOSQL'
CREATE DATABASE myapp;
\\c myapp
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100)
);
\q
EOSQL
```

### Inline CSS/HTML

```bash
cat << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>Report</title></head>
<body>
<h1>System Report for $(hostname)</h1>
<pre>$(uptime)</pre>
</body>
</html>
HTMLEOF
```

### Multi-line Variable

```bash
# Store here-doc in a variable (no trailing newline issue)
read -r -d '' VAR << 'EOF'
Line 1
Line 2
Line 3
EOF

# Or:
VAR=$(cat << 'EOF'
Line 1
Line 2
Line 3
EOF
)
# Note: command substitution strips trailing newlines
```

## Testing

```bash
# Quick test with cat
cat << 'TEST'
hello world
TEST

# Output:
# hello world
```