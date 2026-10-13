---
title: "AWS Systems Manager Patch Manager"
description: "Patch Manager evaluates/installs OS patches on supported managed nodes."
tags:
  - aws/management-governance
date: 2026-10-12
---

# AWS Systems Manager Patch Manager

Patch Manager evaluates/installs OS patches on supported managed nodes. Baseline compliance is evidence about a configured policy, not proof that a system has no vulnerabilities or that an application remains healthy.

Prerequisites: [[AWS/management-governance/systems-manager/README|Systems Manager]], [[AWS/security/iam/README|IAM]] and approved backup/change procedures.

## Policy and OS boundaries

Choose the supported organization-wide Quick Setup patch-policy workflow for multi-account/Region rollout where appropriate. Patch policies do not use patch groups. Traditional patch groups map one baseline per operating-system type, not one baseline for an entire mixed-OS fleet; newer account/Region pairs also have console availability restrictions.

OS/product filters and approval mechanisms are OS-specific. Ubuntu cannot reliably use automatic seven-day release-date approval because repository release dates are unavailable. Use supported filters plus an externally controlled repository/release/approval process if a soak period is required. Do not reuse Amazon Linux approval assumptions for every Linux distribution.

Native package managers can install/update/remove dependencies. RejectedPatchesAction ALLOW_AS_DEPENDENCY can permit a rejected package as a dependency; BLOCK can prevent an otherwise approved update from succeeding. A baseline is not an absolute application-package allowlist.

## Rollout and change control

Separate scan from install. Use development/canary/production stages, maintenance windows or policy schedules, bounded concurrency/error thresholds, notifications and an explicit approval owner. RebootOption NoReboot defers reboot but may leave required updates incomplete; define the subsequent reboot/compliance verification.

Hybrid nodes need supported enrollment, repository reachability and credentials. Multi-account roles/trusted access, regional configuration and log/report ownership require deliberate setup; a tag alone does not establish central authority.

## Canary exercise

Use one supported disposable node, current backups and a rollback plan. Select a baseline matching its real OS/product. Run a scan, inspect missing/installed/rejected status and capture the baseline ID/version used. Install only in the sandbox with bounded concurrency and deliberate reboot behavior.

```bash
aws ssm send-command --instance-ids i-0123456789abcdef0 \
  --document-name AWS-RunPatchBaseline \
  --parameters '{"Operation":["Scan"]}' \
  --max-concurrency 1 --max-errors 0
```

This CLI v2 call requires an authorized managed sandbox node; poll the returned command/invocation with timeout and inspect terminal failures. Scan is not installation. Demonstrate a missing prerequisite/repository failure safely and ensure it appears in the report.

After approved installation/reboot, rescan, run application health checks and compare evidence. Patching success is not itself rollback capability. Remove sandbox policy associations/windows/resources only after reviewing shared targets; retain audit evidence under the approved log policy.

## Production scenario: a thousand-node mixed fleet

Assume multiple AWS accounts/Regions plus authorized Azure/hybrid nodes, Ubuntu 20/22/24 LTS, supported Amazon Linux variants and Windows Server versions. Some jump/log servers can patch/reboot automatically; sensitive production servers require review. Verify current OS/agent support for each actual node before adopting this plan.

```text
Fleet inventory and owners
  → OS-specific policy/baseline + approved repositories
  → sandbox/dev validation
  → canary install/reboot + health tests
  → routine weekly rollout OR sensitive approval gate
  → post-reboot scan + package/report evidence
  → exception/rollback follow-up
```

Native package managers can resolve dependencies, and rejected patches may be installed as dependencies under the configured action. A baseline describes approved patch policy, not all permissible software execution.

## Baselines, targeting and schedules compared

| Concern      | Decision                                                                                                   |
| ------------ | ---------------------------------------------------------------------------------------------------------- |
| WHAT         | Supported OS-specific classifications/severity/explicit approvals and rejection/dependency behavior        |
| WHERE        | Quick Setup patch-policy targets or traditional supported groups/associations; not both assumed equivalent |
| WHEN         | Scan/install schedules, maintenance windows and change cutoff                                              |
| WHO approves | Application/security owner for sensitive waves                                                             |
| REBOOT       | Explicit allowed/required timing, health checks and fallback                                               |
| EVIDENCE     | Baseline/policy version, command execution, package states, timestamps and exceptions                      |

