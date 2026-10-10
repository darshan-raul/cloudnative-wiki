---
title: Terraform State and Collaboration
tags: [devops, infrastructure-as-code, terraform, state, collaboration]
date: 2026-10-10
description: How Terraform state works and how teams use it safely — remote backends and locking, what state contains, splitting state by blast radius, sharing data between states, environment layout, pull-request workflows, drift and recovery.
---

# Terraform State and Collaboration

Terraform is easy for one person. The difficulty starts when several people and pipelines change the same infrastructure, and nearly all of that difficulty is about **state**: the file that records which real resources Terraform manages.

This note assumes the basics from [[DevOps/infrastructure-as-code/terraform|Terraform]].

## What state is

State maps each resource address in your code to a real resource ID, and caches that resource's attributes.

```
aws_db_instance.orders  ──►  id = "orders-prod", endpoint = "…", password = "…"
```

Terraform needs it to know what it owns, to detect what changed, to order deletions, and to avoid querying every API on every run. Three properties follow:

1. **State is the source of truth for ownership.** Lose it, and Terraform believes nothing exists and tries to create everything again.
2. **State contains secrets.** Any sensitive attribute — database passwords, private keys, tokens — is stored in it in plain text, whether or not the variable was marked `sensitive`.
3. **Two concurrent writers corrupt it.** State must be locked while a run is in progress.

## Remote backends

Local state in a working directory fails all three requirements for a team. Use a remote backend with locking, versioning and encryption.

```hcl
terraform {
  backend "s3" {
    bucket       = "example-terraform-state"
    key          = "prod/network/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    kms_key_id   = "alias/terraform-state"
    use_lockfile = true
  }
}
```

| Requirement | On AWS                                                                                    |
| :---------- | :---------------------------------------------------------------------------------------- |
| Durability  | [[AWS/storage/s3/README\|S3]] with **versioning** — the undo button for a bad state write |
| Locking     | S3 native lock files (`use_lockfile`); older setups use a DynamoDB table                  |
| Encryption  | SSE with a [[AWS/security/kms/README\|KMS]] key                                           |
| Access      | A bucket policy limited to the pipeline role and a small break-glass group                |
| Audit       | [[AWS/security/cloudtrail/README\|CloudTrail]] data events on the bucket                  |

Equivalent backends exist for Azure Blob Storage and Google Cloud Storage; HCP Terraform, Spacelift, env0 and Scalr provide managed state with runs. Treat read access to state as read access to every secret in it. [[DevOps/infrastructure-as-code/opentofu|OpenTofu]] can additionally encrypt the state client-side.

## Splitting state

A single state for a whole organisation means every plan refreshes thousands of resources, everyone waits on one lock, and one mistake can reach everything. Split along three axes:

| Axis            | Split by                                       | Reason                                                                |
| :-------------- | :--------------------------------------------- | :-------------------------------------------------------------------- |
| **Environment** | dev, staging, prod — ideally separate accounts | A dev change can never touch prod                                     |
| **Lifecycle**   | Network, cluster, data stores, applications    | Things that change weekly are separate from things that change yearly |
| **Ownership**   | One state per team or service                  | Teams do not block each other                                         |

A typical layout:

```
live/
├── prod/
│   ├── network/          # VPC, subnets, DNS zones        — changes rarely
│   ├── eks/              # cluster and node groups
│   ├── data/orders-db/   # stateful, prevent_destroy
│   └── services/orders/  # queues, buckets, IAM for one service — changes often
├── staging/…
modules/                   # versioned, reusable modules
```

A useful test: a state should plan in under a minute and be understandable by one person. If neither is true, split it.

## Environments: directories or workspaces

|                                  | Directory per environment                          | Workspaces                                          |
| :------------------------------- | :------------------------------------------------- | :-------------------------------------------------- |
| Isolation                        | Separate backend config, credentials and code path | Same code and backend, different state key          |
| Differences between environments | Explicit in each directory                         | Conditionals on `terraform.workspace`               |
| Risk                             | Some duplication                                   | Applying to the wrong workspace is one command away |

