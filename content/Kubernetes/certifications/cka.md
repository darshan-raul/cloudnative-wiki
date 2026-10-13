---
title: CKA Track
tags: [kubernetes, certifications, cka, exam-prep]
date: 2026-10-13
description: "Certified Kubernetes Administrator study track mapping every exam objective to the concept notes, guides and labs in this wiki, with task drills and known gaps."
---

# CKA Track

The Certified Kubernetes Administrator exam tests whether you can install, operate and repair a cluster. Compared with the CKAD it adds `kubeadm`, etcd, node-level work over `ssh`, and a troubleshooting domain worth almost a third of the score.

Exam format, shell setup and time management are in the [[Kubernetes/certifications/index|Certifications hub]]. This page covers what to study.

| Domain                                               | Weight | Practice in this wiki                                                                                      |
| :--------------------------------------------------- | :----- | :--------------------------------------------------------------------------------------------------------- |
| Troubleshooting                                      | 30%    | Lab + practice for nodes, control plane components, Services and DNS                                       |
| Cluster Architecture, Installation and Configuration | 25%    | Mixed: etcd, RBAC, Helm and operators are lab + practice; `kubeadm` install is not run; HA is reading only |
| Services and Networking                              | 20%    | Lab + practice, including Gateway API and unguided fault-finding                                           |
| Workloads and Scheduling                             | 15%    | Lab + practice, including HPA and scheduling constraints                                                   |
| Storage                                              | 10%    | Lab + practice; volume expansion cannot be exercised on the lab's provisioner                              |