For organization-scale operations, evaluate supported Quick Setup patch policies across intended accounts/Regions. They do not use patch groups. For a traditional setup, patch-group mapping is per OS type; one mixed-OS tag does not require one incompatible baseline for every node.

## OS-specific policy matrix

| OS family    | Important differences                                              | Approval approach                                                     |
| ------------ | ------------------------------------------------------------------ | --------------------------------------------------------------------- |
| Ubuntu       | Repository dates do not support generic seven-day auto-approval    | Controlled repository/release or explicit supported approval workflow |
| Amazon Linux | Match actual AL2/AL2023 product/OS support                         | Supported baseline rules and measured canary soak                     |
| Windows      | Update classifications/KBs, supported editions and reboot behavior | Supported approval/rejection and documented change windows            |
| Azure/hybrid | Supported agent/role/enrollment/repository connectivity            | Same justified OS policy, separately verified hybrid identity/network |

Do not promise kernel exclusion means no reboot is needed. Other packages can require reboot; a deferred reboot can leave compliance/application state incomplete. Dependency BLOCK can fail an approved patch transaction—report that explicitly rather than silently widening approvals.

## Routine and sensitive rollout plans

For jump/log/routine nodes, validate dev/canary first, then install during the approved weekly window with bounded concurrency/error threshold, deliberate reboot and application checks. Ensure redundancy/capacity so simultaneous reboot does not remove the service or its observability.

For sensitive nodes, scan first and generate a proposed change report. An owner reviews package list, known issues, backup/recovery readiness and application impact. Approval authorizes a controlled install wave; it is not a blanket permanent bypass. Record declined/deferred packages and their risk/expiry owner.

At a thousand nodes, begin with a small representative canary per OS/application cohort. Set concurrency from service availability rather than a universal percentage, and stop/escalate if failures exceed threshold. Stagger accounts/Regions and verify repository bandwidth/availability.

## Package-level reporting and verification

Capture node ID, account/Region, OS, baseline/policy snapshot, operation/CommandId, start/end time, status, missing/installed/rejected/failed patches, reboot requirements and post-install health result. Distinguish “compliant at scan time” from “this week's command installed these packages.” Package state/installation time and command logs have different meanings.

A read-only package-state inspection uses the actual managed-node ID:

```bash
aws ssm describe-instance-patches --instance-id i-0123456789abcdef0
aws ssm describe-instance-patch-states \
  --instance-ids i-0123456789abcdef0
```

These calls require permissions and complete pagination. For hybrid nodes use the actual supported managed-node ID, not an EC2-shaped placeholder. Central report storage/export needs an authorized, encrypted destination and retention/access policy; an invented one-command CSV exporter is not implied.

After patch/reboot, rescan and run application health checks. Compare per-wave evidence, track inaccessible nodes as failures/exceptions rather than silently excluding them, and reopen unresolved risk with an owner. Preserve audit evidence while removing only disposable test associations/windows/nodes.

## Recovery and operating limits

Have a tested snapshot/backup or application redeployment/recovery path before installing. Package rollback can be engine/repository/application-specific; Patch Manager installation success is not a guarantee that every package can be automatically downgraded.

Account/Region roles, hybrid Session/Run Command pricing, log storage and backup charges belong in the design. At scale, avoid one unbounded command, custom scripts duplicating all supported policy functionality, and “no reboot forever” policies that leave systems half-updated.

## References

- [Quick Setup patch policies](https://docs.aws.amazon.com/systems-manager/latest/userguide/quick-setup-patch-manager.html)
- [Patch groups](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-patch-patchgroups.html)
- [Patch baseline rules/dependencies](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager-baseline-rules.html)
- [Patch Manager OS prerequisites](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager-prerequisites.html)
- [AWS-RunPatchBaseline behavior](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager-aws-runpatchbaseline.html)