Directories (with shared modules) are the safer default for long-lived environments. Workspaces suit many near-identical, short-lived copies such as per-pull-request environments. Terragrunt and Terraform Stacks exist to reduce the duplication of the directory approach.

## Sharing data between states

Once state is split, the cluster configuration needs the VPC ID from the network configuration.

| Method                                         | Trade-off                                                                      |
| :--------------------------------------------- | :----------------------------------------------------------------------------- |
| `terraform_remote_state` data source           | Simple, but grants read access to the **entire** other state, secrets included |
| Provider data sources (look up by tag or name) | Loose coupling, least privilege; needs naming and tagging conventions          |
| A parameter store (SSM, Consul)                | Explicit published interface between teams                                     |

Prefer data sources or a parameter store. Publishing only the values others need is the same principle as a narrow API.

## A team workflow

```
branch ─► pull request ─► CI: fmt, validate, lint, scan, plan ─► plan posted on the PR
                                                                       │
                                                           review code AND plan
                                                                       │
                                merge ─► CI: apply the reviewed plan ─► state updated
```

Rules that make it work:

- **Only the pipeline applies** to shared environments. People get read-only credentials.
- **Plan on every pull request**, with the output visible to reviewers.
- **Apply the plan that was reviewed.** Save it as an artifact; if the base moved, re-plan.
- **One apply at a time per state**; the lock enforces this, the pipeline should queue rather than fail.
- **Short-lived credentials** for the pipeline through OIDC federation, never stored access keys — see [[DevOps/ci-cd/github-actions|GitHub Actions]].
- **Separate roles** for plan (read-only) and apply (write), and for each environment.
- **Policy checks before apply** — [[DevOps/devsecops/README|DevSecOps]].

Atlantis, HCP Terraform, Spacelift and similar tools implement this loop; it can also be built in any CI system. The general design is in [[DevOps/ci-cd/pipeline-design|pipeline design]].

## Drift

Drift is a difference between state and reality: someone changed a security group in the console, or an autoscaler changed a count.

- Run `terraform plan -refresh-only` on a schedule and alert when it is not empty.
- For fields legitimately changed elsewhere, use `ignore_changes`.
- For everything else, either revert reality by applying, or accept it by changing the code. Do not leave it: the next unrelated apply will silently undo the manual fix.

## When state goes wrong

| Situation                                | Recovery                                                                        |
| :--------------------------------------- | :------------------------------------------------------------------------------ |
| A run crashed and left a lock            | Confirm nothing is running, then `terraform force-unlock <id>`                  |
| State was corrupted by a bad write       | Restore the previous object version from the bucket                             |
| A resource was deleted outside Terraform | `terraform apply -refresh-only`, or remove it from state with a `removed` block |
| A resource exists but is not in state    | An `import` block                                                               |
| State was lost entirely                  | Restore from backup; otherwise re-import resource by resource                   |
| Moving a resource to another state       | `removed` (with `destroy = false`) in the source, `import` in the destination   |

Before any manual state operation, take a copy: `terraform state pull > backup.tfstate`. Avoid editing state by hand.

## Common collaboration problems

| Problem                                    | Cause and remedy                                                                         |
| :----------------------------------------- | :--------------------------------------------------------------------------------------- |
| Constant lock contention                   | State too large or shared by too many teams — split it                                   |
| Plans show changes nobody made             | Drift, an unpinned provider, or non-deterministic inputs                                 |
| "It worked in staging" but not in prod     | Environments differ in ways not captured in code; shrink the differences                 |
| Long-lived branches with conflicting plans | Merge small changes often; plans go stale as soon as the base changes                    |
| Module upgrades are frightening            | Modules are unversioned or too large; release them with semantic versions and changelogs |
| Nobody knows who owns a resource           | Enforce owner tags through `default_tags` and policy                                     |

## Related

- [[DevOps/infrastructure-as-code/README|Infrastructure as code]]
- [[DevOps/ci-cd/git|Git workflows]]
- [[AWS/management-governance/organizations/README|AWS Organizations]] — the account structure environments map onto
- [[DevOps/platform-engineering/README|Platform engineering]]
