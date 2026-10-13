---
title: CKS Practice Set
tags: [kubernetes, certifications, cks, exam-prep, practice, security]
date: 2026-10-13
description: "A timed set of seven original CKS-style tasks on the lab cluster, each needing a control that is applied and then proved with an allowed and a denied test, plus a list of the objectives this set does not reach."
---

# CKS Practice Set

Seven tasks to be done in one sitting on the lab cluster. These are original practice tasks written for this wiki. They are **not** reconstructions of exam questions, and a score here is not a prediction of an exam result.

**This set is narrower than the exam.** It uses only what a plain kind cluster offers: RBAC, Pod Security, NetworkPolicy, `securityContext`, an API server flag and an investigation. It does not include the tool-based tasks that make up much of the CKS: Falco rules, Trivy and SBOMs, kube-bench, audit policy, Secrets encryption, AppArmor, gVisor or Cilium. Rehearse those with their labs, listed at the end. Passing this set alone is not evidence of readiness for the CKS.

The setup script was run on kind v0.33.0 with Kubernetes v1.37.0 on 2026-10-13, and the mechanism behind each task was run on that version in the lab it points to. The seven tasks have not been run together as one timed sitting.

Part of the [[Kubernetes/certifications/cks|CKS Track]].

---

## Rules

- **Time:** 75 minutes.
- **Documentation:** only the sites the CKS allows, listed in the [[Kubernetes/certifications/index|hub]]. `helm.sh` is not one of them.
- **Do not open the labs** while the clock runs.
- **Every security task has two halves:** what must now be refused, and what must still work. A control that breaks the workload earns nothing.
- Run the checks **after** time is up.

## Setup

Use the throwaway cluster from [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]. Task 6 edits the API server's manifest; the setup saves a copy for the reset.

```bash
cat << 'SETUP' > cks-setup.sh
for N in s1 s2 s3 s4 s5; do kubectl create namespace $N; done
kubectl -n s1 create serviceaccount billing
kubectl -n s1 create configmap rates --from-literal=vat=20
kubectl -n s1 create secret generic ledger-key --from-literal=k=v
kubectl create clusterrolebinding s1-billing-admin --clusterrole=cluster-admin --serviceaccount=s1:billing
kubectl -n s1 create rolebinding billing-edit --clusterrole=edit --serviceaccount=s1:billing
kubectl -n s2 create deployment portal --image=ghcr.io/stefanprodan/podinfo:6.7.1 --replicas=2
kubectl -n s3 create deployment db --image=ghcr.io/stefanprodan/podinfo:6.7.1 --port=9898
kubectl -n s3 expose deployment db --port=9898
kubectl -n s3 run api --image=curlimages/curl:8.10.1 --labels=app=api --command -- sleep 7200
kubectl -n s3 run batch --image=curlimages/curl:8.10.1 --labels=app=batch --command -- sleep 7200
kubectl -n s4 create deployment renderer --image=ghcr.io/stefanprodan/podinfo:6.7.1
for A in orders search; do kubectl -n s5 create deployment $A --image=ghcr.io/stefanprodan/podinfo:6.7.1; done
kubectl -n s5 create serviceaccount log-forwarder
kubectl -n s5 create role log-forwarder --verb=get,list --resource=secrets
kubectl -n s5 create rolebinding log-forwarder --role=log-forwarder --serviceaccount=s5:log-forwarder
kubectl -n s5 create deployment log-forwarder --image=curlimages/curl:8.10.1 --dry-run=client -o yaml -- sleep 7200 \
  | kubectl patch --local -f - --type json -o yaml -p '[{"op":"add","path":"/spec/template/spec/serviceAccountName","value":"log-forwarder"},{"op":"add","path":"/spec/template/spec/hostNetwork","value":true},{"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"privileged":true}},{"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"h","hostPath":{"path":"/etc/kubernetes"}}]},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[{"name":"h","mountPath":"/host-k8s"}]}]' \
  | kubectl apply -f -
docker exec k8s-lab-control-plane sh -c 'mkdir -p /root/backup/cks-mock && cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/backup/cks-mock/'
SETUP
sh cks-setup.sh > /dev/null 2>&1
```

Start the clock.

---

## Tasks

| #   | Where                        | Weight | Domain                                   |
| :-- | :--------------------------- | :----- | :--------------------------------------- |
| 1   | namespace `s1`               | 16     | Cluster Hardening                        |
| 2   | namespace `s2`               | 16     | Minimize Microservice Vulnerabilities    |
| 3   | namespace `s3`               | 16     | Cluster Setup                            |
| 4   | namespace `s4`               | 14     | Monitoring, Logging and Runtime Security |
| 5   | namespace `s5`               | 20     | Monitoring, Logging and Runtime Security |
| 6   | node `k8s-lab-control-plane` | 10     | Cluster Setup                            |
| 7   | namespace `s1`               | 8      | Cluster Hardening                        |

