---
title: Tools & Prerequisites
tags: [eks, getting-started, tools]
date: 2026-05-17
description: Required tools and IAM permissions for EKS
---

# Tools & Prerequisites

## Required Tools

### eksctl
Official CLI for EKS cluster creation and management.

```bash
brew install eksctl
# or
curl --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin/
```

### kubectl
Kubernetes CLI for interacting with clusters.

```bash
brew install kubectl
# or
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

### AWS CLI v2
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

## IAM Permissions

Minimum IAM policy for cluster creation:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:CreateCluster",
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
```

## Verify Installation

```bash
eksctl version
kubectl version --client
aws --version
```

## References

- [eksctl Documentation](https://eksctl.io/)
- [kubectl Installation](https://kubernetes.io/docs/tasks/tools/)
- [AWS CLI Installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)