The third column says what kind of practice exists, using the labels defined in the [[Kubernetes/certifications/index#what-the-coverage-labels-mean|hub]]. It is not a readiness score.

Objective wording follows the Linux Foundation CKA page as checked on 2026-10-13 (exam on Kubernetes v1.35; this wiki's baseline is 1.37 and the labs were run on v1.37.0). [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]] shows how to create the practice cluster on v1.35 instead. The differences that touch these labs are small: v1.35 ships etcd 3.6 where v1.37 ships 3.7, with the same `etcdctl` and `etcdutl` commands.

> [!note] Where the labs run
> Most labs use the `kind` cluster built in [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]], including the etcd, certificate and control plane repair labs, which reach the node with `docker exec` in place of `ssh`. Only the `kubeadm` install and upgrade labs need real or virtual machines. The install lab has not been run on machines; the upgrade lab's command sequence was run on a kind cluster (v1.36.4 to v1.37.0). Each lab states what was and was not executed.

---

## Prerequisites

- [[Kubernetes/concepts/L01-architecture/00-README|L01 Architecture]] and [[Kubernetes/concepts/L01-architecture/06-what-happens-when|What Happens When You kubectl apply]], so you know which component to suspect.
- [[Kubernetes/review/architecture-refresher|Architecture refresher]] as a check that the request flow is clear.
- [[Kubernetes/guides/tools/kubectl|kubectl]] and [[Kubernetes/guides/tools/context-switching|Context Switching]].
- Linux basics the node tasks assume: [[Linux/boot-init/systemd|systemd]] (`systemctl`, `journalctl`), [[Linux/networking/ss|ss]] and [[Linux/networking/iptables|iptables]].
- If you have not done the CKAD, work through the [[Kubernetes/certifications/ckad|CKAD Track]] drills for workloads and configuration first.

---

## 1. Troubleshooting (30%)

| Objective                                      | Read                                                                                                                                                                                                                                                                                                                          | Practise                                                                                                                                     |
| :--------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------- |
| Troubleshoot clusters and nodes                | [[Kubernetes/guides/troubleshooting/node-not-ready\|Node Not Ready]], [[Kubernetes/concepts/L08-operations/01-troubleshooting\|Troubleshooting Flow]], [[Containers/runtimes\|Container Runtimes]]                                                                                                                            | [[Kubernetes/labs/cka/07-control-plane-and-kubelet-repair\|Lab CKA-07]], [[Kubernetes/labs/ckad/01-cluster-setup\|Lab CKAD-01]]              |
| Troubleshoot cluster components                | [[Kubernetes/concepts/L03-workloads/11-static-pods\|Static Pods]], [[Kubernetes/concepts/L09-advanced/10-etcd\|etcd in Kubernetes]], [[Kubernetes/concepts/L07-security/01-api-access/04-certificates\|Certificates]], [[Kubernetes/concepts/L06-scheduling-scaling/12-scheduler-internals\|Scheduler Internals]]             | [[Kubernetes/labs/cka/07-control-plane-and-kubelet-repair\|Lab CKA-07]], [[Kubernetes/labs/cka/05-etcd-backup-restore\|Lab CKA-05]]          |
| Monitor cluster and application resource usage | [[Kubernetes/concepts/L08-operations/04-metrics-sources\|Metrics Sources]]                                                                                                                                                                                                                                                    | [[Kubernetes/labs/ckad/06-observability-and-troubleshooting\|Lab CKAD-06]], [[Kubernetes/labs/cka/08-autoscaling-with-hpa\|Lab CKA-08]]      |
| Manage and evaluate container output streams   | [[Kubernetes/concepts/L08-operations/02-kubectl-debug\|kubectl Debug Toolkit]], [[Kubernetes/guides/troubleshooting/crashloop-backoff\|CrashLoopBackOff]]                                                                                                                                                                     | [[Kubernetes/labs/ckad/06-observability-and-troubleshooting\|Lab CKAD-06]]                                                                   |
| Troubleshoot services and networking           | [[Kubernetes/guides/troubleshooting/service-unreachable\|Service Unreachable]], [[Kubernetes/guides/troubleshooting/dns-resolution\|DNS Resolution Failures]], [[Kubernetes/guides/troubleshooting/ingress-404\|Ingress 404 / 502 / 503]], [[Kubernetes/concepts/L04-services-networking/08-endpoint-slices\|EndpointSlices]] | [[Kubernetes/labs/cka/11-service-and-dns-troubleshooting\|Lab CKA-11]] (unguided), [[Kubernetes/labs/ckad/05-services-and-dns\|Lab CKAD-05]] |

Also read [[Kubernetes/concepts/L08-operations/03-common-failure-modes|Common Failure Modes]], [[Kubernetes/guides/troubleshooting/pod-pending|Pod Pending]], [[Kubernetes/guides/troubleshooting/image-pull|ImagePullBackOff]] and the [[Kubernetes/review/scenarios|Scenario-Based Incident Reviews]], which are the closest thing in the wiki to exam-shaped tasks.

**Task drills**

- [ ] A node is `NotReady`. Over `ssh`, find out why from `systemctl status kubelet` and `journalctl -u kubelet`, and fix it. Practise at least these causes: kubelet stopped, wrong path in the kubelet config, wrong CA file, container runtime down.
- [ ] The API server is unreachable. Find the broken flag in `/etc/kubernetes/manifests/kube-apiserver.yaml` using `crictl ps -a` and `crictl logs`, since `kubectl` is not available.
- [ ] Pods stay `Pending` with no events. Find and fix a broken `kube-scheduler` static Pod manifest.
- [ ] A Deployment does not scale. Find and fix a broken `kube-controller-manager`.
- [ ] Write the name of the Pod using the most memory across all namespaces to a file (`kubectl top pod -A --sort-by=memory`).
- [ ] Extract every `ERROR` line from one container of a multi-container Pod into a file.
- [ ] A Service returns nothing. Work through selector, endpoints, `targetPort`, NetworkPolicy and kube-proxy in that order.
- [ ] DNS fails cluster-wide. Check the CoreDNS Pods, the `kube-dns` Service and the Corefile ConfigMap.

---

## 2. Cluster Architecture, Installation and Configuration (25%)

| Objective                                                  | Read                                                                                                                                                                                                                                                                                                           | Practise                                                                                                                                     |
| :--------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------- |
| Manage role based access control (RBAC)                    | [[Kubernetes/concepts/L07-security/01-api-access/03-rbac\|RBAC]], [[Kubernetes/concepts/L07-security/01-api-access/02-service-accounts\|Service Accounts]], [[Kubernetes/concepts/L07-security/01-api-access/01-authentication-authorization\|Authentication vs Authorization]]                                | [[Kubernetes/labs/cka/06-users-and-certificate-requests\|Lab CKA-06]], [[Kubernetes/labs/cks/13-rbac-remediation\|Lab CKS-13]]               |
| Prepare underlying infrastructure for installing a cluster | [[Kubernetes/concepts/L01-architecture/01-setting-up-cluster\|Setting up a Cluster]], [[Kubernetes/concepts/L01-architecture/05-need-for-swapoff\|Memory Swap and NodeSwap]], [[Containers/runtimes\|Container Runtimes]], [[Linux/security/sysctl\|sysctl]]                                                   | [[Kubernetes/labs/cka/03-kubeadm-cluster-install\|Lab CKA-03]] (package steps run; rest not run)                                             |
| Create and manage Kubernetes clusters using kubeadm        | [[Kubernetes/concepts/L01-architecture/01-setting-up-cluster\|Setting up a Cluster]]                                                                                                                                                                                                                           | [[Kubernetes/labs/cka/03-kubeadm-cluster-install\|Lab CKA-03]] (not run on VMs)                                                              |
| Manage the lifecycle of Kubernetes clusters                | [[Kubernetes/guides/non-functional/upgrade-strategy\|Upgrade Strategy]], [[Kubernetes/guides/non-functional/backup-restore\|Backup and Restore]], [[Kubernetes/concepts/L09-advanced/10-etcd\|etcd in Kubernetes]], [[Kubernetes/concepts/L06-scheduling-scaling/04-poddisruptionbudget\|PodDisruptionBudget]] | [[Kubernetes/labs/cka/04-kubeadm-upgrade\|Lab CKA-04]] (run on kind, not on VMs), [[Kubernetes/labs/cka/05-etcd-backup-restore\|Lab CKA-05]] |
| Implement and configure a highly-available control plane   | [[Kubernetes/concepts/L01-architecture/02-high-availability\|High Availability]], [[Kubernetes/guides/non-functional/high-availability\|High Availability (guide)]]                                                                                                                                            | Reading only                                                                                                                                 |
| Use Helm and Kustomize to install cluster components       | [[Kubernetes/guides/delivery/templating-patching/helm/README\|Helm]], [[Kubernetes/guides/delivery/templating-patching/helm/commands\|Helm Commands]], [[Kubernetes/guides/delivery/templating-patching/kustomize\|Kustomize]]                                                                                 | [[Kubernetes/labs/ckad/11-helm-release-lifecycle\|Lab CKAD-11]], [[Kubernetes/labs/ckad/07-kustomize-and-lifecycle\|Lab CKAD-07]]            |
| Understand extension interfaces (CNI, CSI, CRI)            | [[Kubernetes/concepts/L04-services-networking/06-cni\|CNI]], [[Kubernetes/review/storage-refresher\|Storage and CSI refresher]], [[Containers/runtimes\|Container Runtimes]]                                                                                                                                   | Reading only                                                                                                                                 |
| Understand CRDs, install and configure operators           | [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions\|CustomResourceDefinitions]], [[Kubernetes/concepts/L09-advanced/01-operators\|Operators]]                                                                                                                                                     | [[Kubernetes/labs/cka/10-operators-and-custom-resources\|Lab CKA-10]]                                                                        |

The upgrade guide uses older version numbers in its examples. The sequence is what matters; substitute the version the task gives you.

**Task drills**

- [ ] Create a ClusterRole and bind it to a ServiceAccount in one namespace with a RoleBinding, then verify with `kubectl auth can-i --as`.
- [ ] Create a user from scratch: generate a key and CSR with `openssl`, submit a CertificateSigningRequest, approve it with `kubectl certificate approve`, build a kubeconfig entry, and grant the user a Role.
- [ ] Prepare a fresh node: load `overlay` and `br_netfilter`, set the forwarding sysctls, install and configure containerd with the systemd cgroup driver, install `kubeadm`, `kubelet` and `kubectl` at a pinned version.
- [ ] Initialise a control plane with `kubeadm init`, install a CNI, and join a worker using `kubeadm token create --print-join-command`.
- [ ] Upgrade a control plane node one minor version: upgrade `kubeadm`, run `kubeadm upgrade plan` and `apply`, drain, upgrade `kubelet` and `kubectl`, restart the kubelet, uncordon. Then upgrade a worker with `kubeadm upgrade node`.
- [ ] Take an etcd snapshot with the certificate paths read from the etcd static Pod manifest, then restore it to a new data directory and point the manifest at it.
- [ ] Check certificate expiry with `kubeadm certs check-expiration` and renew one certificate.
- [ ] Install a component from a Helm chart with custom values, and from a Kustomize directory.
- [ ] Install an operator from its manifests, list the CRDs it adds, and create one custom resource.
- [ ] Drain a node that hosts a Pod protected by a PodDisruptionBudget and a bare Pod, and explain each flag you needed.

---

## 3. Services and Networking (20%)

| Objective                                                         | Read                                                                                                                                                                                                                                               | Practise                                                                                                                                             |
| :---------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------- |
| Understand connectivity between Pods                              | [[Kubernetes/concepts/L04-services-networking/01-networking\|Networking Overview]], [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive\|Networking Deep Dive]], [[Kubernetes/concepts/L04-services-networking/06-cni\|CNI]] | [[Kubernetes/labs/ckad/05-services-and-dns\|Lab CKAD-05]]                                                                                            |
| Define and enforce Network Policies                               | [[Kubernetes/concepts/L04-services-networking/05-network-policy\|NetworkPolicy]]                                                                                                                                                                   | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]] section 7, [[Kubernetes/labs/cka/11-service-and-dns-troubleshooting\|Lab CKA-11]] |
| Use ClusterIP, NodePort, LoadBalancer service types and endpoints | [[Kubernetes/concepts/L04-services-networking/02-services\|Services]], [[Kubernetes/concepts/L04-services-networking/08-endpoint-slices\|EndpointSlices]]                                                                                          | [[Kubernetes/labs/ckad/05-services-and-dns\|Lab CKAD-05]]                                                                                            |
| Use the Gateway API to manage Ingress traffic                     | [[Kubernetes/concepts/L04-services-networking/09-gateway-api\|Gateway API]], [[Kubernetes/concepts/L04-services-networking/gateway-api-lab/RUNBOOK\|Gateway API lab runbook]]                                                                      | [[Kubernetes/labs/cka/12-gateway-api\|Lab CKA-12]]                                                                                                   |
| Know how to use Ingress controllers and Ingress resources         | [[Kubernetes/concepts/L04-services-networking/04-ingress\|Ingress]]                                                                                                                                                                                | [[Kubernetes/labs/ckad/09-ingress\|Lab CKAD-09]]                                                                                                     |
| Understand and use CoreDNS                                        | [[Kubernetes/concepts/L04-services-networking/03-dns\|DNS in Kubernetes]], [[Kubernetes/guides/troubleshooting/dns-resolution\|DNS Resolution Failures]]                                                                                           | [[Kubernetes/labs/ckad/05-services-and-dns\|Lab CKAD-05]], [[Kubernetes/labs/cka/11-service-and-dns-troubleshooting\|Lab CKA-11]] section 5          |

