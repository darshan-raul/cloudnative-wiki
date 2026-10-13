---
title: "Lab CKS-13 — RBAC Remediation"
tags:
  [kubernetes, labs, cks, rbac, least-privilege, serviceaccounts, authorization]
date: 2026-10-13
description: Audit a ServiceAccount that has collected far too many permissions, find every binding that grants them, and replace them with the exact access the workload needs, proving both what is allowed and what is denied.
---

# Lab CKS-13 — RBAC Remediation

[[Kubernetes/labs/cks/01-workload-security-hardening|Lab CKS-01]] removed all API access from a workload that needed none. The harder and more common task is a workload that **does** need the API and has been given far more than it needs. "Minimize exposure" in the CKS objectives means finding every grant, removing the excess, and proving the workload still works.

Concepts: [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] and [[Kubernetes/concepts/L07-security/01-api-access/02-service-accounts|Service Accounts]].

Tested 2026-10-13 on kind v0.33.0 with Kubernetes v1.37.0. The checks use impersonation (`--as`), which evaluates exactly the rules a real request from that identity would meet.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]** and `jq`. No other lab is required.

The requirement, as the application team states it:

> The `reporter` ServiceAccount in namespace `payments` reads one ConfigMap, `report-settings`, and lists the Pods in its own namespace. It needs nothing else.

Create the starting state:

```bash
cat << 'SETUP' > rbac-setup.sh
kubectl create namespace payments
kubectl -n payments create serviceaccount reporter
kubectl -n payments create configmap report-settings --from-literal=format=csv
kubectl -n payments create configmap other-settings --from-literal=x=y
kubectl -n payments create secret generic card-vault --from-literal=key=4111111111111111
kubectl create clusterrole payments-reporter --verb='*' --resource='*'
kubectl create clusterrolebinding payments-reporter --clusterrole=payments-reporter --serviceaccount=payments:reporter
kubectl -n payments create rolebinding reporter-edit --clusterrole=edit --serviceaccount=payments:reporter
kubectl -n payments create rolebinding everyone-view --clusterrole=view --group=system:serviceaccounts
SETUP
sh rbac-setup.sh

SA=system:serviceaccount:payments:reporter
```

---

## 2. Audit: What Can This Identity Do?

```bash
kubectl auth can-i --list --as=$SA -n payments | head -n 4
kubectl auth can-i '*' '*' --as=$SA
kubectl auth can-i get secrets -n kube-system --as=$SA
```

```
Resources   Non-Resource URLs   Resource Names   Verbs
*           []                  []               [*]
...
yes
yes
```

The first row is every verb on every resource. The identity is a cluster administrator in all but name: it can read Secrets in `kube-system`.

`can-i --list` tells you **what** is allowed, not **which object** allows it. Removing access means finding every binding that names the identity, and an identity can be named in three ways:

| Subject in a binding                                       | Matches                               |
| :--------------------------------------------------------- | :------------------------------------ |
| `ServiceAccount` `reporter` in `payments`                  | This account directly                 |
| `Group` `system:serviceaccounts:payments`                  | Every ServiceAccount in the namespace |
| `Group` `system:serviceaccounts` or `system:authenticated` | Every ServiceAccount, or everyone     |

Search both binding kinds for all three:

```bash
kubectl get clusterrolebinding -o json | jq -r '
  .items[] | select(.subjects[]? | (.kind=="ServiceAccount" and .name=="reporter" and .namespace=="payments"))
  | "\(.metadata.name) -> \(.roleRef.kind)/\(.roleRef.name)"'

kubectl get rolebinding -A -o json | jq -r '
  .items[] | select(.subjects[]? | ((.kind=="ServiceAccount" and .name=="reporter")
                                  or (.kind=="Group" and (.name | startswith("system:serviceaccounts")))))
  | "\(.metadata.namespace)/\(.metadata.name) -> \(.roleRef.kind)/\(.roleRef.name) [\(.subjects | map(.kind + ":" + .name) | join(","))]"'
```

```
payments-reporter -> ClusterRole/payments-reporter

payments/everyone-view -> ClusterRole/view [Group:system:serviceaccounts]
payments/reporter-edit -> ClusterRole/edit [ServiceAccount:reporter]
```

Three grants, each a different mistake:

| Binding                                | Problem                                                                                |
| :------------------------------------- | :------------------------------------------------------------------------------------- |
| ClusterRoleBinding `payments-reporter` | A wildcard ClusterRole, bound cluster-wide                                             |
| RoleBinding `reporter-edit`            | `edit` in the namespace: can change workloads and read Secrets                         |
| RoleBinding `everyone-view`            | Gives `view` in `payments` to **every ServiceAccount in the cluster**, through a group |

Without `jq`, `kubectl get rolebinding,clusterrolebinding -A -o wide` prints the subjects in the last columns and can be searched with `grep`.

A ClusterRole is not dangerous in itself. A **RoleBinding** to a ClusterRole grants its rules in one namespace only; a **ClusterRoleBinding** grants them everywhere.

---

## 3. Remediate

Remove all three grants, then add back exactly what was asked for:

