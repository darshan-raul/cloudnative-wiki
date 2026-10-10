---
title: Terraform
tags: [devops, infrastructure-as-code, terraform, hcl]
date: 2026-10-10
description: A working understanding of Terraform — the init, plan, apply loop, HCL building blocks, providers, the resource graph, modules, lifecycle controls, importing and refactoring, testing, and the mistakes that cause outages.
---

# Terraform

Terraform is a declarative provisioning tool. You describe resources in HCL, Terraform compares that description with what it recorded last time and with what actually exists, and it produces a **plan** of creates, updates and deletes for you to approve. It works against any API for which a **provider** exists — every major cloud, plus DNS, Kubernetes, GitHub, Datadog and thousands more.

For where it sits among other tools, see [[DevOps/infrastructure-as-code/README|infrastructure as code]].

## The core loop

```
write HCL ──► terraform init ──► terraform plan ──► review ──► terraform apply
                  │                    │                             │
       download providers        refresh state,               call provider APIs,
       and modules, set up       diff desired vs actual       write new state
       the backend
```

| Command                      | What it does                                                 |
| :--------------------------- | :----------------------------------------------------------- |
| `terraform init`             | Installs providers and modules, configures the state backend |
| `terraform fmt`, `validate`  | Formats and checks syntax and types                          |
| `terraform plan -out=tfplan` | Computes the change set and saves it                         |
| `terraform apply tfplan`     | Executes exactly the saved plan                              |
| `terraform destroy`          | Plans and applies deletion of everything in the state        |

Always apply a **saved plan**. Applying without one re-plans at apply time, and what runs may differ from what was reviewed.

## Reading a plan

```
  # aws_db_instance.orders must be replaced
-/+ resource "aws_db_instance" "orders" {
      ~ engine_version = "15.4" -> "16.3"
      ~ storage_encrypted = false -> true   # forces replacement
        identifier     = "orders"
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

| Symbol | Meaning                                            |
| :----- | :------------------------------------------------- |
| `+`    | Create                                             |
| `~`    | Update in place                                    |
| `-`    | Destroy                                            |
| `-/+`  | Destroy then create — **the resource is replaced** |
| `+/-`  | Create then destroy (with `create_before_destroy`) |

`forces replacement` on a database, a volume or a load balancer is the line that causes outages and data loss. Read every plan for it.

## Building blocks

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { environment = var.environment, managed-by = "terraform" }
  }
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

locals {
  name = "orders-${var.environment}"
}

data "aws_vpc" "main" {
  tags = { Name = "main-${var.environment}" }
}

resource "aws_security_group" "db" {
  name   = "${local.name}-db"
  vpc_id = data.aws_vpc.main.id
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}
```

| Block      | Purpose                                             |
| :--------- | :-------------------------------------------------- |
| `resource` | Something Terraform creates and owns                |
| `data`     | Something that already exists, read but not managed |
| `variable` | An input, with type and validation                  |
| `locals`   | Named expressions, to avoid repetition              |
| `output`   | A value exposed to callers or other configurations  |
| `module`   | A call to a reusable group of resources             |

Use `for_each` to create several instances from a map or set. Prefer it to `count`: `count` identifies instances by position, so removing the first of three renumbers the others and Terraform destroys and recreates them.

## The dependency graph

Terraform builds a graph from references. `vpc_id = data.aws_vpc.main.id` tells it the security group depends on the VPC lookup, so it orders the operations and runs independent branches in parallel. `depends_on` exists for dependencies that are real but not visible in arguments — an IAM policy that must be attached before a service starts, for instance. Needing it often is a sign something else is wrong.

## Modules

A module is a directory of `.tf` files with inputs and outputs. It is the unit of reuse and the way a platform team encodes standards.

```hcl
module "orders_db" {
  source  = "git::https://github.com/example/terraform-modules.git//postgres?ref=v3.2.0"

  name           = local.name
  instance_class = "db.r7g.large"
  vpc_id         = data.aws_vpc.main.id
}
```

