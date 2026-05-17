---
title: EKS Support Resources
tags: [eks, troubleshooting, support]
date: 2026-05-17
description: EKS support resources and where to get help
---

# EKS Support Resources

## AWS Support Plans

| Plan | Support Channels | Response Time |
|------|-----------------|---------------|
| Basic | Documentation, Forums, CloudTrail | N/A |
| Developer | Email | 12 hours |
| Business | Phone, Chat, TAM | 1 hour (critical) |
| Enterprise | Dedicated TAM, Concierge | 15 min (critical) |

## Documentation

- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EKS API Reference](https://docs.aws.amazon.com/eks/latest/APIReference/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [EKS Workshop](https://www.eksworkshop.com/)

## AWS re:Post

Free community support:
- [AWS re:Post - EKS](https://repost.aws/topics/T27ZZ2YVR8W5J/amazon-eks)
- Search for known issues
- Post questions

## GitHub Repos

- [aws/eks-distro](https://github.com/aws/eks-distro) - EKS Kubernetes distribution
- [aws/eks-charts](https://github.com/aws/eks-charts) - Official Helm charts
- [aws-controllers-k8s/community](https://github.com/aws-controllers-k8s/community) - ACK controllers
- [aws-samples/eks-workshop-v2](https://github.com/aws-samples/eks-workshop-v2) - EKS Workshop content

## Slack Channels

- [Kubernetes Slack #eks-user](https://kubernetes.slack.com/)
- [AWS Community - EKS](https://aws-slack.com/)

## Premium Support Resources

### TAM (Technical Account Manager)
- Proactive guidance
- Architecture reviews
- Direct escalation

### AWS Support API

```bash
# Create support case
aws support create-case \
  --subject "EKS cluster issue" \
  --category-code "using-eks" \
  --severity-code "high" \
  --description "Description" \
  --communication-body "Details" \
  --language en

# Check case status
aws support describe-cases
```

## Health Checks

```bash
# Check service health
aws health describe-events --filter eventTypeCategories=issue

# Check personal health
aws health describe-events-for-organization
```

## Useful Tools

| Tool | Purpose |
|------|---------|
| eksctl | Cluster management |
| kubectl | Kubernetes CLI |
| AWS CLI | AWS API |
| CloudWatch | Logs and metrics |
| AWS Config | Resource tracking |

## References

- [AWS Support](https://aws.amazon.com/premiumsupport/)
- [EKS FAQ](https://aws.amazon.com/eks/faqs/)
- [EKS Roadmap](https://github.com/aws/eks-distro/projects/1)