**Task 1 (`s1`).** ServiceAccount `billing` has far more access than it needs. It must be able to read the ConfigMap `rates` in `s1` and nothing else, anywhere. Find and remove every grant that gives it more, and add what is needed. Do not delete any built-in role.

**Task 2 (`s2`).** Enforce the `restricted` Pod Security Standard on the namespace. Deployment `portal` must keep running with 2 ready replicas, and every Pod in the namespace must comply; none may be left over from before.

**Task 3 (`s3`).** Only Pods labelled `app=api` in namespace `s3` may connect to the `db` Pods, and only on TCP 9898. All other ingress to **any** Pod in the namespace must be denied. Pod `api` must still reach `http://db:9898/`; Pod `batch` must not. Do not restrict egress.

**Task 4 (`s4`).** Make the container of Deployment `renderer` immutable at runtime: nothing may be written to its filesystem except under `/tmp`, it must use the runtime's default seccomp profile, and it must not be able to gain privileges. The application must stay ready.

**Task 5 (`s5`).** One workload in this namespace is a risk to the node it runs on. Identify it and write its Deployment's name to `/tmp/s5-suspect.txt`. Write to `/tmp/s5-access.txt` the Kubernetes resource types its ServiceAccount can read. Then contain it: its Pod must keep existing for analysis but must have no API permissions and must not be recreated by its controller. Finally, make the namespace refuse any future Pod of that kind, without affecting `orders` and `search`.

**Task 6.** On the control-plane node, disable profiling on the API server. The API server must come back healthy.

**Task 7 (`s1`).** Make sure no Pod that uses the namespace's `default` ServiceAccount gets a token mounted, unless the Pod asks for one explicitly.

---

## Checks

Stop the clock first. Award a task's weight only if every line matches.

```bash
# 1 (16): yes, then no on every other line
B=system:serviceaccount:s1:billing
kubectl auth can-i get configmap/rates -n s1 --as=$B         # yes
kubectl auth can-i list configmaps -n s1 --as=$B             # no
kubectl auth can-i get secret/ledger-key -n s1 --as=$B       # no
kubectl auth can-i create pods -n s1 --as=$B                 # no
kubectl auth can-i get pods -n kube-system --as=$B           # no
kubectl get clusterrole cluster-admin edit --no-headers | wc -l    # 2: the built-in roles still exist

# 2 (16): restricted; 2; and no Pod listed by the dry run
kubectl get namespace s2 -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}'
kubectl -n s2 get deployment portal -o jsonpath='{.status.readyReplicas}{"\n"}'
kubectl label --dry-run=server --overwrite namespace s2 pod-security.kubernetes.io/enforce=restricted   # no "violate" warning

# 3 (16): api 200; batch 000 (timeout); egress still works
kubectl -n s3 exec api -- curl -s -m 4 -o /dev/null -w 'api %{http_code}\n' http://db:9898/
kubectl -n s3 exec batch -- curl -s -m 4 -o /dev/null -w 'batch %{http_code}\n' http://db:9898/
kubectl -n s3 exec batch -- nslookup -timeout=3 kubernetes.default.svc.cluster.local | grep -c Address    # 2 or more
kubectl -n s3 get networkpolicy -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.policyTypes}{"\n"}{end}'   # no Egress

# 4 (14): Read-only file system; ok; NoNewPrivs 1; Seccomp 2; 1
kubectl -n s4 exec deployment/renderer -- sh -c 'touch /home/app/x; touch /tmp/x && echo ok; grep -E "NoNewPrivs|Seccomp:" /proc/1/status'
kubectl -n s4 get deployment renderer -o jsonpath='{.status.readyReplicas}{"\n"}'

# 5 (20): log-forwarder; secrets; no; one unowned Pod and a Deployment at 0; a rejection
cat /tmp/s5-suspect.txt /tmp/s5-access.txt
kubectl auth can-i list secrets -n s5 --as=system:serviceaccount:s5:log-forwarder          # no
kubectl -n s5 get deployment log-forwarder -o jsonpath='{.spec.replicas}{"\n"}'            # 0
kubectl -n s5 get pods -o custom-columns='NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind,PRIV:.spec.containers[0].securityContext.privileged'   # one privileged Pod with OWNER <none>
kubectl -n s5 run probe --image=busybox:1.36 --restart=Never --overrides='{"spec":{"hostNetwork":true,"containers":[{"name":"p","image":"busybox:1.36","command":["sleep","5"]}]}}'   # Forbidden: violates PodSecurity
kubectl -n s5 get deployment orders search -o jsonpath='{range .items[*]}{.status.readyReplicas} {end}{"\n"}'   # 1 1

# 6 (10): --profiling=false, and the nodes answer
docker exec k8s-lab-control-plane sh -c 'ps -ef | grep -o "kube-apiserver.*" | tr " " "\n" | grep profiling | head -n 1'
kubectl get nodes

# 7 (8): false, and a new Pod has no token
kubectl -n s1 get serviceaccount default -o jsonpath='{.automountServiceAccountToken}{"\n"}'
kubectl -n s1 run t7 --image=busybox:1.36 --restart=Never -- sleep 60
kubectl -n s1 wait --for=condition=Ready pod/t7 --timeout=60s
kubectl -n s1 exec t7 -- ls /var/run/secrets/kubernetes.io/serviceaccount     # No such file or directory
```

