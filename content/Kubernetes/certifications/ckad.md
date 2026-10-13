---
title: CKAD Track
tags: [kubernetes, certifications, ckad, exam-prep]
date: 2026-10-13
description: "Certified Kubernetes Application Developer study track mapping every exam objective to the concept notes, guides and labs in this wiki, with task drills and known gaps."
---

# CKAD Track

The Certified Kubernetes Application Developer exam tests whether you can design, deploy, configure and debug applications on a cluster somebody else runs. There is no cluster installation and almost no node access. Speed with `kubectl` decides the result more than depth of knowledge.

Exam format, shell setup and time management are in the [[Kubernetes/certifications/index|Certifications hub]]. This page covers what to study.

| Domain                                              | Weight | Practice in this wiki                                                       |
| :-------------------------------------------------- | :----- | :-------------------------------------------------------------------------- |
| Application Design and Build                        | 20%    | Lab + practice for images, Jobs, CronJobs, multi-container Pods and volumes |
| Application Deployment                              | 20%    | Lab + practice for rolling updates, blue/green, canary, Helm and Kustomize  |
| Application Observability and Maintenance           | 15%    | Lab + practice for probes, logs, debugging and API deprecations             |
| Application Environment, Configuration and Security | 25%    | Lab + practice for most objectives; admission control is reading only       |
| Services and Networking                             | 20%    | Lab + practice for Services, NetworkPolicy and Ingress                      |

