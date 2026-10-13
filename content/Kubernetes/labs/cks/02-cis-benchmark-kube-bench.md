---
title: "Lab CKS-02 — CIS Benchmark with kube-bench"
tags: [kubernetes, labs, cks, cis, kube-bench, hardening]
date: 2026-10-13
description: "Run kube-bench against the control plane and a worker, read the failed CIS checks, remediate them in the static Pod manifests and kubelet files, and rerun to confirm."
---

# Lab CKS-02 — CIS Benchmark with kube-bench

The CIS Kubernetes Benchmark is a long checklist of component settings. `kube-bench` runs that checklist against a node and prints, for every failed check, the exact remediation. A CKS task typically says "fix the following findings", so the skill is reading the output and editing the right file.

Concepts: [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/22-compliance-frameworks|Compliance Frameworks]], [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/20-cluster-hardening|Cluster Hardening]] and [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening|Node Hardening]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there.

Verified on `kind` v0.31 with Kubernetes v1.35.0.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- Node shells and a backup of the manifests:

```bash
docker exec -it k8s-lab-control-plane bash
# control plane node
mkdir -p /root/backup/cks-02 && cp /etc/kubernetes/manifests/*.yaml /root/backup/cks-02/
```

In the exam `kube-bench` is installed on the node and you run it directly, for example `kube-bench run --targets master`. Here it runs as a Job, which produces the same report.

---

## 2. Run the Benchmark

```bash
curl -fsSLO https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-master.yaml
curl -fsSLO https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-node.yaml
kubectl apply -f job-master.yaml -f job-node.yaml
kubectl wait --for=condition=complete job/kube-bench-master job/kube-bench-node --timeout=180s

kubectl logs job/kube-bench-master > master.txt
kubectl logs job/kube-bench-node > node.txt
```

The Jobs mount the host's `/etc/kubernetes`, `/var/lib/kubelet` and process list, which is how they see the real configuration.

| Target         | Sections | Covers                                                         |
| :------------- | :------- | :------------------------------------------------------------- |
| `master`       | 1.x      | Control plane files, API server, controller manager, scheduler |
| `etcd`         | 2.x      | etcd flags                                                     |
| `controlplane` | 3.x      | Authentication and audit configuration                         |
| `node`         | 4.x      | Kubelet files and configuration                                |
| `policies`     | 5.x      | RBAC, Pod security, NetworkPolicy (manual checks)              |

---

## 3. Read the Report

```bash
grep -E '^\[FAIL\]' master.txt
grep -A4 '== Summary total' master.txt
```

```text
[FAIL] 1.2.15 Ensure that the --profiling argument is set to false (Automated)
[FAIL] 1.3.2 Ensure that the --profiling argument is set to false (Automated)
[FAIL] 1.4.1 Ensure that the --profiling argument is set to false (Automated)
...
```

Every check has a matching remediation further down the report. Look one up by its number:

```bash
grep -A4 '^1.2.15 ' master.txt
```

```text
1.2.15 Edit the API server pod specification file /etc/kubernetes/manifests/kube-apiserver.yaml
on the control plane node and set the below parameter.
--profiling=false
```

Four statuses appear: `PASS`, `FAIL`, `WARN` for checks a human must judge, and `INFO`. Exam tasks name the check numbers to fix, so do not try to clear the whole list.

---

## 4. Remediate Control Plane Findings

Checks 1.2.15, 1.3.2 and 1.4.1 are the same setting on three components. Add the flag to the `command` list of each static Pod manifest:

```yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --profiling=false
```

```bash
# control plane node
for c in kube-apiserver kube-controller-manager kube-scheduler; do
  sed -i "s#^    - $c\$#    - $c\n    - --profiling=false#" /etc/kubernetes/manifests/$c.yaml
done
grep -c profiling /etc/kubernetes/manifests/*.yaml
watch crictl ps
```

The kubelet restarts each component when its manifest changes. Wait for all three to be `Running` again and for `kubectl get nodes` to answer before going on.

---

## 5. Remediate Node Findings

```bash
grep -E '^\[FAIL\]' node.txt
grep -A3 '^4.1.9 ' node.txt
```

File permission findings are fixed on the node the Job ran on, which `kubectl get pod -l job-name=kube-bench-node -o wide` shows:

```bash
docker exec -it k8s-lab-worker bash
# worker node
chmod 600 /var/lib/kubelet/config.yaml
```

Kubelet settings live in `/var/lib/kubelet/config.yaml` and need a kubelet restart to apply. The three every CKS candidate should recognise are already correct on a `kubeadm` cluster; confirm them:

```bash
# worker node
grep -A3 -E '^authentication|^authorization' /var/lib/kubelet/config.yaml
```

```yaml
authentication:
  anonymous:
    enabled: false # 4.2.1
authorization:
  mode: Webhook # 4.2.2, must not be AlwaysAllow
```

A task may hand you a node where one of these was weakened. Set it back, then `systemctl restart kubelet`.

---

## 6. Verification

```bash
kubectl delete job kube-bench-master kube-bench-node
kubectl apply -f job-master.yaml -f job-node.yaml
kubectl wait --for=condition=complete job/kube-bench-master job/kube-bench-node --timeout=180s
kubectl logs job/kube-bench-master | grep -E '^\[FAIL\]'
kubectl logs job/kube-bench-master | grep -A4 '== Summary total'
```

The three profiling checks are gone and the `FAIL` count has dropped by three.

Some failures remain on `kind` and are not worth chasing, because they describe how `kind` builds its nodes: 1.1.2 (manifest ownership) and 1.1.12 (etcd data directory ownership).

---

## 7. Controlled Failure Scenario: A Remediation That Takes Down the API Server

Apply a finding without thinking about its dependencies. Check 1.2.5 wants `--kubelet-certificate-authority` set. Point it at a file that does not exist:

```bash
# control plane node
sed -i 's#^    - kube-apiserver$#    - kube-apiserver\n    - --kubelet-certificate-authority=/etc/kubernetes/pki/kubelet-ca.crt#' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

Within a minute `kubectl` stops answering. Diagnose it the way [[Kubernetes/labs/cka/07-control-plane-and-kubelet-repair|Lab CKA-07]] teaches:

```bash
# control plane node
crictl ps -a --name kube-apiserver
crictl logs --tail 5 $(crictl ps -a -q --name kube-apiserver | head -1)
```

The log names the missing file. Remove the flag, or restore `/root/backup/cks-02/kube-apiserver.yaml` and reapply the profiling fix.

A hardening flag that references a file needs the file to exist **inside the container**, which means a matching `volumeMounts` and `volumes` entry unless the path is already under a mounted directory such as `/etc/kubernetes/pki`. Every later lab that edits the API server repeats this pattern.

---

## 8. Cleanup

```bash
kubectl delete job kube-bench-master kube-bench-node
rm -f job-master.yaml job-node.yaml master.txt node.txt
```

---

## Further reading

- [kube-bench documentation](https://aquasecurity.github.io/kube-bench/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [kube-apiserver reference](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/03-audit-logging|Lab CKS-03 — Audit Logging]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
