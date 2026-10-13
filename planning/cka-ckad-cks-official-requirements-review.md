# CKA, CKAD and CKS: official requirements and curriculum review

Reviewed 2026-10-13. Scope: current public first-party exam requirements versus the worktree certification tracks; selected linked labs inspected for mapping accuracy. This is source research and static content review, not an execution report or a claim about confidential exam questions.

## Verified official baseline

| Exam | Domain weights                                                                                                                                              | Published environment |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| CKA  | Troubleshooting 30%; architecture/installation/configuration 25%; networking 20%; workloads/scheduling 15%; storage 10%                                     | Kubernetes 1.35       |
| CKAD | Design/build 20%; deployment 20%; observability/maintenance 15%; environment/configuration/security 25%; networking 20%                                     | Kubernetes 1.37       |
| CKS  | Cluster setup 15%; cluster hardening 15%; system hardening 10%; microservice vulnerabilities 20%; supply chain 20%; monitoring/logging/runtime security 20% | Kubernetes 1.35       |

The weights and objective families in the three local tracks agree with the published [CKA](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/), [CKAD](https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/) and [CKS](https://training.linuxfoundation.org/certification/certified-kubernetes-security-specialist/) pages. The CKA mapping includes newer Helm/Kustomize, Gateway API, autoscaling and operator objectives. CKAD explicitly includes Kustomize. CKS includes pod-to-pod encryption and supply-chain provenance. These are meaningful strengths: the tracks are not merely older syllabuses relabeled with a recent date.

All three allow two hours. Passing thresholds are 66%, 66%, and 67%, respectively. CKS requires having passed CKA; do not replace that wording with an unverified requirement for a currently unexpired credential. Certifications last two years. Versions above are the actual live values returned on the review date, including the difference between CKAD and the other two exams. The FAQ also gives an approximate four-to-eight-week update policy; do not infer a different live version from that policy. Standard eligible registrations include two simulator activations of 36 hours; SINGLE registrations do not. [LF FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks)

The advertised ordinary package includes a retake, but SINGLE/SINGLE-ATTEMPT purchases exclude it. [Exam terms](https://docs.linuxfoundation.org/tc-docs/certification/exam-terms-of-service)

These web pages are mutable. The review date is the workspace date, not a prediction about a future syllabus. Recheck authoritative pages before publishing or booking; preserve an exact curriculum revision in subsequent audits.

## Findings about exam guidance

### High: documentation access guidance is misleading

Evidence: `content/Kubernetes/certifications/index.md:113` says one extra browser tab is allowed, names Helm generically, and describes CKS access as the documentation of tools the tasks use.

Current policy permits documentation through the browser inside the exam VM. CKA/CKAD have Kubernetes docs/blog and Helm; CKA additionally has Gateway API. CKS instead lists Kubernetes docs/blog, Falco, bom CLI reference, etcd, the specified ingress-nginx configuration path, Cilium, and Istio. Task-specific Quick Reference links are an additional authorization channel. The reviewed policy does not establish the local page's one-extra-tab limit. A generic CKS tool-doc permission can send a learner to a site that is not generally permitted. Helm is not listed as a generally permitted CKS resource. [Allowed resources](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed)

Recommendation: maintain separate concise allowed-resource summaries with the live policy link, state that browsing occurs inside the exam VM, and explicitly distinguish task-provided links from general permission. Remove unsupported tab-count guidance rather than substituting another guessed number.

### Medium: shared exam workflow understates the SSH-host model

Evidence: `certifications/index.md:70` says aliases are available in the exam terminal; line 105 emphasizes switching context, and line 109 mentions leaving nodes after SSH.

Official CKA/CKAD instructions require each task on its designated SSH host, followed by exit to base; nested SSH is unsupported. The tools and aliases are installed on the target hosts, not base. A learner may otherwise configure the wrong shell or expect kubectl on base. Add explicit host → namespace/context → task → verify → exit practice and explain per-host shell setup. [CKA/CKAD instructions](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad)

CKS uses the same designated-host/return-to-base model. [CKS instructions](https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks)

### Medium: registration benefits are overgeneralized

Evidence: `certifications/index.md:48-49` promises one retake and two simulator sessions without a package qualification; every track's gap table refers readers to the included simulator.

Add the SINGLE exception and an alternative readiness route for learners who do not have simulator access. This is an access issue for a resource intended for anyone, rather than just a pricing footnote. Sources: LF FAQ and terms above.

### Medium: version compatibility is not an executable contract

Evidence: `labs/ckad/01-cluster-setup.md:38` accepts kubectl 1.35–1.37, while line 99 expects Kubernetes 1.37. The command on line 92 does not select a node image; the YAML has no image pins. Installed kind version therefore determines the default image rather than the claimed baseline.

Kubernetes supports kubectl within one minor version of the API server. A permitted 1.35 client against the expected 1.37 server falls outside that window. Pin and verify both cluster and tool versions, with a documented profile for each exam; do not confuse a wiki-wide version statement with actual runtime selection. [Version-skew policy](https://kubernetes.io/releases/version-skew-policy/)

## Curriculum coverage is overstated

All 16 domain rows across the tracks say Good, despite explicitly acknowledged gaps. That is an unsupported readiness summary. A topic link, a worked demonstration, an independent exercise, and a timed verified task are different forms of evidence. The material should grade these separately.

### CKA

The track openly records missing hands-on HPA, Helm lifecycle, operator installation, and HA control-plane work (`cka.md:162`). Those are direct objectives, not optional advanced enrichment. Its installation and upgrade labs are explicitly not run end to end. A learner therefore has no basis to interpret the 25% architecture domain or the 15% workloads domain as fully rehearsed. Gateway has an existing runbook, so absence of a numbered lab alone is not evidence of absence of practice; evaluate that runbook's execution and tasks before counting it as a gap.

Recommended missing assessment units: HPA with actual load and metrics diagnosis; Helm install/values/upgrade/rollback; install an operator and validate a reconciled custom resource; HA join and one-control-plane failure; independently verified install/upgrade. Keep extension-interface understanding distinct from requiring a huge CNI/CSI/CRI installation course.

The under-seven-minutes readiness rule applies to heterogeneous drills, including preparing a fresh node and initializing a cluster. It needs per-task timing and prerequisites rather than a universal number. Requiring etcd restoration without documentation also tests memorization more heavily than the published open-documentation environment requires. Assess speed with permitted references, persistence of the restored data, and component recovery.

### CKAD

The track acknowledges no dedicated Helm or multi-container/Jobs/CronJobs labs (`ckad.md:151`). It maps the full workload-selection objective to a Deployment lab. This cannot demonstrate selecting and operating the other workload controllers.

Two less-visible mapping problems were confirmed by reading the target labs: `ckad.md:62` maps blue/green and canary deployment strategies to CKAD-03, which teaches rolling updates/rollback and has no blue/green/canary tasks. `ckad.md:110` maps requests, limits, and quotas to CKA-02, which teaches requests/limits, QoS, topology and PDBs but does not create ResourceQuota or LimitRange. Add those omissions to the gap inventory; they are currently obscured by plausible links.

The CRD/operator objective points to drills, and a learner must still obtain a starting resource/operator and know what completion looks like. A concrete prepared scenario is stronger than an unbounded instruction to install an arbitrary operator.

The ready-when requirement to generate any workload imperatively (`ckad.md:178`) is too broad: kubectl generators do not cover every workload kind. Teach a mix of generators, explain, official examples, and editing existing manifests, then measure correctness and time.

### CKS

The additional labs cover many current objective families, and the gap table is candid about AppArmor not being executed, absent admission-time signature checks, missing least-privilege IAM exercises, and lack of end-to-end incident investigation (`cks.md:162`). Nevertheless, every domain reads Good.

The important distinction for supply-chain work is between verifying a signature manually and the cluster enforcing a signature policy. The former is useful evidence but cannot prove the latter. Similarly, detecting a known test event is weaker evidence of attack investigation than working from an unfamiliar log/alert corpus to identify actor, workload, timeline, and containment.

Do not count every missing tool variant as a mandatory exam deficiency: the CKS objective is pod-to-pod encryption, with Cilium/Istio examples. A validated Cilium encryption lab may satisfy substantial practice here without implementing every service mesh. Conversely, `cks.md:117` treats encryption or a mutual-authentication policy as interchangeable drills. They should teach and verify confidentiality and identity separately. Cilium's design explicitly separates these channels. [Cilium mutual-authentication design](https://github.com/cilium/design-cfps/blob/main/cilium/CFP-28986-mutual-auth-updates.md)

## Learning and assessment implications

The central weakness is not absence of links. It is lack of evidence that learners can transfer a recipe into an unfamiliar, timed, correctly scoped task. All tracks acknowledge that they have no timed mock. External simulations are a useful complement, but cannot validate the internal curriculum for readers without access.

A proportionate improvement is one baseline task, one altered task, and one failure-recovery task for each objective, with supplied starting state, success criteria, permitted references, realistic time budget and repeatable reset. Map each objective to actual sections and checks rather than simply entire documents. Include a small two-hour mixed practice set per exam with task-specific SSH hosts, namespaces, file destinations and scoring criteria. These should be original practice tasks, not claimed reconstructions of private exam content.

The four- or six-week plans at an hour per day assume background fluency without diagnosing it. Offer an entry test and suggested extra foundation work for people who cannot yet navigate Linux, edit YAML, inspect container logs, reason about selectors, or recover from an API outage. Distinguish formal exam prerequisites from learning prerequisites. Completion of a reading schedule is not a pass prediction.

## Review limits

No cluster labs or simulator were run for this report. No percentage of likely exam questions or pass probability is inferred. Objective-level gaps are judged against public competencies, not rumors about question frequency. The exact current CNCF curriculum PDF revision was not downloaded; the public Linux Foundation competency lists were the operative comparison and agree with the tracks at the objective-family level. Lab execution defects and broader site/link validation belong to the companion technical review.