Finish with the [[Kubernetes/review/networking-refresher|Networking refresher]].

**Task drills**

- [ ] Expose a Deployment as NodePort on a specific port and reach it from outside the cluster through a node IP.
- [ ] Write a NetworkPolicy that combines a `namespaceSelector` and a `podSelector` in one rule, then a second policy that lists them as separate rules, and explain the difference.
- [ ] Add a default-deny for ingress and egress in a namespace and restore DNS with an explicit egress rule.
- [ ] Create a Gateway and an HTTPRoute that routes two paths to two Services. Then migrate an existing Ingress to an equivalent HTTPRoute.
- [ ] Create an Ingress with a specific `ingressClassName`, a host rule and a path rule.
- [ ] Resolve a Service and a Pod by full DNS name from a temporary Pod, in the same namespace and across namespaces.
- [ ] Change the CoreDNS Corefile to forward one domain to a custom upstream, and confirm the Pods reloaded it.

---

## 4. Workloads and Scheduling (15%)

| Objective                                                      | Read                                                                                                                                                                                                                                                                                                                                                                                    | Practise                                                                                                                                                                                                  |
| :------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Understand deployments, rolling updates and rollbacks          | [[Kubernetes/concepts/L03-workloads/03-deployments\|Deployments]]                                                                                                                                                                                                                                                                                                                       | [[Kubernetes/labs/ckad/03-updates-and-rollbacks\|Lab CKAD-03]]                                                                                                                                            |
| Use ConfigMaps and Secrets to configure applications           | [[Kubernetes/concepts/L05-config-storage/01-config-maps\|ConfigMaps]], [[Kubernetes/concepts/L05-config-storage/02-secrets\|Secrets]]                                                                                                                                                                                                                                                   | [[Kubernetes/labs/ckad/04-configuration\|Lab CKAD-04]]                                                                                                                                                    |
| Configure workload autoscaling                                 | [[Kubernetes/concepts/L06-scheduling-scaling/03-horizontalpodautoscaler\|HorizontalPodAutoscaler]], [[Kubernetes/concepts/L06-scheduling-scaling/07-vertical-pod-autoscaler\|Vertical Pod Autoscaler]]                                                                                                                                                                                  | [[Kubernetes/labs/cka/08-autoscaling-with-hpa\|Lab CKA-08]]                                                                                                                                               |
| Understand the primitives for robust, self-healing deployments | [[Kubernetes/concepts/L03-workloads/10-probes\|Probes]], [[Kubernetes/concepts/L03-workloads/02-replicaset\|ReplicaSet]], [[Kubernetes/concepts/L03-workloads/05-daemonset\|DaemonSet]], [[Kubernetes/concepts/L03-workloads/04-statefulsets\|StatefulSets]], [[Kubernetes/concepts/L06-scheduling-scaling/06-restart-policy\|Restart Policy]]                                          | [[Kubernetes/labs/ckad/13-quotas-limit-ranges-and-probes\|Lab CKAD-13]] (probes), [[Kubernetes/labs/ckad/02-deploy-workload\|Lab CKAD-02]]                                                                |
| Configure Pod admission and scheduling (limits, node affinity) | [[Kubernetes/concepts/L06-scheduling-scaling/02-scheduling\|Scheduling]], [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|Resource Requests and Limits]], [[Kubernetes/concepts/L06-scheduling-scaling/11-priority-and-preemption\|PriorityClass and Preemption]], [[Kubernetes/concepts/L05-config-storage/08-resource-quota\|ResourceQuota and LimitRange]] | [[Kubernetes/labs/cka/02-scheduling-and-autoscaling\|Lab CKA-02]], [[Kubernetes/labs/cka/09-scheduling-constraints\|Lab CKA-09]], [[Kubernetes/labs/ckad/13-quotas-limit-ranges-and-probes\|Lab CKAD-13]] |

