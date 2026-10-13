---
title: CKA Practice Set
tags: [kubernetes, certifications, cka, exam-prep, practice]
date: 2026-10-13
description: "A timed, mixed set of ten original CKA-style tasks with a setup script that breaks parts of the cluster, the state each task must reach, and a check for each one."
---

# CKA Practice Set

Ten tasks across the five CKA domains, weighted towards troubleshooting as the exam is. These are original practice tasks written for this wiki. They are **not** reconstructions of exam questions, and a score here is not a prediction of an exam result.

The setup script, a reference solution and the checks were run on kind v0.33.0 with Kubernetes v1.37.0 on 2026-10-13. Two tasks were changed after that run because they interfered with each other (a taint kept another task's Pod from scheduling, and a drain deleted another task's Pod); the versions below avoid that and their mechanisms are the ones tested in the labs, but the final ten have not been run together as one sitting.

Part of the [[Kubernetes/certifications/cka|CKA Track]].

> [!warning] This set breaks the control plane
> The setup damages the scheduler on the lab cluster's control-plane node. Use the throwaway cluster from [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]] and nothing you care about. If you cannot repair it, the reset at the bottom restores the saved manifest, and recreating the cluster always works.

---

## Rules

- **Time:** 100 minutes for the ten tasks.
- **Documentation:** only `kubernetes.io/docs`, `kubernetes.io/blog`, `helm.sh/docs` and `gateway-api.sigs.k8s.io`, as in the exam.
- **Do not open the labs** while the clock runs.
- **Hosts.** In the exam each task names a host to `ssh` to. Here, "on node X" means `docker exec -it X bash`, and you `exit` back before the next task. Tasks that name no node are done from your own terminal.
- Run the checks **after** time is up.

## Setup

```bash
cat << 'SETUP' > cka-setup.sh
for N in a1 a3 a4 a5 a6 a7 a8; do kubectl create namespace $N; done
docker exec k8s-lab-control-plane sh -c 'mkdir -p /root/backup/cka-mock && cp /etc/kubernetes/manifests/kube-scheduler.yaml /root/backup/cka-mock/ && sed -i "s#--kubeconfig=/etc/kubernetes/scheduler.conf#--kubeconfig=/etc/kubernetes/scheduler.config#" /etc/kubernetes/manifests/kube-scheduler.yaml'
docker exec k8s-lab-worker mkdir -p /mnt/reports
kubectl -n a5 create deployment web --image=ghcr.io/stefanprodan/podinfo:6.7.1
kubectl -n a6 create serviceaccount ci
kubectl -n a7 create deployment shop --image=ghcr.io/stefanprodan/podinfo:6.7.1 --port=9898 --replicas=2
kubectl -n a7 create service clusterip shop --tcp=80:9898
kubectl -n a7 patch deployment shop --type json -p '[{"op":"add","path":"/spec/template/spec/containers/0/readinessProbe","value":{"httpGet":{"path":"/ready","port":9898},"periodSeconds":3}}]'
kubectl -n a7 run client --image=curlimages/curl:8.10.1 --command -- sleep 7200
kubectl -n a8 create deployment api --image=ghcr.io/stefanprodan/podinfo:6.7.1 --replicas=3
kubectl -n a8 create poddisruptionbudget api --selector=app=api --min-available=3
SETUP
sh cka-setup.sh > /dev/null 2>&1
```

The etcd tools must be on the control-plane node, as they are in the exam. If you have not done [[Kubernetes/labs/cka/05-etcd-backup-restore|Lab CKA-05]] on this cluster, copy them first (this is preparation, not part of a task):

```bash
docker exec k8s-lab-control-plane sh -c \
  'for b in etcdctl etcdutl; do cp "$(find /var/lib/containerd -name $b -type f | head -1)" /usr/local/bin/; done'
```

Start the clock.

---

## Tasks

| #   | Where                        | Weight | Domain                   |
| :-- | :--------------------------- | :----- | :----------------------- |
| 1   | node `k8s-lab-control-plane` | 12     | Cluster Architecture     |
| 2   | node `k8s-lab-control-plane` | 14     | Troubleshooting          |
| 3   | namespace `a3`               | 10     | Storage                  |
| 4   | namespace `a4`               | 8      | Workloads and Scheduling |
| 5   | namespace `a5`               | 8      | Workloads and Scheduling |
| 6   | namespace `a6`               | 8      | Cluster Architecture     |
| 7   | namespace `a7`               | 12     | Troubleshooting          |
| 8   | namespace `a8`               | 8      | Workloads and Scheduling |
| 9   | node `k8s-lab-worker`        | 10     | Troubleshooting          |
| 10  | namespace `a1`               | 10     | Services and Networking  |