The third column says what kind of practice exists, using the labels defined in the [[Kubernetes/certifications/index#what-the-coverage-labels-mean|hub]]. It is not a readiness score. All CKAD labs were run on Kubernetes v1.37.0, the version the exam used on the check date.

Objective wording follows the Linux Foundation CKAD page as checked on 2026-10-13 (exam on Kubernetes v1.37, the same as this wiki's baseline).

---

## Prerequisites

Work through these once before starting the domains:

- [[Kubernetes/concepts/L00-start-here/00-start-here|L00 Start Here]] and [[Kubernetes/concepts/L02-objects/01-kubernetes-objects|Kubernetes Objects]] for the object model, labels and selectors.
- [[Kubernetes/concepts/L01-architecture/03-namespaces|Namespaces]], since almost every task names one.
- [[Kubernetes/guides/tools/kubectl|kubectl]] and [[Kubernetes/guides/tools/context-switching|Context Switching]].
- [[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01 Cluster Setup]] to get the practice cluster running.

---

## 1. Application Design and Build (20%)

| Objective                                      | Read                                                                                                                                                                                                                                                                                                                  | Practise                                                                                                                                                                                                       |
| :--------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Define, build and modify container images      | [[Containers/dockerfile-best-practices\|Dockerfile Best Practices]], [[Containers/images-and-layers\|Images and Layers]], [[Containers/registries\|Registries]]                                                                                                                                                       | [[Kubernetes/labs/ckad/08-build-and-ship-images\|Lab CKAD-08]]                                                                                                                                                 |
| Choose and use the right workload resource     | [[Kubernetes/concepts/L03-workloads/03-deployments\|Deployments]], [[Kubernetes/concepts/L03-workloads/05-daemonset\|DaemonSet]], [[Kubernetes/concepts/L03-workloads/04-statefulsets\|StatefulSets]], [[Kubernetes/concepts/L03-workloads/06-job\|Jobs]], [[Kubernetes/concepts/L03-workloads/07-cronjob\|CronJobs]] | [[Kubernetes/labs/ckad/02-deploy-workload\|Lab CKAD-02]] (Deployment), [[Kubernetes/labs/ckad/10-jobs-cronjobs-and-multi-container-pods\|Lab CKAD-10]] (Job, CronJob). DaemonSet and StatefulSet: reading only |
| Understand multi-container Pod design patterns | [[Kubernetes/concepts/L03-workloads/09-multi-container-pods\|Multi-Container Pods]], [[Kubernetes/concepts/L03-workloads/08-init-containers\|Init Containers]], [[Kubernetes/concepts/L03-workloads/01-pods\|Pods]]                                                                                                   | [[Kubernetes/labs/ckad/10-jobs-cronjobs-and-multi-container-pods\|Lab CKAD-10]]                                                                                                                                |
| Utilize persistent and ephemeral volumes       | [[Kubernetes/concepts/L05-config-storage/03-volumes\|Volume Types]], [[Kubernetes/concepts/L05-config-storage/05-persistentvolumeclaim\|PersistentVolumeClaim]], [[Kubernetes/concepts/L05-config-storage/06-storageclass\|StorageClass]]                                                                             | [[Kubernetes/labs/cka/01-storage-and-persistence\|Lab CKA-01]]                                                                                                                                                 |

**Task drills**

- [ ] Build an image from a given Dockerfile with a specific tag, then export it to a tar archive in OCI format (`docker build` and `docker save`, or the `podman` equivalents).
- [ ] Change the base image or `CMD` in a Dockerfile, rebuild, and run a Pod from the new tag.
- [ ] Create a Job with `completions: 5`, `parallelism: 2` and a `backoffLimit`, then read its Pod logs.
- [ ] Create a CronJob that runs every two minutes, keeps three successful runs and has `activeDeadlineSeconds` set. Trigger it manually with `kubectl create job --from=cronjob/<name>`.
- [ ] Add a sidecar that tails a log file written by the main container through a shared `emptyDir`.
- [ ] Add an init container that blocks until a Service resolves in DNS.
- [ ] Create a PVC, mount it in a Pod, write a file, delete the Pod, and confirm the file survives in a new Pod.

---

## 2. Application Deployment (20%)

| Objective                                                   | Read                                                                                                                                                                   | Practise                                                         |
| :---------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------- |
| Implement common deployment strategies (blue/green, canary) | [[Kubernetes/guides/delivery/progressive-delivery/strategies\|Progressive Delivery Strategies]], [[Kubernetes/concepts/L04-services-networking/02-services\|Services]] | [[Kubernetes/labs/ckad/12-blue-green-and-canary\|Lab CKAD-12]]   |
| Understand Deployments and how to perform rolling updates   | [[Kubernetes/concepts/L03-workloads/03-deployments\|Deployments]], [[Kubernetes/concepts/L03-workloads/02-replicaset\|ReplicaSet]]                                     | [[Kubernetes/labs/ckad/03-updates-and-rollbacks\|Lab CKAD-03]]   |
| Use the Helm package manager to deploy existing packages    | [[Kubernetes/guides/delivery/templating-patching/helm/README\|Helm]], [[Kubernetes/guides/delivery/templating-patching/helm/commands\|Helm Commands]]                  | [[Kubernetes/labs/ckad/11-helm-release-lifecycle\|Lab CKAD-11]]  |
| Kustomize                                                   | [[Kubernetes/guides/delivery/templating-patching/kustomize\|Kustomize]]                                                                                                | [[Kubernetes/labs/ckad/07-kustomize-and-lifecycle\|Lab CKAD-07]] |

The exam expects blue/green and canary built from plain Deployments and Service selectors. Argo Rollouts and service meshes are not in scope, so read the strategies note for the mechanics and skip the tooling sections.

**Task drills**

- [ ] Set `maxSurge` and `maxUnavailable` on a Deployment, change the image, watch `kubectl rollout status`, then roll back to a specific revision.
- [ ] Pause a rollout, make two changes, resume it, and confirm only one new ReplicaSet was created.
- [ ] Blue/green: run `v1` and `v2` Deployments side by side and cut over by editing the Service selector.
- [ ] Canary: run two Deployments behind one Service and size the replicas so roughly 20% of traffic reaches the canary.
- [ ] Add a Helm repository, install a chart into a new namespace with two overridden values, upgrade it, roll it back, and uninstall it.
- [ ] Find which values a chart accepts with `helm show values`, and what a release was installed with using `helm get values`.
- [ ] Apply a Kustomize overlay that changes the namespace, the image tag and the replica count (`kubectl apply -k`).

---

## 3. Application Observability and Maintenance (15%)

| Objective                                      | Read                                                                                                                                                                                                                                                                                                                                                                                 | Practise                                                                                                                                                                         |
| :--------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Understand API deprecations                    | [[Kubernetes/guides/non-functional/deprecations\|Deprecations]], [[Kubernetes/updates-along-the-versions\|Updates Along the Versions]]                                                                                                                                                                                                                                               | [[Kubernetes/labs/ckad/07-kustomize-and-lifecycle\|Lab CKAD-07]]                                                                                                                 |
| Implement probes and health checks             | [[Kubernetes/concepts/L03-workloads/10-probes\|Probes]]                                                                                                                                                                                                                                                                                                                              | [[Kubernetes/labs/ckad/13-quotas-limit-ranges-and-probes\|Lab CKAD-13]] (design and repair), [[Kubernetes/labs/ckad/05-services-and-dns\|Lab CKAD-05]] (readiness and endpoints) |
| Use built-in CLI tools to monitor applications | [[Kubernetes/concepts/L08-operations/04-metrics-sources\|Metrics Sources]], [[Kubernetes/guides/tools/kubectl\|kubectl]]                                                                                                                                                                                                                                                             | [[Kubernetes/labs/ckad/06-observability-and-troubleshooting\|Lab CKAD-06]]                                                                                                       |
| Utilize container logs                         | [[Kubernetes/concepts/L08-operations/02-kubectl-debug\|kubectl Debug Toolkit]]                                                                                                                                                                                                                                                                                                       | [[Kubernetes/labs/ckad/06-observability-and-troubleshooting\|Lab CKAD-06]]                                                                                                       |
| Debugging in Kubernetes                        | [[Kubernetes/concepts/L08-operations/01-troubleshooting\|Troubleshooting Flow]], [[Kubernetes/concepts/L08-operations/03-common-failure-modes\|Common Failure Modes]], [[Kubernetes/guides/troubleshooting/crashloop-backoff\|CrashLoopBackOff]], [[Kubernetes/guides/troubleshooting/image-pull\|ImagePullBackOff]], [[Kubernetes/guides/troubleshooting/pod-pending\|Pod Pending]] | [[Kubernetes/labs/ckad/06-observability-and-troubleshooting\|Lab CKAD-06]]                                                                                                       |

**Task drills**

- [ ] Fix a manifest that uses a removed API version. Find the served version with `kubectl api-resources` and `kubectl explain`.
- [ ] Add an HTTP readiness probe, a TCP liveness probe and a startup probe to one container, each with its own timings.
- [ ] Find the Pod using the most CPU in a namespace with `kubectl top` and write its name to a file.
- [ ] Get logs from a specific container of a multi-container Pod, and from the previous instance of a restarted container.
- [ ] Diagnose a Pod in `CrashLoopBackOff` from its exit code and events alone, then fix it.
- [ ] Attach an ephemeral debug container to a running Pod that has no shell.

---

## 4. Application Environment, Configuration and Security (25%)

The heaviest domain by weight.

| Objective                                                        | Read                                                                                                                                                                                                                                                                                            | Practise                                                                                                                                                                                           |
| :--------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Discover and use resources that extend Kubernetes                | [[Kubernetes/concepts/L09-advanced/03-customresourcedefinitions\|CustomResourceDefinitions]], [[Kubernetes/concepts/L09-advanced/01-operators\|Operators]]                                                                                                                                      | [[Kubernetes/labs/cka/10-operators-and-custom-resources\|Lab CKA-10]]                                                                                                                              |
| Understand authentication, authorization and admission control   | [[Kubernetes/concepts/L07-security/01-api-access/01-authentication-authorization\|Authentication vs Authorization]], [[Kubernetes/concepts/L07-security/01-api-access/03-rbac\|RBAC]], [[Kubernetes/concepts/L07-security/04-admission-policy/10-admission-controllers\|Admission Controllers]] | [[Kubernetes/labs/cks/13-rbac-remediation\|Lab CKS-13]] (RBAC), [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]] (Pod Security admission). Other admission control: reading only |
| Understand requests, limits, quotas                              | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|Resource Requests and Limits]], [[Kubernetes/concepts/L05-config-storage/08-resource-quota\|ResourceQuota and LimitRange]]                                                                                            | [[Kubernetes/labs/ckad/13-quotas-limit-ranges-and-probes\|Lab CKAD-13]]                                                                                                                            |
| Understand ConfigMaps                                            | [[Kubernetes/concepts/L05-config-storage/01-config-maps\|ConfigMaps]]                                                                                                                                                                                                                           | [[Kubernetes/labs/ckad/04-configuration\|Lab CKAD-04]]                                                                                                                                             |
| Define resource requirements                                     | [[Kubernetes/concepts/L06-scheduling-scaling/01-resource-requests-limits\|Resource Requests and Limits]]                                                                                                                                                                                        | [[Kubernetes/labs/cka/02-scheduling-and-autoscaling\|Lab CKA-02]]                                                                                                                                  |
| Create and consume Secrets                                       | [[Kubernetes/concepts/L05-config-storage/02-secrets\|Secrets]]                                                                                                                                                                                                                                  | [[Kubernetes/labs/ckad/04-configuration\|Lab CKAD-04]]                                                                                                                                             |
| Understand ServiceAccounts                                       | [[Kubernetes/concepts/L07-security/01-api-access/02-service-accounts\|Service Accounts]]                                                                                                                                                                                                        | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]]                                                                                                                                 |
| Understand application security (SecurityContexts, capabilities) | [[Kubernetes/concepts/L07-security/02-workload-sandboxing/05-security-context\|SecurityContext]], [[Linux/security/capabilities\|Linux Capabilities]], [[Kubernetes/concepts/L07-security/02-workload-sandboxing/06-pod-security-standards\|Pod Security Standards]]                            | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]]                                                                                                                                 |