Finish with the [[Kubernetes/review/scheduling-scaling-refresher|Scheduling and Scaling refresher]].

**Task drills**

- [ ] Create an HPA on CPU with a minimum, a maximum and a custom scale-down stabilisation window.
- [ ] Taint a node, then schedule a Pod onto it with a matching toleration and a `nodeSelector`.
- [ ] Use required node affinity to pin a Deployment to labelled nodes, and Pod anti-affinity to spread its replicas across nodes.
- [ ] Create a PriorityClass, assign it to a Deployment, and watch it preempt a lower-priority Pod on a full node.
- [ ] Run a static Pod on a worker node by placing a manifest in the kubelet's static Pod path.
- [ ] Schedule a Pod manually by setting `nodeName` while the scheduler is down.
- [ ] Resize a container's CPU request in place without restarting the Pod.

---

## 5. Storage (10%)

| Objective                                                 | Read                                                                                                                                                   | Practise                                                       |
| :-------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------- |
| Implement storage classes and dynamic volume provisioning | [[Kubernetes/concepts/L05-config-storage/06-storageclass\|StorageClass]], [[Kubernetes/concepts/L05-config-storage/07-storage\|Storage Overview]]      | [[Kubernetes/labs/cka/01-storage-and-persistence\|Lab CKA-01]] |
| Configure volume types, access modes and reclaim policies | [[Kubernetes/concepts/L05-config-storage/03-volumes\|Volume Types]], [[Kubernetes/concepts/L05-config-storage/04-persistentvolume\|PersistentVolume]]  | [[Kubernetes/labs/cka/01-storage-and-persistence\|Lab CKA-01]] |
| Manage persistent volumes and persistent volume claims    | [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim\|PersistentVolumeClaim]], [[Kubernetes/guides/troubleshooting/pvc-stuck\|PVC Stuck]] | [[Kubernetes/labs/cka/01-storage-and-persistence\|Lab CKA-01]] |

