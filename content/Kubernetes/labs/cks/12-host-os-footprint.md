---
title: "Lab CKS-12 — Host OS Footprint"
tags: [kubernetes, labs, cks, node-hardening, linux, systemd, attack-surface]
date: 2026-10-13
description: "Find an unneeded service listening on a node, trace the port to its process and package, remove it, and block a kernel module from loading."
---

# Lab CKS-12 — Host OS Footprint

A node should run the kubelet, a container runtime and little else. Every extra service, package and loadable kernel module is something an attacker can use. The System Hardening tasks in the CKS are plain Linux administration on a node: find what should not be there and remove it.

Concepts: [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening|Node Hardening]], [[Linux/security/linux-cis-hardening|Linux CIS Hardening]], [[Linux/networking/ss|ss]] and [[Linux/boot-init/systemd|systemd]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there.

Verified on a `kind` v0.31 node (Debian 12). Exam nodes are Ubuntu, where the same commands apply.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- A worker node shell:

```bash
docker exec -it k8s-lab-worker bash
```

Plant something to find. This installs and starts an FTP server, the kind of leftover a task asks you to remove:

```bash
# node
apt-get update && apt-get install -y vsftpd
systemctl enable --now vsftpd
```

---

## 2. See What Is Listening

```bash
# node
ss -tlnp
```

| Flag | Meaning                        |
| :--- | :----------------------------- |
| `-t` | TCP (`-u` for UDP)             |
| `-l` | Listening sockets only         |
| `-n` | Numeric ports, no name lookups |
| `-p` | Show the owning process        |

```text
State   Recv-Q  Send-Q  Local Address:Port  Peer Address:Port  Process
LISTEN  0       32                  *:21               *:*      users:(("vsftpd",pid=2891,fd=3))
LISTEN  0       4096                *:10250            *:*      users:(("kubelet",...))
LISTEN  0       4096                *:10256            *:*      users:(("kube-proxy",...))
```

Know what belongs on a worker so the outlier stands out:

| Port         | Process        | Expected on a worker           |
| :----------- | :------------- | :----------------------------- |
| 10250        | kubelet        | Yes, the kubelet API           |
| 10248        | kubelet        | Yes, health check on localhost |
| 10256, 10249 | kube-proxy     | Yes                            |
| 6443         | kube-apiserver | Control plane nodes only       |
| 2379, 2380   | etcd           | Control plane nodes only       |
| 21           | vsftpd         | No                             |

A socket bound to `127.0.0.1` is reachable only from the node. One bound to `*` or `0.0.0.0` is reachable from the network, and is the one to question first.

---

## 3. Trace a Port to Its Process and Package

```bash
# node
ss -tlnp 'sport = :21'
PID=$(ss -tlnpH 'sport = :21' | sed 's/.*pid=\([0-9]*\).*/\1/')
ps -o user=,cmd= -p $PID
readlink /proc/$PID/exe
dpkg -S $(readlink /proc/$PID/exe)
systemctl status vsftpd --no-pager | head -4
```

```text
root     /usr/sbin/vsftpd /etc/vsftpd.conf
/usr/sbin/vsftpd
vsftpd: /usr/sbin/vsftpd
```

The chain is port, process ID, binary, package, service unit. `/proc/<pid>/exe` gives the real binary even when the process name is misleading, and `dpkg -S` names the package that owns it.

---

## 4. Remove It

```bash
# node
systemctl disable --now vsftpd
apt-get purge -y vsftpd
ss -tlnH 'sport = :21' | wc -l
```

`disable --now` stops the service and prevents it from starting at boot. Stopping alone is not enough, because the service returns on the next reboot. Purging the package removes the binary, so the service cannot simply be started again.

Read the task wording: "stop and disable" and "remove the package" are different amounts of work, and doing only the first when the second was asked loses the points.

Review what else is running:

```bash
# node
systemctl list-units --type=service --state=running
systemctl list-unit-files --type=service --state=enabled
```

---

## 5. Block a Kernel Module

Containers share the node's kernel, so a vulnerable module that can be loaded on demand is reachable from any container allowed to trigger it. Modules that are not needed are blocked from loading:

```bash
# node
cat > /etc/modprobe.d/k8s-hardening.conf <<'EOF'
blacklist dccp
install dccp /bin/false
EOF

modprobe dccp; echo "exit=$?"
lsmod | grep -c '^dccp'
```

```text
modprobe: ERROR: ... Error running install command '/bin/false' for module dccp: retcode 1
exit=1
0
```

The two lines do different jobs. `blacklist` stops the module from being loaded automatically by an alias. `install dccp /bin/false` replaces the load command itself, so an explicit `modprobe dccp` fails too. A blacklist entry alone does not stop a manual load.

The file changes future loads only. A module that is already loaded stays until `modprobe -r <module>` or a reboot.

> [!warning] Shared kernel on kind
> A `kind` node shares your machine's kernel, so a module loaded or removed inside the node is loaded or removed on your host. This lab only ever makes a load **fail**. Do not experiment with `modprobe` or `modprobe -r` on real modules from inside a `kind` node.

---

## 6. Users and Privileged Binaries

Two more checks a footprint task may ask for:

```bash
# node
awk -F: '$3==0 {print $1}' /etc/passwd
find / -xdev -perm -4000 -type f 2>/dev/null
```

The first lists every account with UID 0; only `root` should appear. The second lists setuid binaries, which run as their owner whoever starts them. An unexpected entry in either list is a finding. [[Linux/security/capabilities|Linux Capabilities]] explains the finer-grained alternative to setuid.

On a node with SSH, the usual settings to confirm in `/etc/ssh/sshd_config` are `PermitRootLogin no` and `PasswordAuthentication no`, followed by `systemctl restart ssh`.

---

## 7. Controlled Failure Scenario: Removing the Wrong Thing

Make the node look as if it has a suspicious listener on a high port, then decide what to do about it:

```bash
# node
ss -tlnp | grep -E '10250|10256'
```

Port `10250` is open to the network and belongs to the kubelet. A candidate working through a list of "unnecessary open ports" who stops it takes the node out of the cluster:

```bash
# node
systemctl stop kubelet
```

```bash
# host
kubectl get nodes -w
```

After about 45 seconds the worker becomes `NotReady`. Restore it:

```bash
# node
systemctl start kubelet
```

Identify a process before acting on its port. On a node, the kubelet, the container runtime, `kube-proxy` and the CNI agent all listen legitimately, and the table in section 2 is the baseline to compare against.

---

## 8. Cleanup

```bash
# node
rm -f /etc/modprobe.d/k8s-hardening.conf
```

---

## Further reading

- [Securing a cluster](https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/)
- [Ports and protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)

## Next Lab

This is the last CKS lab so far. Return to the [[Kubernetes/certifications/cks|CKS Track]] for the objectives that still have no lab.
