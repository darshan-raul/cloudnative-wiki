---
title: Linux CIS Hardening
description: CIS Linux hardening — kernel parameters, GRUB cmdline, sysctl, filesystem mounts, module disabling, user limits, audit rules, service management
tags:
  - linux
  - security
  - cis
---

# Linux CIS Hardening

CIS (Center for Internet Security) benchmarks provide security checklists for Linux distros. This note covers the kernel-level hardening that applies across most distros — sysctl parameters, GRUB boot params, module disabling, and system settings.

## GRUB Boot Parameters

GRUB parameters are set in `/etc/default/grub` and affect the kernel at boot time. These are foundational — they can't be changed at runtime.

```bash
# Edit GRUB config:
# /etc/default/grub
GRUB_CMDLINE_LINUX="..."

# Then regenerate:
grub-mkconfig -o /boot/grub/grub.cfg       # Debian/Ubuntu
grub2-mkconfig -o /boot/grub2/grub.cfg     # RHEL/Fedora
```

### Essential GRUB Hardening Params

```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX="\
  audit=1 \
  audit_backlog_limit=8192 \
  apparmor=1 \
  security=apparmor \
  page_poison=1 \
  slab_nomerge \
  slub_debug=P \
  mce=0 \
  mce=0 \
  processor.max_cstate=1 \
  intel_idle.max_cstate=1 \
  pcie_aspm=off \
  preempt=1 \
  mitigations=auto \
  module.sig_unmet=0 \
  consoleblank=0 \
  "
```

Key params explained:

| Parameter | Purpose |
|-----------|---------|
| `audit=1` | Enable audit logging at boot |
| `page_poison=1` | Fill freed pages with poison bytes (detect heap corruption) |
| `slab_nomerge` | Don't merge slabs (makes alloc bugs more visible) |
| `slub_debug=P` | Enable slub debugging (detect use-after-free) |
| `mce=0` | Disable Machine Check Exception (set to 0 if not needed) |
| `mitigations=auto` | Enable CPU mitigations (Spectre/Meltdown) |
| `consoleblank=0` | Disable console blanking |

### Disable unused filesystems at boot

```bash
# Prevent mounting of uncommon filesystems (CIS requirement)
# Add to GRUB:
GRUB_CMDLINE_LINUX="... \
  disable_numeric_owneroffset_check=1 \
  "

# Create /etc/modprobe.d/ to blacklist filesystems:
# /etc/modprobe.d/cis-filesystems.conf
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
install vfat /bin/true   # if not needed
```

## sysctl Kernel Parameters

Apply via `/etc/sysctl.conf` or `/etc/sysctl.d/*.conf`. Changes apply immediately with `sysctl -p`.

### Network Hardening

```bash
# /etc/sysctl.conf
# Network hardening

# --- IP forwarding (should be off on workstations) ---
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0

# --- ICMP redirects (disable) ---
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv5.conf.all.send_redirects=0

# --- Source packet routing (disable) ---
net.ipv4.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0

# --- ARP flux (prevent ARP cache poisoning across interfaces) ---
net.ipv4.conf.all.arp_announce=2
net.ipv4.conf.all.arp_ignore=1

# --- IP masquerading (disable unless needed) ---
net.ipv4.conf.all.masquerade=0

# --- ICMP echo ignore (enable on internet-facing) ---
net.ipv4.icmp_echo_ignore_all=0          # keep enabled for ping
net.ipv4.icmp_echo_ignore_broadcasts=1   # ignore broadcast ping

# --- TCP SYN cookies (enable to prevent SYN flood) ---
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=8096
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_syn_retries=2

# --- IPsec (enable if using IPsec) ---
net.ipv4.conf.all.esp_encrypt_attr_transition=1

# --- Log martians (log suspicious packets) ---
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1

# --- RP filter (enable reverse path filtering) ---
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1

# --- Disable IPv6 if not needed ---
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
```

### Memory & Kernel Hardening