Finish with the [[Kubernetes/review/storage-refresher|Storage refresher]].

**Task drills**

- [ ] Create a `hostPath` PersistentVolume and a PVC that binds to it specifically, matching capacity, access mode and `storageClassName`.
- [ ] Create a StorageClass with `volumeBindingMode: WaitForFirstConsumer` and `allowVolumeExpansion: true`, make it the default, and expand a bound PVC.
- [ ] Change a PV's reclaim policy to `Retain`, delete its PVC, and make the `Released` volume bindable again.
- [ ] Diagnose a PVC stuck in `Pending` from its events.

---

## Gaps in the wiki

| Objective                            | What is missing                                                                                                                                 | Use instead                                                                                                           |
| :----------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------- |
| `kubeadm` install                    | Lab CKA-03: only the package installation was run (in a container). `kubeadm init`, the CNI install and `kubeadm join` were not run on machines | Run it on three virtual machines and treat the lab's output as a description                                          |
| `kubeadm` upgrade                    | Lab CKA-04: the `kubeadm` and drain sequence was run on kind and the apt steps in a container, never together on machines                       | The same three machines, straight after Lab CKA-03                                                                    |
| Highly-available control plane       | Reading only. A three-control-plane cluster was too heavy for this wiki's test machine, so no lab was written                                   | [HA clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)  |
| Volume expansion                     | Lab CKA-01 shows the refusal; the lab's provisioner cannot expand a volume                                                                      | [Expanding PVCs](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#expanding-persistent-volumes-claims) |
| Extension interfaces (CNI, CSI, CRI) | Reading only, plus the `cri-dockerd` outline in Lab CKA-03                                                                                      | The concept notes in the domain 2 table                                                                               |
| Node-level network faults            | Lab CKA-11 covers Service, DNS and policy faults, not a broken CNI or `kube-proxy`                                                              | [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)                             |
| Independent grading                  | The practice tasks give checks you run yourself; nothing scores you automatically                                                               | The exam simulator, if your registration includes it                                                                  |

