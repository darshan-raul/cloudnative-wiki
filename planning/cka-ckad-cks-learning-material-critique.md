# Critique of the CKA, CKAD and CKS learning tracks

Reviewed 2026-10-13 against the uncommitted worktree. This is a review, not a content rewrite.

## Verdict

These tracks are useful curriculum maps and contain valuable worked exercises. They are not yet reliable, self-contained preparation that I would recommend to an arbitrary learner with the expectation that following the sequence establishes exam readiness.

The biggest problem is the gap between presentation and evidence. All 16 exam domains are marked **Good**, the lab hub says all labs are tested across v1.35–v1.37, and the study plans lead to readiness checklists. However, several central exercises do not produce the described result, some cumulative steps conflict, important objectives have no concrete assessment, and the course has no independent scored practice. A knowledgeable practitioner can compensate. The learner most dependent on a course cannot reliably distinguish an intentional failure from an authoring defect.

| Dimension                                 | Assessment                   | Reason                                                                                   |
| ----------------------------------------- | ---------------------------- | ---------------------------------------------------------------------------------------- |
| Organization and discoverability          | Strong foundation            | Clear certification hubs, objective tables, shared concepts, and lab indexes             |
| Alignment to published objective families | Broadly good                 | The tracks include current topics rather than simply repeating an old syllabus           |
| Accuracy of executable examples           | Needs substantial correction | Multiple reproduced failures affect fundamental lessons                                  |
| Environment reproducibility               | Incomplete                   | Unpinned dependencies, incompatible permitted version combinations, cross-lab state      |
| Teaching progression                      | Partly effective             | Worked examples and controlled failures help, but guided execution dominates             |
| Independent assessment                    | Weak                         | No fixtures and graders for most drills; no internal mixed timed assessment              |
| Accessibility to newcomers                | Weak                         | Assumes shell, YAML, Docker, Linux administration and self-directed debugging competence |
| Value to an experienced practitioner      | Useful                       | Good reading map and a number of focused advanced exercises                              |
| Evidence of exam readiness                | Insufficient                 | Completion and familiarity are not demonstrated transfer under time pressure             |

These are qualitative judgments, not measured pass probabilities or estimates of exam-question coverage.

## Scope and evidence

I read the three certification tracks, their shared hub, all 28 numbered labs and their indexes, and selected supporting material including the Gateway API runbook, incident scenarios, probe material, and backup/restore guide. I examined the uncommitted changes and compared several moved labs with HEAD to distinguish inherited defects. I did not audit every linked concept note in the wiki.

I checked current official exam guidance through a background research review and performed targeted runtime checks in a disposable Kubernetes 1.35.0 cluster using kind 0.31.0 and kubectl 1.36.0. These were focused reproductions, **not** a complete execution of all labs, a three-node scheduling qualification, or a VM-based install/upgrade test.

Companion reports:

- [Official requirements and curriculum comparison](cka-ckad-cks-official-requirements-review.md).
- [Execution evidence and defect provenance](cka-ckad-cks-review-execution-evidence.md).

`npm run check:k8s` passed, reporting 1021 notes scanned and zero Kubernetes errors or warnings. This establishes structural consistency; it says nothing about whether a command works, a diagnosis is correct, or the learner can solve an unfamiliar task. I did not run a production build or visual accessibility audit.

The main broken examples below largely existed before the reorganization. The new tracks inherit them and now rely on them as exam preparation. The NodePort integration problem and overly strong coverage claims must also be evaluated in the new combined structure.

## What deserves to be preserved

1. **The objective-to-reading-to-practice structure.** This makes a large wiki navigable and provides a sensible place to maintain curriculum alignment. It is much better than asking learners to read the entire Kubernetes tree.
2. **The explicit gap tables.** Admitting missing Helm, HPA, multi-container, incident-response and other practice is useful editorial discipline. The domain summaries should reflect that same honesty.
3. **Worked failure and recovery.** The intention to show symptoms, evidence, diagnosis and repair is appropriate for performance exams. Several new node-oriented exercises make the API/node boundary concrete.
4. **CKA-06's authentication versus authorization sequence.** A signed certificate followed by a Forbidden response, then narrowly granted RBAC, is an effective explanation through observable behaviour.
5. **CKS-03's evidence-based audit exercise.** First-match policy rules, deliberately avoiding Secret bodies, and distinguishing the caller from an impersonated identity are valuable lessons.
6. **CKS-04's distinction between new and existing data.** Showing plaintext before encryption, ciphertext afterward, and explicitly rewriting old Secrets teaches a common operational trap. Its key-loss exercise gives the configuration real consequences.
7. **The newer CKS caveats.** CKS-07 explicitly notes that passing a linter does not make a Pod runnable. CKS-09 explicitly says digest enforcement does not verify signatures. CKS-11 distinguishes encryption from mutual authentication and inter-node from same-node traffic. These are good distinctions to expand and test.
8. **The host-versus-node labels in newer labs.** They reduce a common source of confusion, although the overall course still needs a consistent shell/context convention.

## Findings that should block a claim of reliable self-study preparation