- **Pin the version** (`?ref=` or `version =`). An unpinned module changes underneath you.
- **Keep modules small and opinionated.** A module that exposes every argument of the underlying resource adds nothing. A good one makes the secure, standard choice the default and exposes only what legitimately varies.
- **Avoid deep nesting.** Two levels are usually enough.
- **Do not put `provider` blocks inside reusable modules**; pass providers from the root.

## Lifecycle controls

```hcl
resource "aws_db_instance" "orders" {
  # ...
  lifecycle {
    prevent_destroy       = true
    create_before_destroy = true
    ignore_changes        = [password]
  }
}
```

| Setting                 | Use                                                                                     |
| :---------------------- | :-------------------------------------------------------------------------------------- |
| `prevent_destroy`       | Refuses any plan that would delete the resource — for stateful resources                |
| `create_before_destroy` | Builds the replacement first, avoiding a gap                                            |
| `ignore_changes`        | Stops Terraform reverting fields managed elsewhere (autoscaled counts, rotated secrets) |
| `replace_triggered_by`  | Forces replacement when another resource changes                                        |

## Importing and refactoring without destroying

Renaming a resource in code makes Terraform plan a destroy and a create, because it tracks by address. Tell it what you mean instead:

```hcl
moved {
  from = aws_security_group.database
  to   = aws_security_group.db
}

import {
  to = aws_s3_bucket.logs
  id = "example-logs-prod"
}

removed {
  from = aws_instance.legacy
  lifecycle { destroy = false }
}
```

`moved` renames, `import` adopts an existing resource (and `terraform plan -generate-config-out=` writes the HCL), and `removed` stops managing something without deleting it. All three are reviewed in a plan like any other change, which is why they are preferable to the older `terraform state mv` and `terraform import` commands.

## Testing and policy

| Layer              | Tool                                                               |
| :----------------- | :----------------------------------------------------------------- |
| Format and syntax  | `terraform fmt -check`, `terraform validate`                       |
| Lint               | `tflint`                                                           |
| Security scanning  | Checkov, Trivy, tfsec — see [[DevOps/devsecops/README\|DevSecOps]] |
| Policy on the plan | OPA/Conftest, Sentinel                                             |
| Module tests       | `terraform test` (native `.tftest.hcl` files), Terratest           |
| Cost preview       | Infracost                                                          |

## Mistakes that hurt

| Mistake                                                | Consequence                                               |
| :----------------------------------------------------- | :-------------------------------------------------------- |
| Applying from a laptop                                 | No record, no review, state conflicts                     |
| One enormous configuration for everything              | Slow plans, huge blast radius, constant lock contention   |
| Secrets as plain variables or outputs                  | They are stored in state in clear text                    |
| `terraform apply -auto-approve` on shared environments | Nobody read the plan                                      |
| `-target` as a habit                                   | State and code diverge                                    |
| Unpinned providers                                     | A provider release changes behaviour mid-project          |
| Editing resources in the console                       | Drift; the next apply silently reverts or conflicts       |
| Provisioners (`local-exec`, `remote-exec`)             | Not in the plan, not idempotent; use images or cloud-init |

## Licence and OpenTofu

Since version 1.6, Terraform is distributed under the Business Source License rather than an open-source licence. [[DevOps/infrastructure-as-code/opentofu|OpenTofu]] is the open-source fork maintained under the Linux Foundation; it is compatible for most configurations and has added features of its own, notably state encryption.

## Related

- [[DevOps/infrastructure-as-code/terraform-state-and-collaboration|State and collaboration]] — the part that determines whether a team can use it safely
- [[DevOps/infrastructure-as-code/packer|Packer]] and [[DevOps/infrastructure-as-code/ansible|Ansible]]
- [[Kubernetes/eks/automation/control-planes/crossplane|Crossplane]] — the control-plane alternative
- [[AWS/management-governance/cloudformation/README|CloudFormation]]
- [Terraform documentation](https://developer.hashicorp.com/terraform/docs)

## Further reading

- [Terraform — itnext.io](https://itnext.io/pains-in-terraform-collaboration-249a56b4534e)