**Task 1.** On the control-plane node, save a snapshot of etcd to `/opt/backup/mock.db`. Write the snapshot's status, in JSON, to `/opt/backup/mock-status.json`. Take the endpoint and certificate paths from the cluster, not from memory.

**Task 2.** Users report that new Pods in every namespace stay `Pending` and show no events. Find the cause and repair it. Do not restore a backup file; fix what is wrong.

**Task 3 (`a3`).** A directory `/mnt/reports` exists on node `k8s-lab-worker`. Create a 2Gi PersistentVolume `reports-pv` for it with access mode `ReadWriteOnce`, class name `reports`, and a reclaim policy that keeps the data when the claim is deleted. Create a claim `reports` for 1Gi that binds to it, and a Pod `writer` (image `busybox:1.36`) that mounts the claim at `/data`, writes the current date to `/data/started` and then sleeps.

**Task 4 (`a4`).** Make node `k8s-lab-worker2` refuse new Pods that do not tolerate the taint `team=data`, without affecting Pods already running there. Then run a Pod `etl` (image `busybox:1.36`, command `sleep 3600`) that is guaranteed to run on that node.

**Task 5 (`a5`).** Autoscale Deployment `web` between 2 and 6 replicas at 60% CPU utilisation. The autoscaler must report a real utilisation figure, not `<unknown>`.

**Task 6 (`a6`).** ServiceAccount `ci` must be able to get, list, update and patch Deployments in namespace `a6`, and nothing else. Create what is needed.

**Task 7 (`a7`).** Pod `client` gets no answer from `http://shop/`. Find the cause and fix it so that both replicas of `shop` serve traffic.

**Task 8 (`a8`).** Deployment `api` has a PodDisruptionBudget. A node drain would currently be refused. Without changing or deleting the budget, make the workload able to lose one Pod to a voluntary disruption while at least 3 stay available.

**Task 9.** On node `k8s-lab-worker`, run a static Pod named `node-probe` in namespace `a1`, image `busybox:1.36`, command `sleep 3600`. Find the static Pod directory from the kubelet's configuration.

**Task 10 (`a1`).** Create a Deployment `front` with 2 replicas of `ghcr.io/stefanprodan/podinfo:6.7.1`, expose it inside the cluster as Service `front` on port 80, and write the fully qualified DNS name of the Service to `/tmp/front-dns.txt` on your machine. Then allow ingress to the `front` Pods on their container port only from Pods in namespaces labelled `access=front`.

---

## Checks

Stop the clock first. Award a task's weight only if every line matches.

```bash
# 1 (12): a file of several MB, and a totalKey count above zero
docker exec k8s-lab-control-plane sh -c 'ls -la /opt/backup/mock.db; grep -o "\"totalKey\":[0-9]*" /opt/backup/mock-status.json'

# 2 (14): Running, with the manifest fixed and not replaced by the backup
kubectl -n kube-system get pod kube-scheduler-k8s-lab-control-plane -o jsonpath='{.status.phase}{"\n"}'
docker exec k8s-lab-control-plane grep -c "scheduler.conf$" /etc/kubernetes/manifests/kube-scheduler.yaml   # 1 or more
kubectl get pods -A --field-selector=status.phase=Pending --no-headers | wc -l    # 0

# 3 (10): Bound reports-pv, Retain, and a date
kubectl -n a3 get pvc reports -o jsonpath='{.status.phase} {.spec.volumeName}{"\n"}'
kubectl get pv reports-pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy} {.spec.capacity.storage}{"\n"}'
docker exec k8s-lab-worker cat /mnt/reports/started

# 4 (8): k8s-lab-worker2 Running, and a NoSchedule taint team=data
kubectl -n a4 get pod etl -o jsonpath='{.spec.nodeName} {.status.phase}{"\n"}'
kubectl get node k8s-lab-worker2 -o jsonpath='{.spec.taints}{"\n"}'

# 5 (8): 2 6 60, and a TARGETS value with a number in it
kubectl -n a5 get hpa web -o jsonpath='{.spec.minReplicas} {.spec.maxReplicas} {.spec.metrics[0].resource.target.averageUtilization}{"\n"}'
kubectl -n a5 get hpa web

# 6 (8): yes, yes, no, no, no
for q in "patch deployments" "list deployments" "delete deployments" "get secrets" "get pods"; do
  printf '%-20s' "$q"; kubectl auth can-i $(echo $q) -n a6 --as=system:serviceaccount:a6:ci
done
kubectl auth can-i list deployments -n default --as=system:serviceaccount:a6:ci    # no

# 7 (12): 200, and 2 ready replicas
kubectl -n a7 exec client -- curl -s -m 4 -o /dev/null -w '%{http_code}\n' http://shop/
kubectl -n a7 get deployment shop -o jsonpath='{.status.readyReplicas}{"\n"}'

# 8 (8): minAvailable still 3, allowed disruptions 1 or more
kubectl -n a8 get pdb api -o jsonpath='{.spec.minAvailable} {.status.disruptionsAllowed}{"\n"}'

# 9 (10): Running, owned by the Node
kubectl -n a1 get pod node-probe-k8s-lab-worker -o jsonpath='{.status.phase} {.metadata.ownerReferences[0].kind}{"\n"}'

# 10 (10): 2; front.a1.svc.cluster.local; a policy whose only "from" is a namespaceSelector on access=front
kubectl -n a1 get deployment front -o jsonpath='{.status.readyReplicas}{"\n"}'
cat /tmp/front-dns.txt
kubectl -n a1 get networkpolicy -o jsonpath='{.items[0].spec.ingress[0].from}{" "}{.items[0].spec.ingress[0].ports}{"\n"}'
```