Severity here reflects impact on learning: **P1** means a core exercise fails, teaches an incorrect model, or creates false confidence about a security control. **P2** means incomplete coverage, sequencing, portability or assessment. This is not a software vulnerability rating.

### F01 — P1: the ReplicaSet reconciliation exercise does not match the ReplicaSet selector

**Location:** `labs/ckad/02-deploy-workload.md:211–244`.

The lab creates `rogue-pod` with only `app.kubernetes.io/name=podinfo` and claims the Deployment's ReplicaSet will adopt/delete it to restore two replicas. Deployment-generated ReplicaSets also select `pod-template-hash`. The rogue Pod has no hash and does not match.

**Reproduced:** the ReplicaSet selector contained both labels; `rogue-pod` remained Running with no owner. This also contaminates later broad `app.kubernetes.io/name=podinfo` selections. Once the Service exists, the extra BusyBox Pod can be selected even though it is not an HTTP backend; its missing named target port adds another discrepancy to investigate.

**Learning impact:** a foundational controller explanation is false, and later results no longer have the promised starting state.

**Correction:** use an explicitly authored standalone ReplicaSet for adoption, or deliberately copy the full selector and explain the hash. Give an assertion for ownerReferences and replica count, and remove the rogue resource afterward. The [Deployment documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#pod-template-hash-label) explains the generated selector.

### F02 — P1: CKAD-04 is not compatible with the state left by CKAD-03

**Location:** `labs/ckad/03-updates-and-rollbacks.md:67`; `labs/ckad/04-configuration.md:92–173`.

CKAD-03 adds explicit `PODINFO_UI_COLOR` and `PODINFO_UI_MESSAGE` environment entries. CKAD-04 applies a manifest using ConfigMap `envFrom`, expecting new values. Client-side apply retains the imperative entries that were not previously owned by its last-applied configuration; explicit `env` values override `envFrom`.

**Reproduced:** the supposedly ConfigMap-configured container still reported `#16a085` and `v2 rollout successful!`, instead of the lab's expected values.

The replacement manifest also drops the readiness/liveness probes introduced in CKAD-02. The course does not explain this removal, even though later discussions depend on readiness being meaningful.

**Correction:** deliberately remove or replace the prior environment entries, preserve the intended baseline probes, and verify the actual environment and application response before proceeding. Teach precedence as an intentional comparison. See [declarative configuration and retained fields](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/).

### F03 — P1: CKAD-04's documented recovery does not remove the injected fault

**Location:** `labs/ckad/04-configuration.md:274`.

The fault is added using a JSON patch to the `env` list. Reapplying the original manifest is described as removing the invalid reference, but that entry is not in the last-applied configuration used to calculate deletions.

**Reproduced:** after the prescribed recovery, `DB_PASSWORD` still referenced `missing-password-key`, and the replacement Pod remained in `CreateContainerConfigError`.

**Learning impact:** a learner can follow the recovery exactly, remain broken, and carry the failure into networking and observability.

**Correction:** explicitly remove the environment entry, undo the known failed rollout where appropriate, or otherwise define and verify ownership. Check that the reference is absent, then wait for a successful rollout. Do not teach that apply always makes the live object identical to the file.

### F04 — P1: the observability lab never triggers its advertised crash

**Location:** `labs/ckad/06-observability-and-troubleshooting.md:125–204`.

The lab sends `POST /panic`, promises an unhandled Go panic, an exit code of 2, a stack trace, and CrashLoopBackOff. The pinned podinfo 6.7.1 registers this endpoint for **GET** and calls `os.Exit(255)`.

**Reproduced:** `POST /panic` returned HTTP 405. The [pinned route registration](https://github.com/stefanprodan/podinfo/blob/6.7.1/pkg/api/http/server.go) and [handler](https://github.com/stefanprodan/podinfo/blob/6.7.1/pkg/api/http/panic.go) contradict the expected trace. Even after correcting the method, a single intentional exit is not a reliable repeated-crash exercise.

**Correction:** separate a one-shot termination from a deterministic repeated startup failure. Show actual previous logs and `lastState.terminated.exitCode`. Use a controlled failure that repeatedly exits until the learner repairs configuration. Also correct `OOMKilled: true`: the relevant termination status is a reason string such as `reason: OOMKilled`, not that boolean field.

### F05 — P1: the storage lab does not write to the PVC it claims to test

**Location:** `labs/cka/01-storage-and-persistence.md:148–206`.

The exercise mounts a PVC at `/data/cache`, posts to `/cache/k8s-curriculum`, deletes the Pod, then expects a file `/data/cache/k8s-curriculum` in its replacement. Podinfo's `/cache` API uses Redis, and this lab configures no Redis service or cache connection. Mounting a directory does not change application behaviour.

**Reproduced:** the pinned application returned a body saying `cache server is offline`. Its [cache implementation](https://github.com/stefanprodan/podinfo/blob/6.7.1/pkg/api/http/cache.go) uses Redis GET/SET, not the mounted filesystem. The HTTP status in my observed trace was 200 despite the error body; success must be checked semantically, not by assuming a successful transport is a successful write.

The lab also repeatedly calls the Rancher local-path provisioner a CSI driver. The [implementation](https://github.com/rancher/local-path-provisioner) dynamically provisions hostPath/local storage; dynamic provisioning is not synonymous with CSI. Deleting a Pod and recreating it on its local volume does not establish recovery after loss of the storage node.

**Correction:** write and checksum a file through a known filesystem workload with correct permissions; recreate the consumer; verify the same PV identity and checksum. Explain local storage placement and its failure boundary. If using podinfo's filesystem API, configure and test that API rather than `/cache`.

### F06 — P1: the scheduling failure uses a removed kubectl option

**Location:** `labs/cka/02-scheduling-and-autoscaling.md:166–170`.

`kubectl run ... --requests=...` does not create a Pod on the reviewed client.

**Reproduced:** kubectl 1.36.0 returned `error: unknown flag: --requests` even with client dry-run. There can be no subsequent Pending Pod or scheduler events from that command.

**Correction:** generate a manifest and set resources, or provide an appropriate overrides object. Verify that the Pod exists, then distinguish a scheduler refusal from a client-side CLI error. The [current command reference](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_run/) is the appropriate source.

### F07 — P1: the declarative drift repair demonstrates an unhandled ownership conflict

**Location:** `labs/ckad/07-kustomize-and-lifecycle.md:325–363`.

The lab applies with server-side apply, changes replicas and image imperatively, then repeats server-side apply and claims both fields are restored. Those updates transfer field ownership.

**Reproduced with equivalent ownership transitions:** apply failed with conflicts on `.spec.replicas` against the scale manager and on the image against `kubectl-set`.

**Correction:** teach managed fields and the intended conflict-resolution policy. If a designated reconciler is meant to own those fields, explicitly resolve that conflict and explain the consequence; do not present forcing ownership as a universal repair. Manual apply is also a demonstration of reconciliation, not evidence that an automatic GitOps loop is installed. See [server-side apply conflicts](https://kubernetes.io/docs/reference/using-api/server-side-apply/#conflicts).

### F08 — P1: the CKAD sequence allocates the same NodePort twice

**Location:** `labs/ckad/05-services-and-dns.md:263–283`; `labs/ckad/09-ingress.md:32`.

CKAD-05 retains `podinfo-nodeport` on 30080. CKAD-09 installs Traefik with its web NodePort also set to 30080. Namespaces do not isolate NodePort allocation.

**Reproduced:** a second Service allocating 30080 was rejected with `provided port is already allocated`. This is a direct integration defect even if each lab worked on a separately reset cluster.

**Correction:** clean up the earlier Service, allocate a distinct port, or use a documented fresh cluster profile. Test the recommended sequence, not only isolated chapters.

CKAD-05 also attempts `localhost:30080` without mapping that port into kind; the setup maps 80/443. Its node-IP fallback is Linux-specific. Provide the portable port-forward or correct mapping explicitly, rather than grouping HostPort, Docker port mappings, and NodePort under one mechanism.

### F09 — P1: the first security lab misidentifies the workload and does not finish remediation

**Location:** `labs/cks/01-workload-security-hardening.md:64`, `:98`, and the separate `podinfo-insecure` / `podinfo-hardened` Deployments.

The baseline is said to run as UID 0 with all capabilities because no securityContext is present. The image has an image-level USER. **Reproduced:** `id` reported UID 100 (`app`), GID 101. The [pinned Dockerfile](https://github.com/stefanprodan/podinfo/blob/6.7.1/Dockerfile) selects that user. Absence of a securityContext does not imply all Linux capabilities either.

The exercise then creates a second hardened Deployment but never removes or fixes the original. Namespace enforcement is not retroactive remediation of the already running Pod. A new hardened workload is not proof the old exposure is gone.

**Correction:** inventory observed identity and capabilities first. Either deliberately create a root baseline or describe the actual weaknesses accurately. Patch the original workload or explicitly retire it; verify all remaining workloads, ServiceAccount token mounts, effective permissions, filesystem writes, and traffic constraints. See [Pod Security namespace enforcement](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/).

Further semantic corrections: `can-i list pods` returning no does not prove zero cluster permissions; `emptyDir: {}` is not specifically memory-backed; built-in PodSecurity is not an admission webhook; the allow ingress policy permits all namespaces on the application port, not a selected trusted client tier.

### F10 — P1: the upgrade lab starts from an inconsistent predecessor state

**Location:** `labs/cka/03-kubeadm-cluster-install.md:142`; `labs/cka/04-kubeadm-upgrade.md:33` and section 4.

CKA-03 creates Deployment `web` with three replicas. CKA-04 explicitly starts from that cluster, then tries to create the same Deployment with four replicas. It will receive AlreadyExists, leaving three replicas. Its later PDB exercise assumes four: after setting `minAvailable` to three, a three-replica Deployment still has no voluntary disruption allowance.

**Evidence:** deterministic static sequence; I did not run the VM installation. The failure follows directly from reusing the object name and the PDB arithmetic.

**Correction:** make the prerequisite idempotent, scale to four, wait for four healthy replicas, and assert that state before creating the PDB. Include a verified final uncordon for each worker after the deliberate drain. This illustrates why the explicit untested warning is important and the hub's universal testing claim is untenable.

### F11 — P1: a recommended incident scenario teaches incorrect PDB arithmetic

**Location:** `review/scenarios.md:254–259`.

With two replicas and `minAvailable: 2`, fixing the unhealthy replica gets healthy replicas back to two, not to a state permitting one eviction. The scenario incorrectly says allowed disruptions becomes one and drain proceeds.

**Correction:** show that allowed disruptions remains zero. Depending on the task constraints, scale up and wait for readiness, or deliberately revise the budget. The [PDB documentation](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) defines the required number left available after eviction.

This is inherited supporting material, but the tracks explicitly recommend it as some of the nearest material to exam scenarios. Reading links need technical review too.

### F12 — P2: testing and environment claims exceed the documented evidence

**Location:** `labs/index.md:39`; `labs/ckad/01-cluster-setup.md:37–38`, `:92–99`.

The hub says all labs are tested across v1.35–v1.37. Two kubeadm labs and the AppArmor section explicitly say they were not run. Many newer lab headers identify only kind 0.31 / Kubernetes 1.35.0. Setup accepts kind 0.27+ but does not choose an image while printing an expected v1.37 cluster; kubectl 1.35 is permitted even though that is outside the supported skew from a 1.37 server.

**Correction:** maintain per-lab exact tested profiles and execution dates; distinguish tested, source-reviewed and experimental sections. Pin node images and tool/chart versions, then provide an explicit update policy. The [version-skew policy](https://kubernetes.io/releases/version-skew-policy/) supports kubectl within one minor version of the API server.

## Track-specific assessment

### CKAD: helpful tour, incomplete skill-building course

CKAD should teach application tasks through short, independently solvable transformations. The current nine labs spend much of their attention on one Deployment. This reduces context switching for the first pass, but leaves several core skill families largely untested.

| Skill family           | What the material actually provides                      | What is missing                                                                                                      |
| ---------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Images                 | Build, tag, inspect, save/load, local image pull failure | Independent task with supplied files, required archive format and artifact checks                                    |
| Workload selection     | Deployment walkthrough plus reading links                | Jobs/CronJobs, init/sidecar patterns, choosing a controller for a requirement                                        |
| Delivery               | Rolling update/rollback and Kustomize demonstration      | Runnable blue/green and canary tasks; Helm lifecycle exercise                                                        |
| Configuration/security | ConfigMap/Secret walkthrough and shared security lab     | Repaired cumulative state; quotas/LimitRange; granular permissions and security requirements in unfamiliar manifests |
| Observability          | Logs/debug examples and optional top commands            | Working repeated crash; actual metrics environment; probes designed, broken and repaired                             |
| Networking             | Services, DNS, Ingress and policy YAML                   | Correct sequence and portable access; a reachability test matrix for policy selectors and DNS                        |
| Extensibility          | CRD reading and open-ended prompt                        | Installed fixture with a schema to discover and a custom resource to create/validate                                 |

Two misleading mappings deserve explicit correction. Blue/green and canary are mapped to CKAD-03, which only performs rolling updates and rollback. Quotas are mapped to CKA-02, which has no ResourceQuota or LimitRange exercise. A whole-document link can look like coverage while leaving the named competency unpractised.

Probes appear in a large ready-made manifest, but copying a correct readiness probe does not teach selecting a handler, tuning startup timing, or diagnosing the difference between an unready process and a restarting one. Add a slow-starting application and require the learner to keep it available while preserving meaningful health checks.

CKAD-07's deprecation section lists currently served APIs. It does not give the learner an old manifest to migrate or demonstrate schema changes. Gateway API is not established by querying only `networking.k8s.io`; it is a separate API group and requires installed CRDs. The namespace recovery exercise exports ConfigMaps/Secrets but never restores that backup; the sample app does not depend on meaningful restored data. It tests redeploying declarative workloads, not application-data recovery.

The four-week plan is plausible as a revision schedule for someone already comfortable with Kubernetes. It is not justified as a beginner-to-ready time estimate. In particular, scheduling CKA-01 in week one changes the same `default/podinfo` object later cumulative CKAD labs assume. The study-plan path and numeric lab path should both be tested.

**Recommendation:** repair the existing spine, then prioritize multi-container/Jobs/CronJobs, Helm, probes, quota/LimitRange, and deployment-strategy practice before adding more advanced delivery material.

### CKA: useful new node exercises, uneven practice across the syllabus

The new install, upgrade, etcd, CSR and repair labs address the biggest limitation of an application-only kind curriculum. CKA-06 and CKA-07 are good foundations. The problem is that several direct objectives still rely on reading and that the VM path has not been qualified.

Priority gaps:

- **HPA and metrics:** the track asks for autoscaling, but CKA-02 does not create an HPA, and CKAD-06 treats metrics-server as optional and suppresses its errors. Install a working metrics pipeline, generate load, observe scale-up/down, then diagnose missing requests or metrics.
- **Helm and operators:** using Helm incidentally to install Traefik or Falco is not practice discovering chart values, upgrading, rolling back and debugging a release. An operator exercise needs a named, pinned fixture, a CR, and an observable reconciled result.
- **Scheduling:** copying topology spread does not cover taints/tolerations, required/preferred affinity, admission limits, PriorityClass, and manually scheduled/static Pods. These are currently mostly ungraded prompts.
- **Storage:** the numbered lab does not exercise static PV binding, reclaim policies, recovery of a Released PV, or real expansion. The expansion drill needs a supporting driver; a StorageClass flag alone does not give the standard local-path provisioner volume-resize capability. The [upstream expansion discussion](https://github.com/rancher/local-path-provisioner/issues/190) makes that limitation explicit.
- **HA control plane:** concept material exists, but a one-control-plane kind cluster cannot demonstrate joining another control plane, shared endpoints, or quorum survival. Provide a tested advanced profile and name the required operations.
- **Networking troubleshooting:** one selector typo is a narrow sample. Add wrong targetPort, unready endpoints, DNS forwarding, policy, and node-level networking faults with distinct evidence.

Gateway API is **not absent from the repository**. The linked folder contains install/cleanup scripts, VERIFY, and sixteen scenario YAMLs. However, its runbook explicitly says runtime validation was not performed; it begins with `cd lab` rather than the actual checkout path, and includes substantial Envoy-specific day-2 material. A learner needs a small, validated exam-focused path through that existing material, not a claim that only a numbered filename would count.

CKA-05 usefully distinguishes etcdctl from etcdutl and host paths from container mount paths. Its revision rollback treatment is incomplete: restarting the local control plane is not the full general solution for caches in external controllers/operators. Teach the upstream recommendation for revision bump and marking compacted when restoring Kubernetes data, and explain single-member versus multi-member restore. This is a completeness issue, not a claim that its simple single-control-plane demonstration always fails. [etcd recovery guidance](https://etcd.io/docs/v3.6/op-guide/recovery/#restoring-with-revision-bump)

The linked backup guide still describes stopping a kubeadm API server with `systemctl stop kube-apiserver` (`guides/non-functional/backup-restore.md:442`), despite kubeadm's static-Pod model. Changing only the etcd tool name in that guide has not reconciled its operational procedure with the new lab.

**Recommendation:** qualify the VM route, repair storage/scheduling, provide HPA/Helm/operator exercises, and concentrate independent troubleshooting tasks according to the 30% domain emphasis. Do not estimate pass probability from the number of pages or labs.

### CKS: the strongest new breadth, but verification must be more demanding

The twelve labs are a meaningful expansion. Audit, encryption, runtime detection, scanner output, admission controls, signing, sandboxing and packet inspection provide a useful range. An experienced CKA holder can learn from these exercises.

The remaining issue is whether a successful command establishes the promised security outcome:

- **RBAC:** CKS-01 creates an unbound ServiceAccount and gets one denied request. It does not remediate excessive roles, bindings, wildcard privileges, or prove that required permissions remain. Add a workload with a precise required access set and both allowed and forbidden requests.
- **NetworkPolicy:** CKS-01 applies rules but does not test them. Require a matrix across approved and unapproved clients, same/other namespaces, ports, DNS and external destinations. In my tested kind environment, default-deny did block DNS; this review does not assume that all kind CNIs lack enforcement. The lesson still needs to prove its own complete policy outcome on its pinned profile.
- **ImagePolicyWebhook:** CKS-08 intentionally has no backend. Connection refusal proves the fail-closed path is active; it does not prove correct TLS, client authentication, ImageReview exchange, or selective image decisions. Its statement that the plugin is configured correctly overstates this evidence. Provide a small working backend and test allowed, denied and unavailable cases.
- **Signature enforcement:** CKS-09 accurately admits that its digest policy does not verify signatures. Nevertheless, its “Run Only What Was Verified” section should demonstrate that an unsigned digest is still admitted, then add actual signature policy enforcement as an advanced exercise. Otherwise a learner can remember the title and miss the limitation.
- **Runtime investigation:** trigger-known-alert → grep-known-string → identify-known-Pod is an introductory demonstration. It does not assess finding an unknown actor, correlating audit and process evidence, distinguishing benign from malicious activity, building a timeline, and containing the correct controller while preserving evidence.
- **AppArmor:** the VM exception is transparent, but a core kernel-control skill remains unexecuted. The AppArmor section loads a profile on a node without explicitly constraining the example Pod to that node or fully provisioning every schedulable node. Provide a reproducible VM route and an explicit placement check.
- **Seccomp:** “no field means unconfined” depends on kubelet seccompDefault; use an explicit Unconfined comparison or inspect that setting. Restricted PSS accepts Localhost as well as RuntimeDefault. A read-only root filesystem does not make all process state or mounted volumes immutable. See [seccomp defaults](https://kubernetes.io/docs/tutorials/security/seccomp/) and [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/).
- **AppArmor version:** CKS-05 says the field has been stable since 1.30. Field introduction and GA differ; the official historical tutorial identifies stability at 1.31. [AppArmor tutorial](https://kubernetes.io/docs/tutorials/clusters/apparmor/)
- **Host hardening:** CKS-12 has a useful port → PID → binary → package → unit chain, but it is not a complete least-privilege host identity or firewall exercise. The shared-kernel warning is appropriate and should remain.

CKS-11's use of a reachable public address as a metadata stand-in is explicitly explained, which is better than pretending kind supplies cloud metadata. A local deterministic endpoint would remove internet reachability as a confounder. A failure to reach an arbitrary internet address alone is not proof a policy caused the failure; establish the baseline, alternate control, and relevant traffic evidence. Also distinguish encryption from mutual authentication in the track drill that currently joins them with “or.”

**Recommendation:** deepen adversarial validation and add an end-to-end unknown incident before expanding the tool list. Not every alternative tool needs its own lab; an objective can be well taught using one appropriate, validated implementation.

## Cross-cutting teaching problems

### Worked demonstrations are being used as readiness evidence

The recurring pattern is: tell the learner the cause, provide the exact command to create it, show the expected symptom, then supply the repair. That is a worked example. It helps initial understanding but does not show whether the learner can diagnose anything independently.

Each important skill needs three stages:

1. **Guided:** explain and execute the mechanism with visible evidence.
2. **Independent:** provide an outcome and starting state, changing names, namespace, image, ports or constraints; hide the solution.
3. **Transfer:** combine it with another skill or an unfamiliar failure, and grade the final state.

For example, after the Service-selector tutorial, provide a failing app where the defect could be the selector, named targetPort, readiness, DNS or policy. The learner must identify which evidence distinguishes them. Simply repeating the original typo faster mainly tests recall of the recipe.

### Most drills are prompts without enough scaffolding to function as exercises

“Install an operator,” “fix a CRD,” or “find a broken node” requires an environment and success definition. For an experienced practitioner these are useful reminders. A newcomer must design the exercise before they can do it, which silently assumes much of the skill being taught.

Supply initial resources, any broken component, task constraints, allowed reference pages, expected output files, an independent verifier, and a reset. Keep solutions separate and provide graduated hints. Check both required and forbidden behaviour for security tasks.

### Study schedules are not prerequisite-aware

“Four/six weeks at an hour a day” conflates studying, installing tools, pulling images, provisioning VMs, repairing lab defects, practising and taking simulations. There is no entry assessment or separate path for Linux beginners, application developers and existing cluster operators.

A short diagnostic would be more useful: navigate a shell, edit YAML, distinguish command/args, choose a namespace, inspect logs/events, reason about label matching, and recover a simple failure. Then provide a foundation route and a revision route. Make simulator preparation and reviewing mistakes explicit time commitments.

### Universal speed targets encourage the wrong optimization

The CKAD under-five-minute and CKA under-seven-minute rules cover tasks as different as creating a Secret and preparing a cluster. They are not calibrated assessments. Requiring every workload to be generated imperatively is also not realistic; generators do not cover every kind or field.

Measure correct outcomes using permitted references, with task-specific targets and pre-provisioned infrastructure. Include time to read, verify, record results and recover from mistakes. Require repeated success on variants, not one fast completion with the solution visible.

### Isolation and reset are underspecified

The hub promises CKA/CKS labs can run in any order, but CKA-04 requires CKA-03, and different labs edit shared cluster configuration or reuse `default/podinfo`. CKS labs reuse `/root/backup/kube-apiserver.yaml`; subsequent labs overwrite that file, so it is not a durable checkpoint for returning to an earlier chapter. Encryption changes persisted state and cannot be undone safely by blindly restoring an earlier API manifest.

CKS-09 and CKS-11 create and delete separate clusters, changing the active context; neither finishes by explicitly restoring `kind-k8s-lab` for the next chapter. CKAD-09 depends on an image from CKAD-08 despite the index saying 07–09 stand alone. Deleting the host image does not remove its already loaded node copy, but this still needs a clear prerequisite and a genuine standalone fallback.

Give every lab a state contract: cluster profile, namespace, objects consumed, objects created, node files changed, state retained, cleanup, and reset. Use per-lab backup paths and verify restored API health. Test fresh, sequential and repeat executions separately.

### The environment is not yet suitable for “anyone”

The first lab has an author-specific `file:///home/darshan/...` link. Host RAM/disk needs, Docker Desktop allocations, ARM support, rootless restrictions, privileged ports, shell expectations, GNU/BSD command differences, package installation and proxy/offline limitations are not collected into a clear supported-host matrix.

Examples include GNU `base64 -w0` on the host in CKA-06 and Linux-only direct Docker node IP access in CKAD-05. CKS kernel features and VM-based AppArmor deserve an explicit supported platform rather than an implication that every Docker environment is equivalent.

Do not promise universal portability. Choose and qualify a reference Linux profile; provide a tested alternate path where useful. Publish exact setup and preflight checks. A failed preflight should identify an environment problem before the learner begins the lesson.

### Expected output is too literal and sometimes overconfident

Random Pod names, rapid controller transitions, cache propagation, scheduling and version-dependent tool reports cannot be asserted as exact universal transcripts. Service requests are not guaranteed to alternate between backends. An empty Service can reject rather than silently time out depending on implementation. QoS affects eviction but does not replace priority and usage-relative-to-requests reasoning. A lack of events is a useful clue, not a universal proof that the scheduler is down.

Replace fragile sleeps and immediate reads with bounded condition checks. Explain which fields matter and what legitimate variation looks like. Prefer `curl` assertions on the expected response and explicit error checks to silently accepting output. Bound intentionally failing rollout waits and tell the learner how to return to the shell.

### Reference quality and assessment quality need separate labels

The wiki often has substantial concept coverage. That should count as a strength without being mistaken for validated exam practice. Replace **Good** with separate columns for explanation, guided lab, independent task, timed assessment and tested environment. A learner should be able to see exactly what evidence supports a readiness claim.

Remove unsupported exam-frequency claims such as what tasks “almost always” ask, and frame them as useful original practice scenarios unless backed by public guidance. Domain weights are public; the frequency of particular private tasks is not established by them.

## Exam-policy observations

The published versions and domain weights agree with the tracks on the review date. Do not “correct” CKAD 1.37 to match CKA/CKS 1.35 merely because the difference looks surprising. The verified baseline is documented in the companion requirements report and the [official FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks).

The hub's one-extra-browser-tab statement is not supported by the current allowed-resource page. Its generic CKS permission to read documentation for tools used in tasks is too broad, and it omits CKA's Gateway API resource. Give an exam-specific allowlist, distinguish task Quick Reference links, and state that browsing happens inside the exam VM. [Allowed resources](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed)

Teach the designated SSH-host workflow, tool availability on target hosts, exiting to base, and avoiding nested SSH, alongside namespace/context checks. Practising only against one local current context does not rehearse that operational discipline. [CKA/CKAD instructions](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad), [CKS instructions](https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks)

Retakes and simulator sessions need purchase-type qualifications: SINGLE registrations are exceptions. Reliance on an included external simulator is therefore not a complete assessment route for every reader. [FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks), [exam terms](https://docs.linuxfoundation.org/tc-docs/certification/exam-terms-of-service)

## Lab-by-lab observations

These judgments combine content inspection with only the targeted executions identified above. “Useful” does not mean fully runtime-certified.

| Lab     | Educational value                                              | Main correction or next step                                                                                                                                                                              |
| ------- | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CKAD-01 | Useful topology and component orientation                      | Pin the actual cluster image, fix the local file link, publish preflight and host requirements                                                                                                            |
| CKAD-02 | Good ownership-chain intent                                    | Fix selector/adoption demonstration; assert actual ownerReferences and clean the rogue Pod                                                                                                                |
| CKAD-03 | Useful rollout/rollback introduction                           | Preserve a defined exit state; bound failed rollout waits; measure availability if claiming zero downtime; add independent revision selection                                                             |
| CKAD-04 | Valuable env-versus-volume topic                               | Repair both apply/ownership defects; retain intended probes; prove both environment precedence and mounted-file propagation                                                                               |
| CKAD-05 | Good Service/DNS/EndpointSlice sequence                        | Correct host access and backend expectations; test targetPort/readiness too; release or reserve NodePort deliberately                                                                                     |
| CKAD-06 | Important subject with a broken central exercise               | Fix crash trigger/exit/logs; provide genuine repeated crash and OOM/probe cases; make metrics work                                                                                                        |
| CKAD-07 | Useful Kustomize introduction                                  | Handle SSA conflicts; remove duplicated manifest listings; migrate an actual deprecated manifest; restore meaningful data if calling it recovery                                                          |
| CKAD-08 | Practical, compact image workflow                              | Mark the nonexistent `build/Dockerfile.prod` command as an illustration; wait for port-forward; avoid job-number-dependent `kill %1`; give an independent artifact task                                   |
| CKAD-09 | Good host/path/TLS comparison and multiple failure modes       | Resolve NodePort collision, pin chart, satisfy image prerequisite, validate TLS with the supplied CA as well as inspection                                                                                |
| CKA-01  | Appropriate persistence objective                              | Replace Redis cache fiction with a real filesystem persistence test; clarify provisioner and node-loss limits                                                                                             |
| CKA-02  | Useful resources/topology/PDB ingredients                      | Fix CLI; examine Pending replacements after drain; do not assume topology constraints permit all replacements elsewhere; add HPA and real scheduling variants separately                                  |
| CKA-03  | Sensible VM install outline and honest untested status         | Execute on a pinned OS/runtime/CNI combination; assert node connectivity, DNS and cross-node workload traffic; make cri-dockerd a concrete optional exercise                                              |
| CKA-04  | Clear control-plane-first sequence                             | Repair predecessor state and PDB assumptions; execute end to end; verify workloads and final schedulability, not just versions                                                                            |
| CKA-05  | Valuable snapshot/restore and mount-path distinction           | Explain revision bump/compaction, membership and outside-controller caches; make stale-cache failure a deterministic scenario rather than a universal transcript                                          |
| CKA-06  | One of the strongest conceptual progressions                   | Isolate generated kubeconfig entries, support host base64 variants, wait for certificate issuance, add an independent permissions variant                                                                 |
| CKA-07  | Strong node-based troubleshooting foundation                   | Add prepared unknown faults and independent health checks; train repair rather than restoring a supplied backup; distinguish heuristics from proofs                                                       |
| CKS-01  | Good layered-hardening ambition                                | Correct image identity/capability claims; remediate the original Deployment; add effective RBAC, token, filesystem and network checks                                                                     |
| CKS-02  | Useful benchmark → remediation → rerun loop                    | Pin benchmark/job version; target the node that was actually scanned; rerun node checks after node remediation, not only master profiling checks                                                          |
| CKS-03  | Strong audit-policy and impersonation lesson                   | Add unknown log evidence with unrelated events; use unique backup files; make retention and sensitive-data assertions machine-checkable                                                                   |
| CKS-04  | Strong demonstration of at-rest encryption and key dependency  | Correct opening claim that etcd storage is simply base64; distinguish API representation from stored serialization; practise rotation and verify complete rewrite before key removal                      |
| CKS-05  | Useful separation of syscall, filesystem and profile controls  | Qualify defaults, correct PSS and AppArmor version wording, execute AppArmor on the designated node, test allowed as well as denied operations                                                            |
| CKS-06  | Useful custom-rule, override and runtime-ID workflow           | Pin Helm chart; provide a node-service practice variant; add unknown alerts and demonstrate effective containment; validate rules with their required macro dependencies                                  |
| CKS-07  | Good scanner/SBOM distinctions and digest awareness            | Pin tools; require an exact remediation policy rather than deleting just the outlier; include init-container images; run the repaired workload after linting                                              |
| CKS-08  | Useful CEL binding and fail-open/fail-closed comparison        | Supply a functioning webhook backend; verify TLS and positive/negative decisions; extend enforcement to init/ephemeral containers and relevant subresources                                               |
| CKS-09  | Good digest/signature distinction and tag-swap exercise        | Demonstrate unsigned-digest admission, then actual signature enforcement; pin versions and restore context; qualify claims that a tagged image always changes on restart because pull policy/cache matter |
| CKS-10  | Clear RuntimeClass → handler → runtime chain                   | Pin downloaded runtime; make handler setup repeatable; label installation work versus exam-shaped configuration; avoid treating a displayed kernel string alone as a security guarantee                   |
| CKS-11  | Valuable inter-node packet evidence and policy comparison      | Pin Cilium; use deterministic metadata fixture and baseline; restore context; explain CNI-specific identity/CIDR and host-network boundaries                                                              |
| CKS-12  | Good Linux investigative chain and service-removal distinction | Add independent unfamiliar service/identity tasks; keep shared-kernel warning; verify the node returns Ready; scope host-firewall/IAM gaps explicitly                                                     |

## A proportionate improvement plan

### Priority 1: make the existing learning path trustworthy

- Repair F01–F11 and reconcile the linked PDB and backup guidance.
- Replace universal testing and “Good” claims with actual evidence status.
- Pin and validate a reference environment; add functional metrics and policy preflight checks.
- Give every lab an explicit entry/exit state and reset path; isolate shared names or deliberately manage transitions.
- Run the recommended numeric sequences, study-plan sequences and supported fresh-lab entry points. Save actual checks and version manifests.

Acceptance evidence: the documented learner path completes without undocumented intervention; deliberately broken states are observable; the prescribed repair succeeds; cleanup leaves the stated next-lab prerequisites intact.

### Priority 2: fill high-value practice gaps

| Track  | First additional practice units                                                                                                                                      |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shared | Helm release lifecycle; behavioural NetworkPolicy matrix; working metrics and probes; scoped command/editing fluency                                                 |
| CKAD   | Jobs/CronJobs and multi-container patterns; blue/green and canary; ResourceQuota/LimitRange; custom-resource discovery                                               |
| CKA    | HPA under load; storage binding/reclaim/expansion on a suitable driver; operators; validated VM install/upgrade and selected HA operations; focused Gateway path     |
| CKS    | RBAC remediation with positive/negative checks; complete ImagePolicyWebhook; signature verification at admission; validated AppArmor; unknown incident investigation |

Do not add twenty pages of tool exposition where one short verified exercise would close the gap.

### Priority 3: establish evidence of independent competence

Add original, mixed timed sets for each exam. Each task should specify target host/context, namespace, constraints, expected artifact or state, time guidance and objective scoring. Solutions and hints should not be visible until requested. Include cases where creating the right object in the wrong namespace fails verification and where an overbroad security fix breaks a legitimate workload.

A practical readiness gate would require repeated success on unfamiliar variants, no unresolved core-domain gaps, correct use of permitted references, reliable final-state verification, and the ability to recover from one's own mistakes. External simulators remain useful calibration, but internal exercises should already establish these abilities.

### Priority 4: maintain technical evidence as the curriculum changes

Keep runnable fixture files beside the labs and make snippets derive from or be checked against them. Record tested OS, architecture, kind/node image, kubectl, runtime, CNI, chart/tool versions and date. Automatically catch unknown CLI flags, invalid API objects, missing dependencies and cross-lab port/name collisions where feasible; do runtime checks for behaviour that static validation cannot prove.

Preserve old lab URLs through aliases/redirects after moving them. The new files generally do not retain the deleted numbered paths as aliases; internal link validation alone does not preserve external bookmarks. Verify this in the site's routing/build before publishing.

The material has enough substance to improve in place. The most valuable next investment is correctness, repeatability and assessment—not additional breadth or stronger claims of readiness.
