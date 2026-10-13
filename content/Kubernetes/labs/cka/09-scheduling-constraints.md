---
title: "Lab CKA-09 — Taints, Affinity, Priority & Static Pods"
tags:
  [
    kubernetes,
    labs,
    cka,
    scheduling,
    taints,
    tolerations,
    affinity,
    priority,
    static-pods,
  ]
date: 2026-10-13
description: Steer Pods with taints and tolerations, node and Pod affinity, and PriorityClasses, then bypass the scheduler with nodeName and a static Pod, reading the scheduler's message each time.
---

# Lab CKA-09 — Taints, Affinity, Priority & Static Pods

[[Kubernetes/labs/cka/02-scheduling-and-autoscaling|Lab CKA-02]] covered resource requests, topology spread and drains. This lab covers the other ways the CKA expects you to control where a Pod runs: keeping Pods **off** a node (taints), drawing them **to** a node (selectors and affinity), deciding who wins when there is no room (priority), and placing Pods **without** the scheduler (`nodeName` and static Pods).

Concepts: [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling|Scheduling]], [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption|Priority and Preemption]] and [[Kubernetes/concepts/L03-workloads/11-static-pods|Static Pods]].

Tested 2026-10-13 on kind v0.33.0 with Kubernetes v1.37.0.

| Mechanism                      | Set on           | Effect                                                        |
| :----------------------------- | :--------------- | :------------------------------------------------------------ |
| Taint                          | Node             | Repels every Pod that does not tolerate it                    |
| Toleration                     | Pod              | Permits a tainted node. It does **not** attract the Pod to it |
| `nodeSelector` / node affinity | Pod              | Restricts or prefers nodes by label                           |
| Pod affinity / anti-affinity   | Pod              | Places a Pod near, or away from, other Pods                   |
| PriorityClass                  | Pod (by name)    | Higher priority may evict lower to make room                  |
| `nodeName`                     | Pod              | Skips the scheduler entirely                                  |
| Static Pod                     | File on the node | The kubelet runs it with no API server involved               |

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**, all three nodes `Ready` and none cordoned. No other lab is required.

```bash
kubectl create namespace place-lab
kubectl config set-context --current --namespace=place-lab
kubectl get nodes
```

This lab changes **node** taints and labels, which are cluster-wide. Each section removes what it added. Section 7 lists a final check.

---

## 2. Taints and Tolerations

### Step 1: `NoSchedule` keeps new Pods away

```bash
kubectl taint nodes k8s-lab-worker dedicated=gpu:NoSchedule

kubectl create deployment plain --image=busybox:1.36 --replicas=4 -- sleep 3600
kubectl rollout status deployment/plain --timeout=60s
kubectl get pods -l app=plain -o custom-columns=NODE:.spec.nodeName --no-headers | sort | uniq -c
```

```
      4 k8s-lab-worker2
```

All four went to the untainted worker. A taint is `key=value:effect`, and the three effects are:

| Effect             | New Pods without a toleration | Pods already running |
| :----------------- | :---------------------------- | :------------------- |
| `NoSchedule`       | Not scheduled here            | Left alone           |
| `PreferNoSchedule` | Avoided if another node fits  | Left alone           |
| `NoExecute`        | Not scheduled here            | **Evicted**          |

### Step 2: A toleration permits, a selector directs

```bash
kubectl run tolerant --image=busybox:1.36 --restart=Never --overrides='{
  "spec": {
    "tolerations": [{"key": "dedicated", "operator": "Equal", "value": "gpu", "effect": "NoSchedule"}],
    "nodeSelector": {"kubernetes.io/hostname": "k8s-lab-worker"},
    "containers": [{"name": "c", "image": "busybox:1.36", "command": ["sleep", "3600"]}]
  }}'

kubectl get pod tolerant -o wide
```

```
NAME       READY   STATUS    RESTARTS   AGE   IP            NODE
tolerant   1/1     Running   0          3s    10.244.2.52   k8s-lab-worker
```

The toleration alone would only have made the tainted node **allowed**; the Pod could still have landed on `k8s-lab-worker2`. To reserve a node for a workload you need both halves: a taint to keep others out, and a selector or affinity to bring yours in. `operator: Exists` with no `value` tolerates any value of the key.

### Step 3: Controlled failure: `NoExecute` evicts, and there is nowhere to go

```bash
kubectl taint nodes k8s-lab-worker2 maintenance=true:NoExecute

sleep 8
kubectl get pods -l app=plain -o wide
kubectl describe pod -l app=plain | grep FailedScheduling | head -n 1
```

