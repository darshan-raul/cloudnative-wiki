---
title: "Lab CKS-05 — Seccomp, AppArmor & Immutability"
tags: [kubernetes, labs, cks, seccomp, apparmor, securitycontext, immutability]
date: 2026-10-13
description: "Apply the RuntimeDefault and a custom Localhost seccomp profile, load and attach an AppArmor profile, and make a container's filesystem immutable at runtime."
---

# Lab CKS-05 — Seccomp, AppArmor & Immutability

Three kernel-level controls that limit what a compromised container can do: seccomp filters system calls, AppArmor confines file and capability access, and a read-only root filesystem stops an attacker from changing the container at all.

Concepts: [[Kubernetes/concepts/L07-security/02-workload-sandboxing/16-seccomp-apparmor|Seccomp and AppArmor]], [[Linux/security/seccomp|seccomp]], [[Linux/security/apparmor|AppArmor]] and [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context|SecurityContext]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there. The AppArmor section was not run at all; see its warning.

The seccomp and immutability sections were verified on `kind` v0.31 with Kubernetes v1.35.0.

> [!warning] AppArmor section not run on kind
> A `kind` node shares the host kernel and does not expose the AppArmor interface inside the node container, so section 4 was written from the upstream documentation and not executed. Run it on a virtual machine node, such as the cluster from [[Kubernetes/labs/cka/03-kubeadm-cluster-install|Lab CKA-03]].

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- A worker node shell:

```bash
docker exec -it k8s-lab-worker bash
```

```bash
# host
kubectl create namespace sandbox-lab
```

---

## 2. Seccomp: Unconfined, RuntimeDefault, Localhost

### Step 1: See the default

On this cluster a Pod with no seccomp setting runs unconfined. That is the default only while the kubelet's `seccompDefault` option is off; with it on, the same Pod gets `RuntimeDefault`. The check below shows which you have, and the `restricted` Pod Security Standard accepts either `RuntimeDefault` or `Localhost`:

```bash
kubectl -n sandbox-lab run none --image=busybox:1.36 -- sleep 3600
kubectl -n sandbox-lab exec none -- grep Seccomp: /proc/1/status
```

```text
Seccomp:	0
```

`0` means no filter, `2` means a filter is active.

### Step 2: RuntimeDefault

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: runtime-default
  namespace: sandbox-lab
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
```

```bash
kubectl apply -f runtime-default.yaml
kubectl -n sandbox-lab exec runtime-default -- grep Seccomp: /proc/1/status
kubectl -n sandbox-lab exec runtime-default -- unshare -U true
kubectl -n sandbox-lab exec none -- unshare -U true
```

The filter is active (`Seccomp: 2`), and creating a user namespace fails with `Operation not permitted` in the confined Pod while the unconfined one allows it. `RuntimeDefault` is the container runtime's built-in profile and is what the `restricted` Pod Security Standard requires.

### Step 3: A custom Localhost profile

Profiles live under the kubelet's seccomp directory on **each node** that may run the Pod:

```bash
# worker node
mkdir -p /var/lib/kubelet/seccomp/profiles

cat > /var/lib/kubelet/seccomp/profiles/deny-mkdir.json <<'EOF'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    { "names": ["mkdir", "mkdirat"], "action": "SCMP_ACT_ERRNO" }
  ]
}
EOF
```

`localhostProfile` is a path **relative to** `/var/lib/kubelet/seccomp`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: localhost-profile
  namespace: sandbox-lab
spec:
  nodeName: k8s-lab-worker
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/deny-mkdir.json
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
```

```bash
kubectl apply -f localhost-profile.yaml
kubectl -n sandbox-lab exec localhost-profile -- mkdir /tmp/x
kubectl -n sandbox-lab exec none -- mkdir /tmp/x
```

```text
mkdir: can't create directory '/tmp/x': Operation not permitted
```

The profile blocks `mkdir` in the first Pod only. `nodeName` pins the Pod to the node that has the file; in the exam the task tells you which node holds the profile.