**Task drills**

- [ ] List the CRDs in a cluster, read the schema of one with `kubectl explain`, and create a custom resource from it.
- [ ] Create a Role, a ServiceAccount and a RoleBinding imperatively, then prove the result with `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa>`.
- [ ] Fix a Pod that is rejected by a ResourceQuota because it declares no requests.
- [ ] Create a LimitRange with default requests and limits, and confirm a new Pod picks them up.
- [ ] Consume one ConfigMap three ways: single env var, `envFrom`, and a mounted file with `subPath`.
- [ ] Create a Secret from a file and from literals, then mount it read-only with a specific file mode.
- [ ] Run a Pod under a named ServiceAccount with token automounting disabled.
- [ ] Set `runAsUser`, `runAsNonRoot`, `readOnlyRootFilesystem` and `allowPrivilegeEscalation: false`, drop all capabilities and add back `NET_BIND_SERVICE`.

---

## 5. Services and Networking (20%)

| Objective                                                    | Read                                                                                                                                                                                                                             | Practise                                                           |
| :----------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------- |
| Demonstrate basic understanding of NetworkPolicies           | [[Kubernetes/concepts/L04-services-networking/05-network-policy\|NetworkPolicy]], [[Security/kubernetes-security/network-policies/README\|Network Policies (Security)]]                                                          | [[Kubernetes/labs/cks/01-workload-security-hardening\|Lab CKS-01]] |
| Provide and troubleshoot access to applications via Services | [[Kubernetes/concepts/L04-services-networking/02-services\|Services]], [[Kubernetes/concepts/L04-services-networking/03-dns\|DNS in Kubernetes]], [[Kubernetes/guides/troubleshooting/service-unreachable\|Service Unreachable]] | [[Kubernetes/labs/ckad/05-services-and-dns\|Lab CKAD-05]]          |
| Use Ingress rules to expose applications                     | [[Kubernetes/concepts/L04-services-networking/04-ingress\|Ingress]], [[Kubernetes/guides/troubleshooting/ingress-404\|Ingress 404 / 502 / 503]]                                                                                  | [[Kubernetes/labs/ckad/09-ingress\|Lab CKAD-09]]                   |