```bash
# /etc/sysctl.conf

# --- Kernel hardening ---
kernel.dmesg_restrict=1          # only root can read kernel messages
kernel.kptr_restrict=2           # hide kernel pointers (2 = hide from everyone)
kernel.yama.ptrace_scope=1        # restrict ptrace (1 = only parent processes)
kernel.modules_disabled=0         # set to 1 AFTER loading required modules

# --- PID max (increase from default 32768) ---
kernel.pid_max=65536

# --- Core dumps ---
kernel.core_pattern=|/bin/false   # disable core dumps
kernel.core_uses_pid=1
fs.suid_dumpable=0                # don't dump SUID binaries

# --- Randomize memory layout (ASLR) ---
kernel.randomize_va_space=2       # 0=off, 1=stack, 2=all (CIS: 2)

# --- Sysrq (disable risky sysrq commands) ---
kernel.sysrq=0                    # CIS: disable for production
# Values: 0=disable all, 1=enable all, 0xf=enable subset

# --- Perf (disable if not needed for debugging) ---
kernel.perf_event_paranoid=2      # 2 = disable perf for unprivileged users

# --- BPF (restrict) ---
kernel.bpf_stats_enabled=0        # hide BPF stats
```

### User/Process Limits

```bash
# --- Resource limits ---
kernel.msgmnb=65536               # max bytes in single message queue
kernel.msgmni=32000               # max message queues
kernel.shmmni=4096                # max shared memory segments
kernel.shmmax=68719476736         # max shared memory size (64GB)
kernel.shmall=4294967296          # total shared memory pages

# --- File descriptors ---
fs.file-max=2097152               # system-wide max file handles

# --- Inotify ---
fs.inotify.max_user_watches=524288  # max inotify watches per user
fs.inotify.max_user_instances=1024  # max inotify instances per user
```

## Account Security

```bash
# /etc/login.defs — password aging defaults
PASS_MAX_DAYS 90
PASS_MIN_DAYS 7
PASS_WARN_AGE 14
PASS_MIN_LEN 12

# /etc/default/useradd
INACTIVE=30    # lock account 30 days after password expires

# Restrict root login to specific TTY (CIS)
# /etc/securetty — list of TTYs root can login on
# For serial console only:
# ttyS0
# For console only (no remote root):
# tty1
# tty2

# Disable ctrl-alt-del (CIS)
# RHEL/CentOS:
ln -s /dev/null /etc/systemd/system/ctrl-alt-del.target
# Ubuntu:
systemctl mask ctrl-alt-del.target
```

## Password Quality (pam_pwquality)

```bash
# /etc/security/pwquality.conf
minlen = 14
dcredit = -1          # at least 1 digit
ucredit = -1          # at least 1 uppercase
lcredit = -1          # at least 1 lowercase
ocredit = -1          # at least 1 special char
maxrepeat = 2         # max same consecutive chars
maxclassrepeat = 4    # max chars from same class consecutively
gecoscheck = 1        # check against GECOS fields
dictcheck = 1         # check against cracklib
reject_username = 1   # reject if password contains username
enforce_for_root = 1  # enforce for root too
```

## Disable Unused Services

```bash
# List all enabled services
systemctl list-unit-files --state=enabled

# Common services to disable on servers (if not needed):
systemctl disable --now cups.socket cups.path cups.service    # printer
systemctl disable --now avahi-daemon                          # multicast DNS
systemctl disable --now rpcbind.socket rpcbind.service        # RPC portmapper
systemctl disable --now xinetd                               # superdaemon (legacy)
systemctl disable --now tftp.socket tftp.service             # trivial FTP
systemctl disable --now telnet.socket telnet.service         # telnet (unencrypted)
systemctl disable --now rsh.socket rsh.service               # rsh (unencrypted)
systemctl disable --now rlogin.socket rlogin.service         # rlogin (unencrypted)

# Network file systems:
systemctl disable --now nfs-client.target nfs-utils          # NFS
systemctl disable --now autofs                                # automount

# Radio/discovery services:
systemctl disable --now bluetooth.service hciuart            # bluetooth
systemctl disable --now wpa_supplicant                       # wifi (on servers)
```

## Audit Rules (CIS)

