---
title: "Reference: Node Access and Log Locations"
description: "How to get a shell or logs from an EKS node on AL2023, Bottlerocket and Auto Mode, where each component logs, and how to collect a support bundle."
tags: [kubernetes/eks/operator-runbook, eks, reference, nodes, logs, ssm]
date: 2026-10-20
aliases: [EKS node log locations, EKS node SSM access]
---

# Reference: Node Access and Log Locations

## Getting onto a node

| Node type                                 | Access                                                                                                                                                                       |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AL2023 (managed, self-managed, Karpenter) | `aws ssm start-session --target "$INSTANCE_ID"`. Needs the SSM agent (in the EKS AMI) and `AmazonSSMManagedInstanceCore` on the node role                                    |
| Bottlerocket                              | `aws ssm start-session` lands in the **control container**. Then `enter-admin-container` (if the admin container is enabled) and `sudo sheltie` for a root shell on the host |
| Auto Mode                                 | No shell. Use `kubectl debug node` (below), or a `NodeDiagnostic` resource to ship logs to S3                                                                                |
| Any node, no SSM                          | `kubectl debug node/"$NODE" -it --profile=sysadmin --image=public.ecr.aws/amazonlinux/amazonlinux:2023`. The host filesystem is at `/host`; `chroot /host` for host tools    |
| OS hung, nothing connects                 | `aws ec2 get-console-output --instance-id "$INSTANCE_ID" --latest --output text` (kernel messages, OOM, panics)                                                              |

`kubectl debug node` needs the API server and the kubelet to be working, so it doesn't help on a `NotReady` node. Use SSM or the console output there.

Delete debug Pods when you're done: `kubectl get pods -A | grep node-debugger`.

## Where things log (AL2023)

| Component                      | Location                                                    |
| ------------------------------ | ----------------------------------------------------------- |
| kubelet                        | `journalctl -u kubelet`                                     |
| containerd                     | `journalctl -u containerd`                                  |
| Node bootstrap (`nodeadm`)     | `journalctl -u nodeadm-config -u nodeadm-run`               |
| cloud-init / user data         | `/var/log/cloud-init.log`, `/var/log/cloud-init-output.log` |
| VPC CNI ipamd                  | `/var/log/aws-routed-eni/ipamd.log`                         |
| VPC CNI plugin (per Pod setup) | `/var/log/aws-routed-eni/plugin.log`                        |
| Network policy agent           | `/var/log/aws-routed-eni/network-policy-agent.log`          |
| Container stdout/stderr        | `/var/log/pods/<ns>_<pod>_<uid>/<container>/<n>.log`        |
| Kernel                         | `journalctl -k` or `dmesg -T`                               |
| kubelet configuration          | `/etc/kubernetes/kubelet/`                                  |

Useful one-liners on the node:

```bash
sudo journalctl -u kubelet --since "-30min" --no-pager | grep -Ei 'error|fail' | tail -50
sudo crictl ps -a | head -30           # containers, including exited
sudo crictl pods | head -30
sudo crictl logs <container-id> | tail
df -h / /var/lib/containerd; df -i /
sudo dmesg -T | grep -iE 'oom|killed process|hung_task|error' | tail
```

On **Bottlerocket**, run the same `journalctl` and `crictl` commands from `sheltie`. Settings are read with `apiclient get settings`.

## Collect a support bundle

AL2023 and other EKS-optimized Linux AMIs:

```bash
curl -sO https://raw.githubusercontent.com/awslabs/amazon-eks-ami/main/log-collector-script/linux/eks-log-collector.sh
sudo bash eks-log-collector.sh       # writes /var/log/eks_<instance>_<timestamp>.tar.gz
```

VPC CNI only: `sudo /opt/cni/bin/aws-cni-support.sh`. Bottlerocket: `logdog` in the admin container writes a tarball, which you can then copy out.

Copy it off the node, for example through an S3 bucket the node role can write to: `aws s3 cp /var/log/eks_*.tar.gz s3://<bucket>/`.

## Auto Mode: NodeDiagnostic

The EKS node monitoring agent collects a log bundle when you create a `NodeDiagnostic` named after the node. It runs on Auto Mode nodes, and on other nodes where the agent is installed. The destination is a presigned S3 `PUT` URL that you create:

```yaml
apiVersion: eks.amazonaws.com/v1alpha1
kind: NodeDiagnostic
metadata:
  name: <node-name>
spec:
  logCapture:
    destination: <presigned S3 PUT URL>
```

Watch `kubectl get nodediagnostic <node-name> -o yaml`. `Success` or `SuccessWithErrors` means the bundle was uploaded. Delete the resource afterwards; it isn't cleaned up automatically. Newer agent versions (v1.6.1-eksbuild.1 and later) also accept `destination: node`, which keeps the bundle on the node briefly for collection with the `ekslogs` kubectl plugin.

## Across the wiki

- [[Kubernetes/eks/operator-runbook/runbooks/node-not-ready|Node NotReady]]
- [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl debug]]
- [[Kubernetes/eks/operator-runbook/reference/command-conventions|Command conventions]]