```bash
kubectl delete clusterrolebinding payments-reporter
kubectl delete clusterrole payments-reporter
kubectl -n payments delete rolebinding reporter-edit everyone-view

kubectl -n payments create role report-reader --verb=get --resource=configmaps --resource-name=report-settings
kubectl -n payments create role pod-lister --verb=get,list --resource=pods

kubectl -n payments create rolebinding reporter-read --role=report-reader --serviceaccount=payments:reporter
kubectl -n payments create rolebinding reporter-pods --role=pod-lister --serviceaccount=payments:reporter
```

- `--resource-name` limits the rule to one named object. It works with `get`, `update`, `patch` and `delete`, and **cannot** restrict `list` or `watch`, which is why the requirement to read one ConfigMap became `get` only.
- The custom ClusterRole was deleted because nothing else used it. Never delete a built-in role such as `edit` or `view`; remove the binding.
- Before deleting a group binding such as `everyone-view` on a real cluster, find out who else relies on it. Here the requirement says nobody should.

---

## 4. Verify Both Directions

A remediation has two ways to be wrong: something is still allowed that should not be, or something needed is now denied. Test both.

```bash
check() { printf '%-36s' "$*"; kubectl auth can-i "$@" -n payments --as=$SA; }

check get configmap/report-settings
check list pods
check get configmap/other-settings
check list configmaps
check delete pods
check get secret/card-vault
printf '%-36s' "get pods -n default"; kubectl auth can-i get pods -n default --as=$SA

kubectl auth can-i --list --as=$SA -n payments | grep -E "configmaps|pods|secrets|^\*"
```

```
get configmap/report-settings       yes
list pods                           yes
get configmap/other-settings        no
list configmaps                     no
delete pods                         no
get secret/card-vault               no
get pods -n default                 no

configmaps   []   [report-settings]   [get]
pods         []   []                  [list get]
```

The first two are the requirement and must say `yes`. The rest are the excess and must say `no`. The final listing shows two rules and nothing else for the resources that matter.

Finally, confirm no other ServiceAccount kept access through the group binding:

```bash
kubectl auth can-i list pods -n payments --as=system:serviceaccount:default:default
```

```
no
```

---

## 5. Controlled Failure Scenario: The Binding That Looks Right

Create a Role and a binding for a second account, with one mistake:

```bash
kubectl -n payments create serviceaccount auditor
kubectl -n payments create role secret-names --verb=list --resource=secrets
kubectl -n payments create rolebinding auditor-secrets --role=secret-names --serviceaccount=default:auditor

kubectl auth can-i list secrets -n payments --as=system:serviceaccount:payments:auditor
```

```
no
```

The Role exists, the binding exists, and the answer is `no`. Nothing reports an error, because a binding to a subject that does not exist is perfectly valid. Look at who the binding names:

```bash
kubectl -n payments get rolebinding auditor-secrets -o jsonpath='{.subjects}{"\n"}'
```

```
[{"kind":"ServiceAccount","name":"auditor","namespace":"default"}]
```

`--serviceaccount` takes `<namespace>:<name>`, and the namespace is wrong. A binding's subjects can be edited, but its `roleRef` cannot; a wrong role means deleting and recreating the binding.

```bash
kubectl -n payments delete rolebinding auditor-secrets
kubectl -n payments create rolebinding auditor-secrets --role=secret-names --serviceaccount=payments:auditor
kubectl auth can-i list secrets -n payments --as=system:serviceaccount:payments:auditor     # yes
```

> [!warning] `list` on Secrets is `get` on Secrets
> The Role was named "secret-names", but a `list` response contains every Secret's full content. There is no way to grant names without values. Treat `list` and `watch` on Secrets as read access to all of them.

Other verbs that grant more than they appear to: `create` on `pods` (run anything with any ServiceAccount in the namespace), `escalate` and `bind` on roles, `impersonate`, and `create` on `serviceaccounts/token`.

---

## 6. Cleanup

```bash
kubectl delete namespace payments
rm -f rbac-setup.sh
```

The ClusterRole and ClusterRoleBinding were removed in section 3. Confirm with `kubectl get clusterrolebinding | grep payments`, which should print nothing.

---

## Practice Without the Answer

Suggested time: 10 minutes.

```bash
kubectl create namespace ops
kubectl -n ops create serviceaccount deployer
kubectl create clusterrolebinding ops-deployer --clusterrole=cluster-admin --serviceaccount=ops:deployer
kubectl -n ops create rolebinding all-accounts --clusterrole=admin --group=system:serviceaccounts:ops
```

The `deployer` account must be able to get, list, update and patch Deployments in `ops`, and read (not change) ConfigMaps in `ops`. It must have no access outside `ops`. No other ServiceAccount in `ops` should have any access.

Check yourself:

```bash
D=system:serviceaccount:ops:deployer
kubectl auth can-i patch deployments -n ops --as=$D            # yes
kubectl auth can-i get configmaps -n ops --as=$D               # yes
kubectl auth can-i update configmaps -n ops --as=$D            # no
kubectl auth can-i delete deployments -n ops --as=$D           # no
kubectl auth can-i get secrets -n ops --as=$D                  # no
kubectl auth can-i get pods -n kube-system --as=$D             # no
kubectl auth can-i list pods -n ops --as=system:serviceaccount:ops:default   # no
```

Reset with `kubectl delete namespace ops; kubectl delete clusterrolebinding ops-deployer`.

---

## Further reading

- [Using RBAC authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)
- [Checking API access](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/14-incident-investigation|Lab CKS-14 — Investigating an Unknown Incident]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
