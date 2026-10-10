---
title: EKS Support Resources
tags: [eks, troubleshooting, support, references]
date: 2026-05-17
description: Where to get help with EKS and how to ask well — official documentation, AWS Support plans and what to put in a case, diagnostic tooling, community channels, the source repositories and how to track changes and roadmap.
---

# EKS Support Resources

When [[Kubernetes/eks/troubleshooting/README|your own troubleshooting]] runs out, the speed of the answer depends mostly on where you ask and what evidence you bring. This page lists the places worth knowing and how to use them.

## Official documentation

| Resource                                                                  | Use it for                                                                                                              |
| :------------------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------------------------- |
| [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)       | How each feature works and is configured                                                                                |
| [EKS API Reference](https://docs.aws.amazon.com/eks/latest/APIReference/) | Exact request and response shapes for automation                                                                        |
| [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/) | Opinionated guidance on security, reliability, networking, scaling, cost and upgrades — the most useful single document |
| [EKS Workshop](https://www.eksworkshop.com/)                              | Hands-on labs for almost every feature ([source](https://github.com/aws-samples/eks-workshop-v2))                       |
| [EKS FAQs](https://aws.amazon.com/eks/faqs/)                              | Pricing, limits and support-policy questions                                                                            |

The best-practices guide is worth reading in full once, not only when something breaks.

## AWS Support

A paid [support plan](https://aws.amazon.com/premiumsupport/) is the only channel with a response-time commitment and the only one that can look at the managed control plane, which you cannot see into.

**What AWS Support can do:** inspect control-plane health and logs, confirm service-side issues, explain EKS and add-on behaviour, and escalate to the service team.

**What it will not do:** debug your application, or support heavily customised third-party components beyond best effort.

### Writing a case that gets answered quickly

Include, in the first message:

1. **Cluster ARN and region**, Kubernetes version, platform version.
2. **What you expected and what happened**, with exact error text.
3. **When it started** (UTC) and **what changed** around then.
4. **Scope**: one pod, one node, one zone, or everything.
5. **Resource identifiers**: instance IDs, node names, pod names and namespaces, add-on versions, request IDs from failed API calls.
6. **What you have already ruled out.**
7. **Diagnostic bundles** (below).

Choose severity honestly — "production system down" gets a fast response and should be reserved for that. For anything urgent, ask for a call or chat rather than waiting on email.

### Diagnostic tooling

| Tool                                                                      | What it produces                                                                                            |
| :------------------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------------- |
| **EKS log collector** script (in the `awslabs/amazon-eks-ami` repository) | A tarball of kubelet, containerd, CNI, iptables, kernel and system logs from a node — attach it to the case |
| `AWSSupport-TroubleshootEKSWorkerNode` (Systems Manager automation)       | An automated check of why a node will not join                                                              |
| **Cluster insights**                                                      | Upgrade-readiness and configuration findings                                                                |
| **EKS observability dashboard**                                           | Control-plane metrics and health in the console                                                             |
| **VPC Reachability Analyzer**                                             | Whether a network path exists between two ENIs                                                              |
| `aws eks describe-addon` / `describe-nodegroup`                           | Health issues reported by the service itself                                                                |

Enable [[Kubernetes/eks/observability/logging/control-plane-logs|control plane logging]] before you need it; Support will ask for those logs and they cannot be produced retroactively.

## Community

| Channel                                                                 | Good for                                                                |
| :---------------------------------------------------------------------- | :---------------------------------------------------------------------- |
| [AWS re:Post — EKS](https://repost.aws/topics/T27ZZ2YVR8W5J/amazon-eks) | Searchable Q&A; AWS staff answer there                                  |
| [Kubernetes Slack](https://kubernetes.slack.com/)                       | `#eks`, plus channels for individual projects (`#karpenter`, `#cilium`) |
| [AWS Developers Slack](https://aws-slack.com/)                          | General AWS discussion                                                  |
| Project GitHub issues                                                   | Bugs in a specific component — search before filing                     |

Community channels are best for "how do I" and "has anyone seen this" questions. They are not a place for account-specific details or anything urgent. Remove account IDs, ARNs and secrets from anything you paste.

## Source repositories

Much of EKS is open source, and reading the code or the issue tracker often answers a question faster than waiting.

| Repository                                                                          | Contains                                                       |
| :---------------------------------------------------------------------------------- | :------------------------------------------------------------- |
| `aws/amazon-vpc-cni-k8s`                                                            | The [[Kubernetes/eks/networking/vpc-cni/README\|VPC CNI]]      |
| `awslabs/amazon-eks-ami`                                                            | The node AMI build and `nodeadm`                               |
| `kubernetes-sigs/aws-load-balancer-controller`                                      | ALB and NLB integration                                        |
| `kubernetes-sigs/aws-ebs-csi-driver`, `aws-efs-csi-driver`                          | [[Kubernetes/eks/storage/README\|Storage drivers]]             |
| `aws/karpenter-provider-aws`                                                        | [[Kubernetes/eks/compute/karpenter/README\|Karpenter]] for AWS |
| [`aws-controllers-k8s/community`](https://github.com/aws-controllers-k8s/community) | [[Kubernetes/eks/automation/control-planes/ack\|ACK]]          |
| [`aws/eks-charts`](https://github.com/aws/eks-charts)                               | Helm charts for AWS components                                 |
| [`aws/eks-distro`](https://github.com/aws/eks-distro)                               | The Kubernetes distribution EKS is built from                  |

## Staying ahead of changes

- **Roadmap**: the public `aws/containers-roadmap` repository shows what is planned and lets you vote; the [EKS Distro project board](https://github.com/aws/eks-distro/projects/1) tracks its releases.
- **Version calendar**: the Kubernetes release calendar in the user guide lists end-of-standard-support and end-of-extended-support dates for each version. Put them in your own calendar.
- **AWS Health Dashboard**: account-specific notices — scheduled maintenance, deprecations and required actions for your clusters. Route these events through EventBridge to the team's channel.
- **Release notes**: platform versions, add-on versions and AMI releases each have their own changelog.
- **What's New feed** for EKS feature launches.

Deadlines missed here turn into forced upgrades — see [[Kubernetes/eks/cluster-upgrades/upgrade-process|the upgrade process]].

## Before asking anyone

A short checklist that resolves a surprising share of problems:

- [ ] Read the events: `kubectl describe` and `kubectl get events --sort-by=.lastTimestamp`
- [ ] Checked [[Kubernetes/eks/troubleshooting/common-issues|common EKS issues]] for the symptom
- [ ] Add-ons are on supported, current versions
- [ ] Looked at what changed in the last day: deployments, IAM, security groups, node AMIs
- [ ] Searched the component's GitHub issues for the exact error string
- [ ] Reproduced it in the smallest possible case

## Related

- [[Kubernetes/eks/troubleshooting/README|EKS troubleshooting]]
- [[Kubernetes/guides/troubleshooting/index|Kubernetes troubleshooting playbooks]]
- [[DevOps/sre/incident-management|Incident management]]
- [[AWS/management-governance/systems-manager/README|AWS Systems Manager]]
