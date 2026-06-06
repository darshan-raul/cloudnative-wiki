---
title: AWS Security
description: AWS security services — IAM for identity, KMS for encryption, CloudTrail for audit, GuardDuty for threat detection, Security Hub for aggregation, Inspector for vulnerability scanning, Macie for data privacy, Secrets Manager, ACM, and Detective.
tags:
  - aws
  - security
---

# AWS Security

AWS provides a comprehensive set of security services covering identity, encryption, audit logging, threat detection, vulnerability management, and secrets management.

## Service Map

| Service | Category | Use Case |
|---------|----------|----------|
| [[iam/README|IAM]] | Identity | Users, groups, roles, policies, federation |
| [[kms/README|KMS]] | Encryption | Data at rest encryption, CMK, envelope encryption |
| [[cloudtrail/README|CloudTrail]] | Audit | API call logging, compliance, forensics |
| [[config/README|Config]] | Compliance | Resource inventory, change tracking, conformance packs |
| [[guardduty/README|GuardDuty]] | Threat Detection | DNS/CloudTrail/VPC flow analysis, malware detection |
| [[security-hub/README|Security Hub]] | Centralized Security | Aggregates findings from all security services |
| [[inspector/README|Inspector]] | Vulnerability Scanning | EC2, ECR, Lambda vulnerability assessment |
| [[macie/README|Macie]] | Data Privacy | S3 data classification, PII detection |
| [[secrets-manager/README|Secrets Manager]] | Secrets | Passwords, API keys, rotation |
| [[certificate-manager/README|Certificate Manager]] | TLS/SSL | Public/private certificates, managed renewal |
| [[detective/README|Detective]] | Investigation | Graph-based security investigation |

## Shared Responsibility Model

```
AWS Responsible:
  - Physical security of data centers
  - Hardware/software infrastructure (EC2 host, S3, RDS, etc.)
  - Network infrastructure
  - Hypervisor (Nitro)

Customer Responsible:
  - IAM (users, roles, policies)
  - Data (encryption, access control)
  - Application code
  - OS patches (EC2, containers)
  - Network configuration (SGs, NACLs, VPC)
  - Data classification and labeling
```

## Security Architecture Pattern

```
                    ┌─────────────────────────────────────┐
                    │          AWS Security Services        │
                    │                                       │
  ┌──────────────┐  │  ┌────────────────────────────────┐  │
  │   Identity   │──│─▶│  IAM (Users, Roles, Policies)   │  │
  │   (Users,     │  │  └────────────────────────────────┘  │
  │   Federated)  │  │                                       │
  └──────────────┘  │  ┌────────────────────────────────┐  │
                    │  │  KMS (Encryption Keys)          │  │
  ┌──────────────┐  │  └────────────────────────────────┘  │
  │   Data       │──│                                       │
  │   (S3, RDS,  │  │  ┌────────────────────────────────┐  │
  │   DynamoDB)  │  │  │  CloudTrail (Audit Logs)        │  │
  └──────────────┘  │  └────────────────────────────────┘  │
                    │                                       │
                    │  ┌────────────────────────────────┐  │
                    │  │  GuardDuty (Threat Detection)   │  │
                    │  │  Security Hub (Aggregation)     │  │
                    │  │  Inspector (Vulnerabilities)   │  │
                    │  └────────────────────────────────┘  │
                    │                                       │
                    └─────────────────────────────────────┘
```

## Defense in Depth

1. **Identity** — IAM roles with least privilege
2. **Network** — VPC (public/private/subnet isolation), Security Groups, NACLs
3. **Data** — Encryption at rest (KMS) and in transit (TLS)
4. **Monitoring** — CloudTrail + CloudWatch + GuardDuty
5. **Incident Response** — Detective + Security Hub + automated remediation

## References

- **Homepage:** https://aws.amazon.com/security/
- **Documentation:** https://docs.aws.amazon.com/security/
- **Pricing:** https://aws.amazon.com/security/pricing/

## Nuggets & Gotchas

- **AWS shared responsibility means YOU are responsible for what's IN the cloud — AWS secures the cloud ITSELF:** Many breaches are customer-side misconfigurations (open S3 buckets, overly permissive IAM policies), not AWS infrastructure failures.
- **Security is not a product you buy — it's a process (people + process + technology):** AWS security services help, but you still need patch management, configuration management, and incident response procedures.
- **Most AWS security breaches follow the same pattern — compromised credentials or misconfigured resources:** GuardDuty, Security Hub, and Macie help detect these, but prevention (least privilege IAM, proper encryption) is better than detection.
- **Security Hub doesn't prevent threats — it aggregates findings from other services:** You need GuardDuty for threat detection, Inspector for vulnerabilities, and Macie for data privacy to generate findings that Security Hub then correlates.
- **AWS security services generate findings that require human review — automate triage with EventBridge + Lambda:** Without automation, you'll be overwhelmed by security findings. Build automated remediation for common issues (e.g., S3 bucket made public → auto-apply block public access).