# EKS Operator Handbook — Specification

**Revised:** 2026-10-20
**Target:** `content/Kubernetes/eks/operator-runbook/`
**Status:** Replaces the previous subsystem-chapter spec. That version produced 29 cautious essays with almost no commands, expected output or decisions. This spec is task-first.

## Who it is for

An on-call engineer or platform operator who already knows Kubernetes and AWS basics and needs to **act**: stop an outage, carry out a planned change, or look up a limit. Concepts are taught elsewhere in the wiki (`Kubernetes/concepts/`, `Kubernetes/eks/*`); the handbook links to them and does not re-teach them.

## Structure

```
operator-runbook/
  index.md          symptom → runbook lookup, procedure list, reference list
  runbooks/         one failure per note (unplanned work)
  procedures/       one planned change per note
  reference/        limits, formulas, log locations, standard command sets
```

- **Runbook**: one symptom or failure family, e.g. "Pods stuck ContainerCreating: IP exhaustion". Name files after the symptom an operator sees, not the subsystem.
- **Procedure**: one planned change, e.g. "Upgrade the control plane one minor version", "Rotate a managed node group AMI".
- **Reference**: tables and copy-paste blocks used by many runbooks, e.g. max-pods formula, ENI limits, node log paths on AL2023 and Bottlerocket, first-five-minutes command set.

Target size: 25–35 runbooks, ~10 procedures, 4–6 reference notes. Add a runbook only for a failure that actually happens; don't create one per subsystem for coverage.

## Runbook template

Every runbook uses these sections in this order. Omit a section only if it truly does not apply.

1. **Header line** — applies to (compute models / CNI / versions), typical severity, and test status (see "Test status").
2. **Symptoms** — the alerts, events and error strings the operator will see, quoted verbatim in code so they can be searched.
3. **Impact** — what is and isn't broken (e.g. running Pods keep working, new Pods can't start).
4. **Triage** — numbered steps. Each step is a command plus what to look for: **Expect** (healthy) and **If** (unhealthy → meaning). Steps go from cheapest/broadest to narrowest.
5. **Diagnosis** — a table: signal → cause → fix section.
6. **Fix** — one subsection per cause. Each has the commands, then **Verify** and **Undo** (how to revert the fix, or "none" with a reason).
7. **Verify recovery** — the end-to-end check that users are fine, not just that the command succeeded.
8. **Escalate** — when to open an AWS Support case and exactly what to attach.
9. **Prevent** — the alert or design change that would have caught or avoided this.
10. **Background** — links to the wiki notes that explain the mechanism.

## Procedure template

Header line → **When to use** → **Pre-checks** (commands with expected output; any failure is a stop) → **Steps** (numbered, each with a checkpoint) → **Abort criteria and rollback** → **Post-checks** → **Clean-up** (temporary changes to revert) → **Background**.

## Writing rules

- **Lead with the action.** Say what to do and what you'll see. A warning goes in the step it applies to, in one sentence, with the reason. No paragraphs of general caution.
- **Be specific to EKS.** Use real error strings, API names, log paths, metric names, default values and formulas. If a sentence would read the same for GKE, cut it or make it concrete.
- **State facts.** Defaults, limits and behaviour for the wiki's Kubernetes baseline (currently 1.37, see `content/Kubernetes.md`) are stated plainly. Where a value varies by instance type or version, give the formula or the command that returns it.
- **Commands are copy-paste ready.** Use the variables in the reference note (`$CLUSTER`, `$REGION`, `$NODE`, `$NS`, …). Show the command that produces each input you need, e.g. how to get `$INSTANCE_ID` from `$NODE`.
- **Name the managed-add-on trap.** When a fix changes an EKS-managed add-on, do it through `aws eks update-addon --configuration-values`, not by editing the DaemonSet, or the next add-on update overwrites it.
- **Name the reconciler trap.** If GitOps or an owning controller will revert a live fix, say so in that step and say how to pause it.
- **Destructive steps are marked.** Prefix with **⚠ Destructive:** and state the precondition (e.g. "only after the instance is confirmed stopped").
- **No boilerplate.** No per-note validation paragraph, no generic "use the documentation" footer. Primary sources go inline where a fact comes from them, or in Background.
- **Link, don't duplicate.** If a fix is a planned change with its own procedure, link to the procedure.

## Test status

