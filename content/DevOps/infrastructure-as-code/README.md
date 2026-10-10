---
title: Infrastructure as Code
tags: [devops, infrastructure-as-code, terraform, opentofu, ansible]
date: 2026-10-10
description: What infrastructure as code is for, the distinctions that matter — declarative versus imperative, provisioning versus configuration, plan-and-apply versus continuous reconciliation — and a map of the tools with guidance on choosing.
---

# Infrastructure as Code

Infrastructure as code (IaC) means describing infrastructure in files that are versioned, reviewed and applied by a tool, instead of being clicked together in a console. The point is not the files; it is what they make possible:

- **Reproducibility** — the same definition builds staging and production, and rebuilds either after a disaster.
- **Review** — a change to a firewall rule is a pull request with a diff, not something discovered later.
- **History** — who changed what, when and why is in Git.
- **Automation** — environments can be created and destroyed by pipelines.

## The distinctions that matter

### Declarative or imperative

|            | Declarative                                               | Imperative                                           |
| :--------- | :-------------------------------------------------------- | :--------------------------------------------------- |
| You write  | The desired end state                                     | The steps to get there                               |
| The tool   | Works out the difference and what to change               | Runs your steps in order                             |
| Re-running | Safe: nothing changes if reality already matches          | Safe only if every step was written to be idempotent |
| Examples   | Terraform, OpenTofu, CloudFormation, Kubernetes manifests | Shell scripts, most CLI automation                   |

General-purpose-language tools such as Pulumi and the CDK look imperative but are declarative underneath: the program builds a desired-state graph, and an engine diffs it.

### Provisioning or configuration

| Layer              | Question                                    | Typical tools                                                                                                                        |
| :----------------- | :------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------- |
| **Provisioning**   | Which cloud resources exist?                | [[DevOps/infrastructure-as-code/terraform\|Terraform]], [[DevOps/infrastructure-as-code/opentofu\|OpenTofu]], CloudFormation, Pulumi |
| **Image building** | What is baked into a machine image?         | [[DevOps/infrastructure-as-code/packer\|Packer]], container builds                                                                   |
| **Configuration**  | What is installed and running on a machine? | [[DevOps/infrastructure-as-code/ansible\|Ansible]], cloud-init                                                                       |
| **Workload**       | What runs on the platform?                  | Kubernetes manifests, Helm, Kustomize                                                                                                |

The layers blur — Terraform can run scripts, Ansible can create cloud resources — but each tool is much better at its own layer.

### Mutable or immutable

A **mutable** server is patched and reconfigured in place over its life. An **immutable** one is never changed: a new image is built and the server is replaced. Immutable infrastructure removes configuration drift and makes rollback trivial, at the cost of needing a build pipeline and stateless servers. Containers made this the default for applications; node images and auto scaling groups extend it to the hosts.

### Plan-and-apply or continuous reconciliation

|          | Plan and apply                         | Continuous reconciliation                                                                                                                                   |
| :------- | :------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Runs     | When someone or a pipeline triggers it | All the time, in a control loop                                                                                                                             |
| Drift    | Detected at the next plan              | Corrected automatically                                                                                                                                     |
| Preview  | An explicit plan to review             | Usually none                                                                                                                                                |
| Examples | Terraform, OpenTofu, CloudFormation    | Kubernetes controllers, [[Kubernetes/eks/automation/control-planes/crossplane\|Crossplane]], [[Kubernetes/eks/automation/control-planes/ack\|ACK]], Argo CD |

A reviewed plan is valuable for foundations where a mistake is expensive. Continuous reconciliation suits resources that follow an application's lifecycle and are requested self-service.

## State

A declarative tool needs to know which real resources belong to which definitions. Kubernetes keeps that in its API server. Terraform and OpenTofu keep it in a **state file**, and how that file is stored, locked and split determines whether a team can work safely. That deserves its own note: [[DevOps/infrastructure-as-code/terraform-state-and-collaboration|state and collaboration]].

## Choosing tools

| Situation                                                      | Reasonable choice                                                                                                    |
| :------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------- |
| Cloud foundations: accounts, networks, clusters, databases     | Terraform or OpenTofu                                                                                                |
| AWS-only shop that wants native support and no state file      | [[AWS/management-governance/cloudformation/README\|CloudFormation]] or [[AWS/management-governance/cdk/README\|CDK]] |
| Developers who want loops, types and tests in a real language  | Pulumi or CDK                                                                                                        |
| Configuring VMs, network devices, or anything reached over SSH | Ansible                                                                                                              |
| Golden machine images                                          | Packer                                                                                                               |
| Self-service infrastructure through the Kubernetes API         | Crossplane, ACK, [[Kubernetes/eks/automation/control-planes/kro\|kro]]                                               |
| Kubernetes workloads                                           | Helm or Kustomize, delivered by [[Kubernetes/guides/delivery/gitops/basics\|GitOps]]                                 |

Most organisations end up with two or three of these, one per layer. The mistake is using one tool for every layer because it is the one the team knows.

## Practices that apply to all of them

1. **Everything through version control and a pipeline.** Console changes are for emergencies and are back-ported immediately.
2. **Review the plan, not only the code.** The diff of what will happen in the real account is what matters.
3. **Small blast radius.** Split definitions so one mistake cannot touch everything; separate environments and separate lifecycles.
4. **No secrets in code or state where avoidable.** Reference a secret store. See [[DevOps/devsecops/stage1-code/06-secrets-detection|secrets detection]].
5. **Policy as code.** Check plans against rules — encryption on, no public buckets, mandatory tags — before apply, with OPA/Conftest, Checkov or Sentinel. Part of [[DevOps/devsecops/README|DevSecOps]].
6. **Test.** Static validation and linting on every commit; plan in CI; ephemeral environments for modules that matter.
7. **Detect drift** on a schedule and treat it as a defect.
8. **Pin versions** of tools, providers and modules, and upgrade deliberately.
9. **Tag everything** with owner, environment and cost centre — see [[AWS/cost-management/cost-allocation-tags|cost allocation tags]].

## Notes in this section

- [[DevOps/infrastructure-as-code/terraform|Terraform]] — the workflow, language, providers and modules
- [[DevOps/infrastructure-as-code/terraform-state-and-collaboration|Terraform state and collaboration]] — backends, locking, splitting state, team workflows
- [[DevOps/infrastructure-as-code/opentofu|OpenTofu]] — the open-source fork and where it differs
- [[DevOps/infrastructure-as-code/ansible|Ansible]] — agentless configuration management
- [[DevOps/infrastructure-as-code/packer|Packer]] — building machine images

## Related

- [[DevOps/platform-engineering/README|Platform engineering]] — IaC modules as the building blocks of golden paths
- [[DevOps/ci-cd/pipeline-design|Pipeline design]]
- [[Azure/governance/policy|Azure governance]] and [[GCP|GCP]] — the provider-native equivalents
- [[Kubernetes/eks/getting-started/cluster-creation|Creating an EKS cluster]]

## Further reading

- [Infra as Code (video)](https://youtu.be/IW-cPuydd5s)
