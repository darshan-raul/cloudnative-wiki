---
title: "Lab CKS-03 — Audit Logging"
tags: [kubernetes, labs, cks, audit, api-server, logging]
date: 2026-10-13
description: "Write an audit policy, enable it on the API server with the log flags and volume mounts, and query the audit log to find who did what."
---

# Lab CKS-03 — Audit Logging

Audit logging is off by default. Turning it on takes a policy file, four or five API server flags and two volume mounts, and a mistake in any of them stops the API server from starting. This lab builds it step by step and then uses the log to answer an investigation question.

Concepts: [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/15-audit-logging|Audit Logging]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there.

Verified on `kind` v0.31 with Kubernetes v1.35.0.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**.
- A control plane node shell with an editor and a backup:

```bash
docker exec -it k8s-lab-control-plane bash
# node
apt-get update && apt-get install -y vim-tiny
mkdir -p /root/backup/cks-03 && cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/backup/cks-03/
```

```bash
# host
kubectl create namespace audit-lab
```

---

## 2. Write the Policy

```bash
# node
mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit

cat > /etc/kubernetes/audit/policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - RequestReceived
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]
  - level: RequestResponse
    namespaces: ["audit-lab"]
    resources:
      - group: ""
        resources: ["configmaps"]
  - level: None
EOF
```

Rules are evaluated top to bottom and the **first match wins**. The final `level: None` rule drops everything the earlier rules did not claim.

| Level             | Records                                   |
| :---------------- | :---------------------------------------- |
| `None`            | Nothing                                   |
| `Metadata`        | Who, what, when, and the response code    |
| `Request`         | Metadata plus the request body            |
| `RequestResponse` | Metadata plus request and response bodies |

Secrets are logged at `Metadata` on purpose. `Request` or `RequestResponse` would write the Secret values into the audit log.

---

## 3. Enable It on the API Server

Edit `/etc/kubernetes/manifests/kube-apiserver.yaml` and make three additions.

**Flags**, in the `command` list:

```yaml
- --audit-policy-file=/etc/kubernetes/audit/policy.yaml
- --audit-log-path=/var/log/kubernetes/audit/audit.log
- --audit-log-maxage=7
- --audit-log-maxbackup=3
- --audit-log-maxsize=100
```

**Volume mounts**, in the container's `volumeMounts`:

```yaml
- name: audit-policy
  mountPath: /etc/kubernetes/audit
  readOnly: true
- name: audit-log
  mountPath: /var/log/kubernetes/audit
```

**Volumes**, in the Pod's `volumes`:

```yaml
- name: audit-policy
  hostPath:
    path: /etc/kubernetes/audit
    type: Directory
- name: audit-log
  hostPath:
    path: /var/log/kubernetes/audit
    type: DirectoryOrCreate
```

The API server runs in a container. It can only read the policy and write the log if both host directories are mounted into it. The log mount must not be read-only.

| Flag                    | Meaning                                    |
| :---------------------- | :----------------------------------------- |
| `--audit-log-maxage`    | Days to keep rotated log files             |
| `--audit-log-maxbackup` | Number of rotated files to keep            |
| `--audit-log-maxsize`   | Size in megabytes before a file is rotated |

Save the file and watch the API server come back:

```bash
# node
watch crictl ps --name kube-apiserver
```

---

## 4. Verification

Generate some events:

```bash
# host
kubectl -n audit-lab create secret generic db --from-literal=password=s3cret
kubectl -n audit-lab create configmap app --from-literal=mode=prod
kubectl -n audit-lab get secret db -o yaml > /dev/null
kubectl -n audit-lab get pods
```

```bash
# node
tail -3 /var/log/kubernetes/audit/audit.log
```

Each line is one JSON event. `kind` nodes include `jq`; in the exam, `grep` is always there and `jq` usually is.

```bash
# node
jq -r 'select(.objectRef.resource=="secrets")
       | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.name, .level]
       | @tsv' /var/log/kubernetes/audit/audit.log
```

```text
2026-10-13T07:35:24.755123Z   kubernetes-admin   create   audit-lab   db   Metadata
2026-10-13T07:35:24.863139Z   kubernetes-admin   get      audit-lab   db   Metadata
```

Confirm the policy did what it says:

- Secret events are at `Metadata` and contain no `requestObject`.
- The ConfigMap event is at `RequestResponse` and contains the full `requestObject` and `responseObject`.
- The `get pods` call is not in the log at all.

```bash
# node
grep '"resource":"configmaps"' /var/log/kubernetes/audit/audit.log | jq '.level, .requestObject.data'
grep -c '"resource":"pods"' /var/log/kubernetes/audit/audit.log
```

---

## 5. Investigation Exercise

Delete the Secret as a different identity, then find out who did it using only the log:

```bash
# host
kubectl -n audit-lab create serviceaccount intruder
kubectl -n audit-lab create role secret-admin --verb='*' --resource=secrets
kubectl -n audit-lab create rolebinding intruder --role=secret-admin --serviceaccount=audit-lab:intruder
kubectl -n audit-lab delete secret db --as=system:serviceaccount:audit-lab:intruder
```

```bash
# node
jq -r 'select(.verb=="delete" and .objectRef.resource=="secrets")
       | [.requestReceivedTimestamp, .user.username, .impersonatedUser.username, .sourceIPs[0], .responseStatus.code]
       | @tsv' /var/log/kubernetes/audit/audit.log
```

```text
2026-10-13T07:35:25.117555Z   kubernetes-admin   system:serviceaccount:audit-lab:intruder   172.18.0.1   200
```

The event shows the real caller in `user.username` and the identity it acted as in `impersonatedUser.username`. Impersonation never hides who made the call.

---

## 6. Controlled Failure Scenario: The Missing Mount

Edit the working manifest and delete the two audit entries from `volumeMounts` and the two from `volumes`, leaving the flags in place.

The API server never comes back:

```bash
# node
crictl ps -a --name kube-apiserver
crictl logs --tail 3 $(crictl ps -a -q --name kube-apiserver | head -1)
```

```text
"command failed" err="loading audit policy file: failed to read file path \"/etc/kubernetes/audit/policy.yaml\": open /etc/kubernetes/audit/policy.yaml: no such file or directory"
```

The file exists on the node, but not inside the container. Put the `volumeMounts` and `volumes` from section 3 back and the API server starts.

The same failure appears with a YAML error in the policy file itself, so when the API server is down after an audit change, check the policy and the mounts in that order.

---

## 7. Cleanup

```bash
# host
kubectl delete namespace audit-lab
```

To turn auditing off, restore `/root/backup/cks-03/kube-apiserver.yaml` and wait for `kubectl get nodes` to answer again. Leave it on if you are continuing to [[Kubernetes/labs/cks/06-falco-runtime-detection|Lab CKS-06]], where the audit log complements Falco.

---

## Further reading

- [Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Audit policy reference](https://kubernetes.io/docs/reference/config-api/apiserver-audit.v1/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/04-secrets-encryption-at-rest|Lab CKS-04 — Secrets Encryption at Rest]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