The CKS pass mark is 67%. Record your score, the time used and which tasks you flagged.

---

## Review

Points that decide these tasks, to compare with what you did:

- **Task 1:** two bindings grant the excess, one cluster-wide and one in the namespace. Deleting the ClusterRole `cluster-admin` instead of the binding would break the cluster.
- **Task 2:** labelling the namespace does not change running Pods. The Deployment must be rewritten to comply, and the old Pods must be gone.
- **Task 3:** "all other ingress to any Pod" needs a default-deny for the namespace as well as the allow rule. Adding `Egress` to `policyTypes` breaks DNS and fails the task.
- **Task 4:** a read-only root filesystem needs a writable volume at `/tmp`, or the application may stop working.
- **Task 5:** the order matters. Removing the Pod's label releases it from its ReplicaSet, which then creates a replacement unless the Deployment is scaled to zero. `baseline` is the standard that refuses `privileged`, host namespaces and `hostPath`, and it does not affect ordinary Pods.
- **Task 6:** after editing a static Pod manifest, wait for the API server, and if it does not return, read the container's log with `crictl`.

| Task | Lab                                                                                                                         |
| :--- | :-------------------------------------------------------------------------------------------------------------------------- |
| 1, 7 | [[Kubernetes/labs/cks/13-rbac-remediation\|Lab CKS-13]], [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]] |
| 2, 3 | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]]                                                          |
| 4    | [[Kubernetes/labs/cks/05-seccomp-apparmor-and-immutability\|Lab CKS-05]]                                                    |
| 5    | [[Kubernetes/labs/cks/14-incident-investigation\|Lab CKS-14]]                                                               |
| 6    | [[Kubernetes/labs/cks/02-cis-benchmark-kube-bench\|Lab CKS-02]]                                                             |

### Objectives this set does not reach

Rehearse each of these from its lab, with the allowed documentation only and a time limit you set yourself:

| Objective                              | Lab                                                                              |
| :------------------------------------- | :------------------------------------------------------------------------------- |
| Audit policy and reading the audit log | [[Kubernetes/labs/cks/03-audit-logging\|Lab CKS-03]]                             |
| Secrets encryption at rest             | [[Kubernetes/labs/cks/04-secrets-encryption-at-rest\|Lab CKS-04]]                |
| Falco rules and alerts                 | [[Kubernetes/labs/cks/06-falco-runtime-detection\|Lab CKS-06]]                   |
| Image scanning, SBOM, static analysis  | [[Kubernetes/labs/cks/07-image-scanning-and-static-analysis\|Lab CKS-07]]        |
| Admission control for images           | [[Kubernetes/labs/cks/08-image-admission-control\|Lab CKS-08]]                   |
| Image signing                          | [[Kubernetes/labs/cks/09-image-signing-with-cosign\|Lab CKS-09]]                 |
| RuntimeClass and sandboxing            | [[Kubernetes/labs/cks/10-runtime-sandboxing-gvisor\|Lab CKS-10]]                 |
| Pod-to-Pod encryption                  | [[Kubernetes/labs/cks/11-cilium-encryption-and-metadata-protection\|Lab CKS-11]] |
| Host footprint                         | [[Kubernetes/labs/cks/12-host-os-footprint\|Lab CKS-12]]                         |
| AppArmor                               | Not run in this wiki; needs a virtual machine node                               |

## Reset

```bash
kubectl delete namespace s1 s2 s3 s4 s5
kubectl delete clusterrolebinding s1-billing-admin 2>/dev/null
docker exec k8s-lab-control-plane sh -c \
  'cp /root/backup/cks-mock/kube-apiserver.yaml /etc/kubernetes/manifests/ && rm -rf /root/backup/cks-mock'
until kubectl get nodes > /dev/null 2>&1; do sleep 5; done
kubectl get nodes
rm -f cks-setup.sh /tmp/s5-suspect.txt /tmp/s5-access.txt
```