```
NAME                     READY   STATUS        RESTARTS   AGE   NODE
plain-594ddbf7c9-7wmjt   1/1     Terminating   0          14s   k8s-lab-worker2
plain-594ddbf7c9-84mwr   1/1     Terminating   0          14s   k8s-lab-worker2
plain-594ddbf7c9-97t6v   0/1     Pending       0          9s    <none>
plain-594ddbf7c9-f8h9t   0/1     Pending       0          8s    <none>
...

Warning  FailedScheduling  ...  0/3 nodes are available: 3 node(s) had untolerated taint(s). ...
```

`NoExecute` removed the running Pods at once, with no drain and no regard for PodDisruptionBudgets. Their replacements are `Pending` because every node is now tainted: the control plane by default, `worker` from step 1 and `worker2` from this step. The scheduler's message counts them: `3 node(s) had untolerated taint(s)`.

List taints across the cluster when you see that message:

```bash
kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key'
```

Remove both taints (a trailing `-` deletes one) and clean up:

```bash
kubectl taint nodes k8s-lab-worker2 maintenance=true:NoExecute-
kubectl taint nodes k8s-lab-worker dedicated=gpu:NoSchedule-
kubectl delete deployment plain
kubectl delete pod tolerant --grace-period=1
```

---

## 3. Node Selectors and Node Affinity

```bash
kubectl label node k8s-lab-worker disktype=ssd

cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: needs-ssd
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: disktype
                operator: In
                values: ["ssd"]
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 50
          preference:
            matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values: ["zone-b"]
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: needs-nvme
spec:
  nodeSelector:
    disktype: nvme
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
EOF

kubectl get pods -o wide
kubectl describe pod needs-nvme | grep FailedScheduling
```

```
NAME         READY   STATUS    RESTARTS   AGE   NODE
needs-nvme   0/1     Pending   0          4s    <none>
needs-ssd    1/1     Running   0          4s    k8s-lab-worker

Warning  FailedScheduling  4s  default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match Pod's node affinity/selector. ...
```

- `needs-ssd` has a **required** rule (`disktype In [ssd]`) and a **preferred** one (zone-b). The only node with `disktype=ssd` is in zone-a, so the requirement decided and the preference was ignored. A preference never blocks scheduling.
- `needs-nvme` uses `nodeSelector`, the short form for "label equals value". No node has `disktype=nvme`, so it waits. The message says two nodes `didn't match Pod's node affinity/selector` and the third is the tainted control plane.
- `IgnoredDuringExecution` means the rule is checked only at scheduling time. Removing the label later does not evict the Pod.

A Pending Pod is scheduled as soon as a node fits. Give one the label:

```bash
kubectl label node k8s-lab-worker2 disktype=nvme
kubectl wait --for=condition=Ready pod/needs-nvme --timeout=60s
kubectl get pod needs-nvme -o wide
```

Node affinity adds what `nodeSelector` cannot express: the operators `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt` and `Lt`, several alternative terms, and preferences with weights.

### Pod anti-affinity: one replica per node

```bash
kubectl create deployment spread --image=busybox:1.36 --replicas=3 --dry-run=client -o yaml -- sleep 3600 \
  | kubectl patch --local -f - --type merge -o yaml -p '{"spec":{"template":{"spec":{"affinity":{"podAntiAffinity":{
      "requiredDuringSchedulingIgnoredDuringExecution":[{
        "labelSelector":{"matchLabels":{"app":"spread"}},
        "topologyKey":"kubernetes.io/hostname"}]}}}}}}' \
  | kubectl apply -f -

sleep 8
kubectl get pods -l app=spread -o wide
```

```
NAME                      READY   STATUS    RESTARTS   AGE   NODE
spread-76c9bf4d4c-2vmf5   1/1     Running   0          8s    k8s-lab-worker2
spread-76c9bf4d4c-dldh5   0/1     Pending   0          8s    <none>
spread-76c9bf4d4c-j7qfg   1/1     Running   0          8s    k8s-lab-worker
```

The rule says: do not place this Pod on a node (`topologyKey: kubernetes.io/hostname`) that already runs a Pod labelled `app=spread`. There are two usable nodes and three replicas, so the third cannot be placed. That is the rule working, not a fault. With `preferred...` instead of `required...`, the third replica would share a node.

```bash
kubectl delete deployment spread
kubectl delete pod needs-ssd needs-nvme --grace-period=1
kubectl label node k8s-lab-worker disktype-
kubectl label node k8s-lab-worker2 disktype-
```

---

## 4. Priority and Preemption

When no node has room, the scheduler may evict lower-priority Pods to make room for a higher-priority one.