Lab CKAD-05 covers Services, DNS, NodePorts and three ways to lose a backend. Lab CKS-01 section 7 tests NetworkPolicies with a before-and-after reachability matrix. Routing by host and path is in Lab CKAD-09. For mixed, unlabelled faults see [[Kubernetes/labs/cka/11-service-and-dns-troubleshooting|Lab CKA-11]].

**Task drills**

- [ ] Expose a Deployment as ClusterIP and as NodePort, and test both from a temporary Pod with `kubectl run tmp --rm -it --image=busybox -- wget -qO- <svc>`.
- [ ] Fix a Service with no endpoints by comparing its selector with the Pod labels, then fix one whose `targetPort` is wrong.
- [ ] Write a default-deny ingress policy for a namespace, then allow traffic to one app only from Pods carrying a given label.
- [ ] Add an egress rule that allows DNS and one destination port, and nothing else.
- [ ] Given existing NetworkPolicies you may not edit, make a Pod reachable by changing only its labels.
- [ ] Create an Ingress with two path rules and a host rule pointing at two Services, using `kubectl create ingress`.

---

## Gaps in the wiki

| Objective                             | What is missing                                                                   | Use instead                                                                                                                                                                 |
| :------------------------------------ | :-------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DaemonSet and StatefulSet             | Concept notes only; no lab creates or changes one                                 | [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) and [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) |
| Admission control beyond Pod Security | Reading only for the CKAD level                                                   | [Admission control](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)                                                                         |
| Imperative command fluency            | Generators appear throughout the labs, not as one drill set                       | [kubectl quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/)                                                                                    |
| Independent grading                   | The practice tasks give checks you run yourself; nothing scores you automatically | The exam simulator, if your registration includes it                                                                                                                        |