```bash
# /etc/audit/rules.d/cis-hardening.rules

# Monitor account modifications
-w /etc/passwd -p wa -k passwd_modifications
-w /etc/shadow -p wa -k shadow_modifications
-w /etc/group -p wa -k group_modifications
-w /etc/gshadow -p wa -k gshadow_modifications
-w /etc/sudoers -p wa -k sudoers_modifications
-w /etc/sudoers.d/ -p wa -k sudoers_dir_modifications

# Monitor cron and at
-w /etc/cron.allow -p wa -k cron_allow
-w /etc/cron.d/ -p wa -k cron_config
-w /etc/at.allow -p wa -k at_allow
-w /var/spool/cron/ -p wa -k cron_spool

# Monitor network configuration
-w /etc/sysconfig/network -p wa -k network_modifications
-w /etc/sysconfig/network-scripts/ -p wa -k network_scripts

# Monitor module loading
-w /sbin/modprobe -p x -k module_load
-w /sbin/insmod -p x -k module_load

# Monitor privilege escalation
-w /usr/bin/sudo -p x -k sudo_exec
-w /usr/bin/su -p x -k su_exec

# Monitor SSH access
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes
```

## Filesystem Mount Options

```bash
# /etc/fstab — add nosuid, nodev, noexec to mount options where appropriate

# /tmp
tmpfs  /tmp  tmpfs  defaults,nosuid,noexec,nodev,mode=1777  0 0

# /var/tmp (often symlinked to /tmp)
tmpfs  /var/tmp  tmpfs  defaults,nosuid,noexec,nodev,mode=1777  0 0

# /var/log (if separate partition)
# /dev/sda3  /var/log  ext4  defaults,nosuid,noexec,nodev  0 0

# /home (if separate partition)
# /dev/sda4  /home  ext4  defaults,nosuid,nodev  0 0

# CD/DVD (prevent execution from media)
/dev/cdrom  /media/cdrom  iso9660  ro,noexec,nosuid,nodev  0 0
```

## SSH Hardening

```bash
# /etc/ssh/sshd_config — CIS SSH hardening

# Protocol and keys
Protocol 2

# Authentication
PermitRootLogin no
PermitEmptyPasswords no
PasswordAuthentication no              # use keys only
PubkeyAuthentication yes
MaxAuthTries 3
MaxSessions 10

# Disable dangerous features
HostbasedAuthentication no
IgnoreRhosts yes
PermitUserEnvironment no
AllowAgentForwarding no               # if not needed
AllowTcpForwarding no                 # if not needed
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes

# Timeout
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Ciphers and MACs
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,ecdh-sha2-nistp521

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server -f AUTHPRIV -l INFO
```

## Applying Changes

```bash
# Apply sysctl immediately:
sysctl -p
sysctl -p /etc/sysctl.d/99-cis-hardening.conf

# Verify changes:
sysctl net.ipv4.tcp_syncookies
sysctl kernel.randomize_va_space
sysctl kernel.dmesg_restrict

# Check GRUB:
grep -E "audit=|slab_nomerge|page_poison" /proc/cmdline
# Or:
cat /proc/cmdline

# Audit rules:
auditctl -l

# Check if IPv6 is disabled:
cat /proc/sys/net/ipv6/conf/all/disable_ipv6
```

## Verification

```bash
# Run CIS benchmark tool (if available):
# For Ubuntu:
apt install bzt
bzt /usr/share/bzt/ubuntu-cis-benchmark.yaml

# For RHEL:
yum install oscap
oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_cis /usr/share/xml/scap/ssg/rhel8/ssg-rhel8-ds.xml

# Quick manual checks:
# 1. Root login disabled on TTYs
grep "tty" /etc/securetty 2>/dev/null | wc -l  # should be minimal
# 2. Core dumps disabled
ulimit -c   # should be 0
# 3. ASLR
cat /proc/sys/kernel/randomize_va_space  # should be 2
# 4. Sysrq
cat /proc/sys/kernel/sysrq  # should be 0 on production
# 5. ICMP redirects
cat /proc/sys/net/ipv4/conf/all/accept_redirects  # should be 0
# 6. Source routing
cat /proc/sys/net/ipv4/conf/all/accept_source_route  # should be 0
```