This profile allows everything except two calls, which makes the effect easy to see. A real profile does the opposite: `defaultAction: SCMP_ACT_ERRNO` and an explicit allow list.

---

## 3. Immutable Containers

"Ensure immutability of containers at runtime" means the container cannot modify its own filesystem or gain privileges:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: immutable
  namespace: sandbox-lab
spec:
  containers:
    - name: web
      image: nginxinc/nginx-unprivileged:1.28-alpine
      securityContext:
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
```

```bash
kubectl apply -f immutable.yaml
kubectl -n sandbox-lab exec immutable -- touch /etc/x
kubectl -n sandbox-lab exec immutable -- touch /tmp/ok
```

```text
touch: /etc/x: Read-only file system
```

Writing under `/etc` fails and writing under `/tmp` works, because that path is an `emptyDir`. The method for any image is the same: turn on `readOnlyRootFilesystem`, see where the application fails to write, and mount an `emptyDir` on exactly those paths.

Exam tasks on this topic often ask the reverse: given several Pods, find the ones that are **not** immutable and delete them. The markers are a missing `readOnlyRootFilesystem: true`, `privileged: true`, or a writable `hostPath`.

```bash
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.readOnlyRootFilesystem}{"\n"}{end}'
```

---

## 4. AppArmor

Run this section on a node whose kernel exposes AppArmor: `cat /sys/module/apparmor/parameters/enabled` prints `Y` and `aa-status` works.

### Step 1: Load a profile on the node

```bash
# node
cat > /etc/apparmor.d/k8s-deny-write <<'EOF'
#include <tunables/global>

profile k8s-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>

  file,
  deny /** w,
}
EOF

apparmor_parser -q /etc/apparmor.d/k8s-deny-write
aa-status | grep k8s-deny-write
```

`apparmor_parser` loads the profile into the kernel. The name that matters afterwards is the one after the `profile` keyword, not the file name. Like seccomp profiles, an AppArmor profile must be loaded on every node that may run the Pod.

### Step 2: Attach it to a container

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: apparmor
  namespace: sandbox-lab
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        appArmorProfile:
          type: Localhost
          localhostProfile: k8s-deny-write
```

```bash
kubectl apply -f apparmor.yaml
kubectl -n sandbox-lab exec apparmor -- cat /proc/1/attr/current
kubectl -n sandbox-lab exec apparmor -- touch /tmp/x
```

The first command prints `k8s-deny-write (enforce)` and the second is denied.

The `securityContext.appArmorProfile` field was added in Kubernetes 1.30 and became stable in 1.31. Older material uses the annotation `container.apparmor.security.beta.kubernetes.io/<container>: localhost/<profile>`, which you may still meet in existing manifests.

---

## 5. Controlled Failure Scenario: A Profile That Is Not on the Node

Reference a seccomp profile that does not exist:

```bash
kubectl -n sandbox-lab run missing --image=busybox:1.36 --overrides='
{"spec":{"securityContext":{"seccompProfile":{"type":"Localhost","localhostProfile":"profiles/nope.json"}}}}' -- sleep 3600
kubectl -n sandbox-lab get pod missing
kubectl -n sandbox-lab describe pod missing | tail -5
```

The Pod is accepted by the API server and then fails on the node with `CreateContainerError`. The event names the path the kubelet looked for. The API server cannot validate a node-local file, so this class of mistake only shows up at runtime.

Three causes to check, in order: the file is on a different node than the Pod, the path is not relative to `/var/lib/kubelet/seccomp`, or the JSON is invalid.

---

## 6. Cleanup

```bash
# host
kubectl delete namespace sandbox-lab
```

```bash
# worker node
rm -rf /var/lib/kubelet/seccomp/profiles
```

---

## Further reading

- [Restrict a container's syscalls with seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [Restrict a container's access to resources with AppArmor](https://kubernetes.io/docs/tutorials/security/apparmor/)
- [Configure a security context for a Pod or container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/06-falco-runtime-detection|Lab CKS-06 — Falco Runtime Detection]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
