---
title: "02 — File Permissions"
description: Linux file permissions — rwx, chmod, chown, chgrp, umask, sticky bit, setuid, setgid, ACLs
tags:
  - linux
  - concepts
---

# 02 — File Permissions

Every file and directory in Linux has three things: an owner, a group, and a set of permissions. Understanding this is fundamental to everything else.

## Reading Permissions

```bash
ls -la /etc/passwd
# -rw-r--r-- 1 root root  1234 Jun  6 10:00 /etc/passwd
# │││││││││
# ││││││││└─ other: read
# │││││││└── other: write
# ││││││└─── other: execute
# │││││└──── group: read
# ││││└───── group: write
# │││└────── group: execute
# ││└─────── owner: read
# │└──────── owner: write
# └────────── owner: execute
# ─────────── file type (- = file, d = directory, l = symlink)
```

The 10-character string breaks down as:

```
[type][owner][group][other]
 d   rwx   rwx   rwx
```

### Permission Values

```
r (read)    = 4
w (write)   = 2
x (execute) = 1
```

You can combine them:

```
7 = rwx  = read + write + execute
6 = rw-  = read + write
5 = r-x  = read + execute
4 = r--  = read only
3 = -wx  = write + execute
2 = -w-  = write only
1 = --x  = execute only
0 = ---  = nothing
```

So `chmod 755 file` means: owner gets rwx (7), group gets r-x (5), other gets r-x (5).

## chmod — Change Permissions

```bash
# Numeric (preferred for scripts):
chmod 644 file         # rw-r--r-- : owner rw, group ro, other ro
chmod 755 script.sh    # rwxr-xr-x : owner rwx, group rx, other rx
chmod 600 id_rsa       # rw------- : owner rw only (SSH keys)
chmod 700 .ssh/        # rwx------ : owner rwx only (SSH dir — must be!)
chmod 644 /etc/passwd  # world-readable (system file)

# Symbolic (easier to read):
chmod u+x script.sh    # add execute for owner
chmod g-x file         # remove execute from group
chmod o+r file         # add read for other
chmod a+x script.sh   # add execute for all (a = all)
chmod u=rw,go=r file   # owner rw, group/other ro
chmod +x script.sh     # add execute for all (shorthand)
```

## chown — Change Owner

```bash
chown user file                    # change owner
chown user:group file             # change owner and group
chown :group file                 # change group only
chown -R user:group dir/          # recursive
chown --reference=otherfile file  # copy ownership from another file
```

## chgrp — Change Group

```bash
chgrp group file          # change group
chgrp -R group dir/      # recursive
```

## Common Permission Patterns

```bash
# Standard file:
chmod 644 file           # rw-r--r--

# Script (needs to execute):
chmod 755 script.sh      # rwxr-xr-x

# SSH private key (must be owner-only):
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# SSH directory (must be owner-only to work):
chmod 700 ~/.ssh

# Web directory (apache/nginx need to read):
chmod 755 /var/www/html
chown -R www-data:www-data /var/www/html

# Log file (service needs to write, you need to read):
chmod 644 /var/log/nginx/access.log
chown root:adm /var/log/nginx/access.log  # 'adm' group can read logs

# Database files (mysql/postgres restrict to their user):
chmod 700 /var/lib/mysql
chown -R mysql:mysql /var/lib/mysql
```

## Special Permissions

### Sticky Bit

On a directory, the sticky bit means only the owner of a file (or root) can delete or rename it — even if others have write permission. `/tmp` has this by default.

```bash
ls -la / | grep tmp
# drwxrwxrwt  11 root root  4096 Jun  6 10:00 /tmp
#                                       └─ t = sticky bit set

# What this prevents:
# User A creates /tmp/file.txt
# User B cannot delete /tmp/file.txt (even though /tmp is drwxrwxrwt)
# Only root or user A can delete it

chmod +t /tmp/myapp-temp/
chmod 1777 /tmp/myapp-temp/   # same as 777 + sticky bit
```

### Setuid (suid)

When a file with suid runs, it runs as the **file's owner**, not the calling user. Used for `passwd` — you need root to write `/etc/shadow`, but users run `passwd` as themselves.

```bash
ls -la /usr/bin/passwd
# -rwsr-xr-x 1 root root  27768 ... /usr/bin/passwd
#    └─ s = setuid bit is set (execute bit shows as 's')

chmod u+s /path/to/file    # set suid
chmod 4755 /path/to/file   # 4 = suid, 755 = permissions

# To check: does this file have suid?
find /usr/bin -perm /4000   # all suid binaries
```

### Setgid (sgid)

On a file: runs as the file's **group**. On a directory: new files inherit the directory's group.

```bash
# File with sgid:
chmod g+s /path/to/file
chmod 2755 /path/to/file   # 2 = sgid

# Directory with sgid (common for shared group directories):
# Any file created in this dir gets the dir's group:
chgrp developers /shared/project
chmod 2775 /shared/project  # developers can write, files get 'developers' group
```

## umask — Default Permissions for New Files

When you create a file, Linux starts with `666` (rw-rw-rw-) for files or `777` (rwxrwxrwx) for directories, then subtracts the umask.

```bash
# Default umask (varies by distro):
umask
# 0022  →  666 - 022 = 644 (rw-r--r--) for files
# 0002  →  666 - 002 = 664 (rw-rw-r--) for files (common for users in same group)

# Set a different umask for your session:
umask 027    # files get 640, dirs get 750 (good for security)

# Make it permanent:
# ~/.bashrc or /etc/profile or /etc/bash.bashrc
echo "umask 027" >> ~/.bashrc
```

## ACLs — Access Control Lists

For more granular permissions than owner/group/other, use ACLs.

```bash
# Check if a file has ACLs:
getfacl file

# Set an ACL (give user 'alice' read+write):
setfacl -m u:alice:rw file

# Give group 'developers' read access:
setfacl -m g:developers:r directory/

# Remove ACL:
setfacl -x u:alice file

# Copy ACLs from one file to another:
getfacl file1 | setfacl --set-file=- file2

# Default ACL on a directory (new files inherit it):
setfacl -m d:u:alice:rwx /shared/project
```

## Troubleshooting Permissions

```bash
# Why can't I write here?
ls -la /path/to/file
# Check: are you the owner? Are you in the group? Does group/other have 'x' on all parent dirs?

# 'Permission denied' even with 777?
lsattr /path/to/file   # check for immutable flag
# If 'i' is set: chattr -i /path/to/file

# Can't execute script even with chmod +x?
# Check the shebang line and file encoding:
file script.sh
head -1 script.sh   # must start with #!

# SSH key won't work?
# MUST be 600 for private key, 644 for public
chmod 600 ~/.ssh/id_rsa
# Also check ~/.ssh/ is 700
```

## Quick Reference

```bash
# Read perms
ls -la file

# Change perms
chmod 644 file         # numeric
chmod u+x file         # add execute for owner
chmod -x file          # remove execute for all

# Change owner/group
chown user:group file
chgrp group file

# Special bits
chmod +t /dir/         # sticky bit
chmod +s /path/to/file # setuid
chmod +s /path/to/file # setgid

# Check suid files
find /usr/bin -perm /4000

# ACLs
getfacl file
setfacl -m u:alice:rw file

# umask
umask                  # show current
umask 027              # set for session
```