---

## Study plan

The plan below is a **revision schedule for someone who passes the [[Kubernetes/certifications/index#before-you-start-a-track|entry check]]** and is comfortable in a Linux shell, at about an hour a day. It does not include provisioning virtual machines for the `kubeadm` labs; allow an extra evening or two for that. Finishing it is not a pass prediction.

The weeks follow the exam's weights loosely: most of the last two go to troubleshooting, which is 30% of the score.

| Week | Focus                                                                                                                          | Labs                                                                   |
| :--- | :----------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------- |
| 1    | Prerequisites, workloads and configuration                                                                                     | CKAD-01, 02, 03, 04, 13                                                |
| 2    | Scheduling, autoscaling, storage                                                                                               | CKA-01, 02, 08, 09                                                     |
| 3    | Services and networking                                                                                                        | CKAD-05, 09, CKA-12, CKS-01 section 7                                  |
| 4    | Cluster lifecycle, RBAC, Helm, operators                                                                                       | CKA-03, 04 (on machines if you have them), 05, 06, 10, CKAD-11, CKS-13 |
| 5    | Troubleshooting                                                                                                                | CKAD-06, CKA-07, CKA-11; then repeat CKA-07 and CKA-11 unguided        |
| 6    | Every "Practice Without the Answer" section again; the timed practice set; weak spots; the simulator sessions if you have them | [[Kubernetes/certifications/cka-mock-exam\|CKA practice set]]          |

## Ready when

- [ ] You can upgrade a node and restore etcd with only the allowed documentation open, and you check that the restored data and the cluster's components are healthy afterwards.
- [ ] You can find a broken control plane component with `crictl` and `journalctl` when `kubectl` does not answer.
- [ ] You diagnose the faults in [[Kubernetes/labs/cka/11-service-and-dns-troubleshooting|Lab CKA-11]] from evidence, without the answers, on a second attempt some days after the first.
- [ ] You finish the [[Kubernetes/certifications/cka-mock-exam|CKA practice set]] inside two hours at or above the pass mark.
- [ ] If you have the simulator, your second session is at or above the pass mark.

Time targets depend on the task. Creating a Secret takes a minute; restoring etcd or upgrading a node takes ten or more even when it goes well. Judge yourself on correct, verified results inside the two hours as a whole, not on one number per task.

## Further reading

- [CKA curriculum](https://github.com/cncf/curriculum)
- [CKA exam page](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/)
- [kubeadm reference](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [Gateway API documentation](https://gateway-api.sigs.k8s.io/)

## Across the wiki

- [[Kubernetes/certifications/ckad|CKAD Track]]: workload and configuration drills shared with this exam.
- [[Kubernetes/certifications/cks|CKS Track]]: the next exam, which requires a passed CKA.
- [[Kubernetes/MAINTENANCE|Maintenance Playbook]]: how this wiki tracks upstream Kubernetes releases.
- [[Linux/troubleshooting/systematic-debugging|Systematic Debugging]]: the Linux side of node troubleshooting.
