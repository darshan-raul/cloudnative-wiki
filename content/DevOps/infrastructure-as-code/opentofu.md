---
title: OpenTofu
tags: [opentofu, terraform, iac, hashicorp, devops]
date: 2026-09-06
description: "OpenTofu open-source infrastructure as code engine — architecture, state encryption, provider registry, migration from Terraform, and CLI reference."
---

# OpenTofu 🚀

OpenTofu is an open-source, community-driven fork of Terraform (v1.5.x) managed under the Linux Foundation. It provides backward-compatible HCL infrastructure orchestration while adding key security innovations such as native state encryption.

---

## 1. Why OpenTofu?

Following HashiCorp's license change of Terraform to BSL 1.1 in August 2023, the community and major cloud vendors established OpenTofu under the Linux Foundation (MPL-2.0 license).

| Dimension                 | Terraform (v1.6+)                        | OpenTofu (v1.8+)                               |
| :------------------------ | :--------------------------------------- | :--------------------------------------------- |
| **License**               | BUSL-1.1 (Source-available, non-compete) | MPL-2.0 (Truly open source)                    |
| **Governance**            | Single vendor (HashiCorp / IBM)          | Linux Foundation community-led                 |
| **State Encryption**      | Enterprise / Cloud feature only          | **Native, open-source client-side encryption** |
| **Provider Registry**     | `registry.terraform.io`                  | `get.opentofu.org` (mirrors all providers)     |
| **Variables in Backends** | Limited interpolation                    | Supported in backend configuration blocks      |

---

## 2. Key Differentiator: Native State Encryption

OpenTofu allows encrypting sensitive state files client-side before sending them to remote backends (e.g., S3, GCS, Azure Blob):

```hcl
terraform {
  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.tofu_encryption_passphrase
    }

    method "aes_gcm" "state_encryption" {
      keys = key_provider.pbkdf2.passphrase
    }

    state {
      method = method.aes_gcm.state_encryption
      enforced = true
    }

    plan {
      method = method.aes_gcm.state_encryption
      enforced = true
    }
  }
}
```

Cloud-native key providers (`aws_kms`, `gcp_kms`, `azure_key_vault`) are also supported directly.

---

## 3. CLI Workflow & Drop-in Replacement

OpenTofu CLI (`tofu`) uses identical commands to `terraform`:

```bash
# Initialize working directory and download providers from OpenTofu registry
tofu init

# Format and validate HCL files
tofu fmt -recursive
tofu validate

# Plan infrastructure execution
tofu plan -out=tfplan

# Apply infrastructure changes
tofu apply tfplan

# State management
tofu state list
tofu state show aws_instance.web
```

---

## 4. Migration from Terraform

1. OpenTofu is a drop-in replacement for Terraform <= 1.5.x without changes.
2. Replace the binary: `alias terraform=tofu` or install via system package manager:
   ```bash
   # Debian / Ubuntu
   snap install --classic opentofu
   # Homebrew / macOS / Linux
   brew install opentofu
   ```
3. Run `tofu init` in your existing configuration. OpenTofu will automatically download providers from the OpenTofu registry and read existing `.tfstate` files.

## Across the wiki

- [[AWS/management-governance/cloudformation/README|AWS CloudFormation]] — infrastructure as code (AWS)
- [[Kubernetes/eks/automation/control-planes/ack|AWS Controllers for Kubernetes (ACK)]] — infrastructure as code (Kubernetes)
- [[AWS/management-governance/cdk/README|AWS CDK]] — infrastructure as code (AWS)
- [[Kubernetes/eks/getting-started/cluster-creation|Cluster Creation]] — infrastructure as code (Kubernetes)