For task 10, also test the behaviour rather than trusting the object: a Pod in a namespace labelled `access=front` must reach `http://front.a1/`, and a Pod in `default` must time out.

The CKA pass mark is 66%. Record your score, the time used and which tasks you flagged.

---

## Review

Task 2 comes first in practice whatever order you chose, because nothing else schedules until it is fixed. Noticing that, from `Pending` Pods with no events, is part of the task.

| What happened                               | What to do                                              |
| :------------------------------------------ | :------------------------------------------------------ |
| Did not know the mechanism                  | Go back to the lab in the table below                   |
| Knew it, could not find the syntax in time  | Practise finding that page in the allowed documentation |
| Right object, wrong namespace, node or path | Read the task twice before typing                       |
| Thought it was done; the check disagreed    | Verify before moving on, every time                     |
| Ran out of time                             | Repeat in a week and note which tasks took longest      |

| Task | Lab                                                                                                                                     |
| :--- | :-------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | [[Kubernetes/labs/cka/05-etcd-backup-restore\|Lab CKA-05]]                                                                              |
| 2    | [[Kubernetes/labs/cka/07-control-plane-and-kubelet-repair\|Lab CKA-07]]                                                                 |
| 3    | [[Kubernetes/labs/cka/01-storage-and-persistence\|Lab CKA-01]]                                                                          |
| 4, 9 | [[Kubernetes/labs/cka/09-scheduling-constraints\|Lab CKA-09]]                                                                           |
| 5    | [[Kubernetes/labs/cka/08-autoscaling-with-hpa\|Lab CKA-08]]                                                                             |
| 6    | [[Kubernetes/labs/cks/13-rbac-remediation\|Lab CKS-13]], [[Kubernetes/labs/cka/06-users-and-certificate-requests\|Lab CKA-06]]          |
| 7    | [[Kubernetes/labs/cka/11-service-and-dns-troubleshooting\|Lab CKA-11]]                                                                  |
| 8    | [[Kubernetes/labs/cka/02-scheduling-and-autoscaling\|Lab CKA-02]]                                                                       |
| 10   | [[Kubernetes/labs/ckad/05-services-and-dns\|Lab CKAD-05]], [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]] section 7 |

A set you have already seen measures memory as much as skill. Before repeating it, change the names, nodes and numbers, or have someone else do so. The `kubeadm` install and upgrade objectives are not in this set, because they need virtual machines; rehearse them separately with [[Kubernetes/labs/cka/03-kubeadm-cluster-install|Lab CKA-03]] and [[Kubernetes/labs/cka/04-kubeadm-upgrade|Lab CKA-04]].

## Reset

```bash
kubectl taint node k8s-lab-worker2 team=data:NoSchedule- 2>/dev/null
docker exec k8s-lab-worker sh -c 'rm -f /etc/kubernetes/manifests/node-probe.yaml; rm -rf /mnt/reports'
kubectl delete namespace a1 a3 a4 a5 a6 a7 a8
kubectl delete pv reports-pv
docker exec k8s-lab-control-plane sh -c \
  'grep -q scheduler.config /etc/kubernetes/manifests/kube-scheduler.yaml && cp /root/backup/cka-mock/kube-scheduler.yaml /etc/kubernetes/manifests/; rm -rf /opt/backup /root/backup/cka-mock'
rm -f cka-setup.sh /tmp/front-dns.txt
kubectl get nodes
```

If your static Pod's manifest has a different file name, remove that file instead. Adjust the name in the first `docker exec` line.