---

## Study plan

The plan below is a **revision schedule for someone who passes the [[Kubernetes/certifications/index#before-you-start-a-track|entry check]]**, at about an hour a day. It does not include installing tools, pulling images or learning Linux and YAML from scratch; add time for those. Finishing it is not a pass prediction.

Do the CKAD labs in numeric order. Labs 02 to 06 share one application and each expects the state the previous one left; every other lab uses its own namespace and can be done at any point.

| Week | Focus                                                                                                                                    | Labs                                                            |
| :--- | :--------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------- |
| 1    | Prerequisites, the shared application, configuration                                                                                     | CKAD-01, 02, 03, 04, 05                                         |
| 2    | Observability, images, workload kinds, volumes                                                                                           | CKAD-06, 08, 10, 13 and CKA-01                                  |
| 3    | Delivery, networking, security, extensions                                                                                               | CKAD-07, 09, 11, 12, CKS-01, CKS-13 and CKA-10                  |
| 4    | Every "Practice Without the Answer" section again, unguided; the timed practice set; weak spots; the simulator sessions if you have them | [[Kubernetes/certifications/ckad-mock-exam\|CKAD practice set]] |

Use the [[Kubernetes/review/workloads-refresher|Workloads refresher]] and [[Kubernetes/review/networking-refresher|Networking refresher]] in the last few days.

## Ready when

- [ ] You complete each lab's practice section without opening the guided part, on a second attempt some days after the first.
- [ ] You can produce a manifest for any object in the track by the fastest route available: a generator where one exists, an edited documentation example where none does.
- [ ] You finish the [[Kubernetes/certifications/ckad-mock-exam|CKAD practice set]] inside two hours at or above the pass mark, using only the allowed documentation, and every check you ran before moving on was your own idea.
- [ ] If you have the simulator, your second session is at or above the pass mark.

## Further reading

- [CKAD curriculum](https://github.com/cncf/curriculum)
- [CKAD exam page](https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/)
- [kubectl quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/)

## Across the wiki

- [[Kubernetes/certifications/cka|CKA Track]]: the natural next exam, and about half of it is this material.
- [[Kubernetes/certifications/cks|CKS Track]]
- [[Containers/dockerfile-best-practices|Dockerfile Best Practices]]