```bash
kubectl create priorityclass critical --value=100000 --description="business critical"
kubectl get priorityclass
```

```
NAME                      VALUE        GLOBAL-DEFAULT   AGE   PREEMPTIONPOLICY
critical                  100000       false            0s    PreemptLowerPriority
system-cluster-critical   2000000000   false            62m   PreemptLowerPriority
system-node-critical      2000001000   false            62m   PreemptLowerPriority
```

The two `system-` classes are built in and are what protects control plane and node components. A Pod with no class has priority `0`.

Make room scarce: take one worker out of scheduling, and fill most of the other with low-priority Pods that each request one CPU. Adjust the replica count so that it is one less than the node's CPU count (`kubectl get node k8s-lab-worker -o jsonpath='{.status.allocatable.cpu}'`; this machine has 6):

```bash
kubectl cordon k8s-lab-worker2

kubectl create deployment filler --image=busybox:1.36 --replicas=5 --dry-run=client -o yaml -- sleep 3600 \
  | kubectl set resources --local -f - --requests=cpu=1 -o yaml \
  | kubectl apply -f -
kubectl rollout status deployment/filler --timeout=60s
```

Now ask for two CPUs at high priority. Less than one is free:

```bash
kubectl run vip --image=busybox:1.36 --restart=Never --dry-run=client -o yaml -- sleep 3600 \
  | kubectl set resources --local -f - --requests=cpu=2 -o yaml \
  | kubectl patch --local -f - --type merge -p '{"spec":{"priorityClassName":"critical"}}' -o yaml \
  | kubectl apply -f -

sleep 12
kubectl get pods -o wide
kubectl get events --sort-by=.lastTimestamp | grep Preempted
kubectl get pod vip -o jsonpath='{.spec.priority} {.status.nominatedNodeName}{"\n"}'
```

```
NAME                      READY   STATUS        RESTARTS   AGE   NODE
filler-59785ddb65-2zdnf   1/1     Running       0          20s   k8s-lab-worker
filler-59785ddb65-ccbtq   1/1     Running       0          20s   k8s-lab-worker
filler-59785ddb65-dssxg   0/1     Pending       0          12s   <none>
filler-59785ddb65-gb7gx   1/1     Terminating   0          20s   k8s-lab-worker
filler-59785ddb65-jc96v   0/1     Pending       0          12s   <none>
filler-59785ddb65-mmh2s   1/1     Terminating   0          20s   k8s-lab-worker
filler-59785ddb65-s2vpz   1/1     Running       0          20s   k8s-lab-worker
vip                       0/1     Pending       0          12s   <none>

Normal  Preempted  pod/filler-59785ddb65-mmh2s  Preempted by pod 2a49ea07-... on node k8s-lab-worker

100000 k8s-lab-worker
```

Two `filler` Pods were chosen as victims and are terminating. `vip` is `Pending` with a **nominated node**: the scheduler has reserved the space and binds the Pod once the victims have gone, which takes their grace period (30 seconds here, because BusyBox ignores SIGTERM). The Deployment recreates the two victims, and they stay `Pending` because the node is now full.

Preemption considers priority only. It ignores PodDisruptionBudgets if it has to, and it is why a low-priority workload can vanish from a busy cluster with a `Preempted` event as the only trace. `preemptionPolicy: Never` on a PriorityClass gives a Pod a place ahead in the queue without letting it evict anything.

```bash
kubectl delete deployment filler
kubectl delete pod vip --grace-period=1
kubectl uncordon k8s-lab-worker2
kubectl delete priorityclass critical
```

---

## 5. Without the Scheduler: `nodeName`

```bash
kubectl run pinned --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"nodeName":"k8s-lab-control-plane"}}' -- sleep 3600

kubectl wait --for=condition=Ready pod/pinned --timeout=60s
kubectl get pod pinned -o wide
kubectl get events --field-selector involvedObject.name=pinned
```

```
NAME     READY   STATUS    RESTARTS   AGE   NODE
pinned   1/1     Running   0          14s   k8s-lab-control-plane

LAST SEEN   TYPE     REASON    OBJECT       MESSAGE
4s          Normal   Pulling   pod/pinned   Pulling image "busybox:1.36"
```

The Pod runs on the control-plane node **despite its `NoSchedule` taint**, and there is no `Scheduled` event. Setting `nodeName` bypasses the scheduler, and with it every check the scheduler makes: taints, affinity and resource fit. The kubelet on the named node simply runs the Pod. (A `NoExecute` taint would still evict it, because that is enforced separately.)