One line in each note's header: `Tested: <what was run, where, versions>` or `Tested: not run on a live cluster; commands checked for syntax`. Never imply a runtime test that did not happen. `index.md` keeps a table of every note and its test status, updated when it changes.

## Status

**Complete as of 2026-10-20.** The handbook has 24 runbooks, 11 procedures and 5 reference notes. The 29 `NN-*.md` subsystem chapters were retired the same day. Their concrete content moved into the new notes: chapter 12 became `procedures/roll-back-a-deployment`, chapter 13 `runbooks/hpa-not-scaling`, and chapters 24–26 the Windows, GPU and hybrid-node runbooks. Their concept material is covered by the existing `Kubernetes/eks/*` and `Kubernetes/concepts/` notes, which the index links under "Concepts". Nothing outside the folder linked to the chapters or used their aliases.

Node group update failures, add-on update failures and upgrade-blocking insights were folded into their procedures rather than given separate runbooks.

### Facts checked against documentation (2026-10-20)

| Claim                                    | Result                                                                                                                                                                                                                                                                                                                    | Source                                                                                                                                     |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| EKS control-plane rollback               | **Exists** (the pages had hedged it away): one minor version back, within 7 days of an in-place upgrade, gated by `ROLLBACK_READINESS` insights. Nodes and add-ons first; Auto Mode nodes handled by EKS; Fargate not supported                                                                                           | [Roll back a cluster](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html)                                              |
| Add-on downgrade                         | **Supported** with `update-addon --addon-version <earlier>` (corrected; the pages said it might be rejected)                                                                                                                                                                                                              | Same page, "Rollback and add-ons"                                                                                                          |
| Insights refresh                         | Every 24 h; on demand with `aws eks start-insights-refresh`                                                                                                                                                                                                                                                               | Same page                                                                                                                                  |
| etcd size                                | Provisioned at 8 GiB (upstream recommended maximum)                                                                                                                                                                                                                                                                       | [EKS best practices: known limits](https://docs.aws.amazon.com/eks/latest/best-practices/known_limits_and_service_quotas.html)             |
| Extended support price                   | $0.60 vs $0.10 per cluster-hour                                                                                                                                                                                                                                                                                           | [AWS blog: extended support pricing](https://aws.amazon.com/blogs/containers/amazon-eks-extended-support-for-kubernetes-versions-pricing/) |
| Scheduler and controller-manager metrics | `/apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics` and `.../kcm/...`, on 1.28+                                                                                                                                                                                                                                    | [Fetch control plane raw metrics](https://docs.aws.amazon.com/eks/latest/userguide/view-raw-metrics.html)                                  |
| `NodeDiagnostic`                         | `eks.amazonaws.com/v1alpha1`, presigned PUT URL destination; `node` destination from agent v1.6.1                                                                                                                                                                                                                         | [Retrieve node logs](https://docs.aws.amazon.com/eks/latest/userguide/auto-get-logs.html)                                                  |
| CoreDNS add-on `autoScaling`             | Exists for CoreDNS v1.9+; `enabled`, optional `minReplicas` and `maxReplicas`                                                                                                                                                                                                                                             | [Scale CoreDNS Pods](https://docs.aws.amazon.com/eks/latest/userguide/coredns-autoscaling.html)                                            |
| `nodeadm debug`                          | Exists; validates networking and credential requirements                                                                                                                                                                                                                                                                  | [Troubleshooting hybrid nodes](https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes-troubleshooting.html)                         |
| Karpenter event wording                  | "incompatible with nodepool" was **wrong**; current messages are `Failed to schedule pod, incompatible requirements, ...`, `no instance type met ...`, `all available instance types exceed limits for nodepool`, `node limits have been exhausted for nodepool`; Nominated is `Pod should schedule on: nodeclaim/<name>` | `kubernetes-sigs/karpenter` main: `pkg/controllers/provisioning/scheduling/{scheduler,nodeclaim,events}.go`                                |

### Next

Exercise the runbooks on a throwaway kind or EKS cluster where possible, and update each page's "Tested" line and the index column. Add runbooks only for failures that actually happen.

## Repository requirements

- Required frontmatter (`title`, `tags`, `date`, `description`), one H1, quoted descriptions containing colons or dashes.
- Full-path wikilinks with aliases; escape pipes in tables.
- Every new note linked from `index.md` (no orphans).
- Run `npm run format`, `npm run check:content`, and `npm run check` after changes.
- Do not commit without the user's instruction.