This is how you place a Pod when the scheduler is down, which is a CKA troubleshooting task. `nodeName` cannot be changed on an existing Pod.

```bash
kubectl delete pod pinned --grace-period=1
```

---

## 6. Without the API Server: Static Pods

The kubelet runs any Pod manifest it finds in its static Pod directory. That is how a kubeadm control plane starts before there is an API server to ask. Open a shell on a worker (`docker exec -it k8s-lab-worker bash`; in the exam, `ssh`):

```bash
# node: k8s-lab-worker
grep staticPodPath /var/lib/kubelet/config.yaml

cat > /etc/kubernetes/manifests/static-web.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  namespace: place-lab
spec:
  containers:
    - name: web
      image: busybox:1.36
      command: ["sh", "-c", "mkdir -p /www; echo static > /www/index.html; httpd -f -p 8080 -h /www"]
EOF
```

```
staticPodPath: /etc/kubernetes/manifests
```

Always read `staticPodPath` from the kubelet's configuration; a task may have moved it. Back on your machine:

```bash
kubectl get pods -o wide
kubectl get pod static-web-k8s-lab-worker \
  -o jsonpath='{.metadata.ownerReferences[0].kind} {.metadata.annotations.kubernetes\.io/config\.source}{"\n"}'
```

```
NAME                        READY   STATUS    RESTARTS   AGE   NODE
static-web-k8s-lab-worker   1/1     Running   0          10s   k8s-lab-worker

Node file
```

The kubelet appended the node name to the Pod's name and created a **mirror Pod** in the API so that you can see it. Its owner is the `Node` and its source is `file`.

### Controlled failure: deleting it does nothing

```bash
kubectl delete pod static-web-k8s-lab-worker --grace-period=1
sleep 8
kubectl get pods
```

```
pod "static-web-k8s-lab-worker" deleted from place-lab namespace

NAME                        READY   STATUS    RESTARTS   AGE
static-web-k8s-lab-worker   1/1     Running   0          8s
```

The delete "succeeded" and the Pod is back. You removed only the mirror; the kubelet still has the file. The same is true of editing: `kubectl edit` on a mirror Pod changes nothing that lasts. A static Pod is changed or removed **only through its file on the node**:

```bash
# node: k8s-lab-worker
rm /etc/kubernetes/manifests/static-web.yaml
```

The Pod disappears within about 20 seconds, the kubelet's file check interval. If a Pod keeps coming back after deletion and its name ends in a node name, look for a manifest on that node before looking for a controller.

---

## 7. Cleanup & Exit State

```bash
kubectl config set-context --current --namespace=default
kubectl delete namespace place-lab

kubectl get nodes
kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key,DISK:.metadata.labels.disktype'
```

All nodes `Ready`, none `SchedulingDisabled`, only the control-plane taint, and no `disktype` label. If anything is left, the commands in each section's last block remove it.

---

## Practice Without the Answer

Suggested time: 12 minutes. Namespace `place`.

1. Reserve `k8s-lab-worker2` for the "batch" team: Pods without a matching toleration must not be scheduled there, and Pods already running there must be left alone.
2. Run a Pod `batch-job` (image `busybox:1.36`, `sleep 3600`) that is guaranteed to run on that node.
3. Run a Deployment `cache` with 2 replicas that must never have two replicas on the same node.
4. Create a PriorityClass `low` with value `10` that never preempts, and a Pod `background` that uses it.
5. On `k8s-lab-worker`, run a static Pod `node-agent` (image `busybox:1.36`, `sleep 3600`) in namespace `place`.

Check yourself:

```bash
kubectl describe node k8s-lab-worker2 | grep Taints                            # a NoSchedule taint
kubectl -n place get pod batch-job -o jsonpath='{.spec.nodeName}{"\n"}'        # k8s-lab-worker2
kubectl -n place get pods -l app=cache -o jsonpath='{.items[*].spec.nodeName}{"\n"}'   # two different nodes
kubectl get priorityclass low -o jsonpath='{.value} {.preemptionPolicy}{"\n"}' # 10 Never
kubectl -n place get pod node-agent-k8s-lab-worker                             # Running
```

Reset: remove the taint, delete the static Pod's file on the node, then `kubectl delete namespace place; kubectl delete priorityclass low`.

---

## Further reading

- [Taints and tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Assigning Pods to nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Pod priority and preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [Create static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)

## Next Lab

Proceed to **[[Kubernetes/labs/cka/10-operators-and-custom-resources|Lab CKA-10 — CRDs, Custom Resources & Operators]]**, or return to the [[Kubernetes/certifications/cka|CKA Track]].
