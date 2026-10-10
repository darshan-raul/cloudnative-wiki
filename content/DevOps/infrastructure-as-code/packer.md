---
title: Packer
tags: [devops, infrastructure-as-code, packer, images, immutable-infrastructure]
date: 2026-10-10
description: Building machine images with Packer — why bake rather than configure at boot, templates in HCL, builders, provisioners and post-processors, an AMI pipeline with testing and promotion, and how images relate to containers and EKS nodes.
---

# Packer

Packer builds machine images from a template. It launches a temporary machine from a base image, runs provisioners to install and configure software, captures the result as a new image, and deletes the machine. The same template can produce an AWS AMI, an Azure image, a GCP image and a local VM image.

It is the tool behind **immutable infrastructure** for virtual machines: servers are never patched in place, they are replaced with ones built from a newer image. See [[DevOps/infrastructure-as-code/README|infrastructure as code]] for the wider picture.

## Bake or fry

|             | Bake (build an image ahead of time)                | Fry (configure at boot)                       |
| :---------- | :------------------------------------------------- | :-------------------------------------------- |
| Boot time   | Seconds — everything is already installed          | Minutes of package installs and configuration |
| Reliability | No dependency on package mirrors at scale-out time | A mirror outage breaks autoscaling            |
| Consistency | Every instance is byte-identical                   | Instances built on different days differ      |
| Rollback    | Launch the previous image                          | Reverse the configuration, hopefully          |
| Change cost | A build per change                                 | Edit a script                                 |

The usual compromise bakes everything slow and stable — OS patches, agents, runtimes, hardening — and leaves only environment-specific values for boot time through user data or cloud-init. Fast boot matters most where capacity is added under load: [[AWS/compute/ec2/README|EC2]] auto scaling groups and Kubernetes nodes.

## A template

```hcl
# web.pkr.hcl
packer {
  required_plugins {
    amazon  = { source = "github.com/hashicorp/amazon",  version = "~> 1.3" }
    ansible = { source = "github.com/hashicorp/ansible", version = "~> 1.1" }
  }
}

variable "version" { type = string }

source "amazon-ebs" "web" {
  region        = "eu-west-1"
  instance_type = "t4g.small"
  ssh_username  = "ec2-user"
  ami_name      = "web-${var.version}-{{timestamp}}"

  source_ami_filter {
    owners      = ["amazon"]
    most_recent = true
    filters = {
      name         = "al2023-ami-2023.*-arm64"
      architecture = "arm64"
    }
  }

  encrypt_boot = true
  imds_support = "v2.0"

  tags = {
    Name       = "web"
    version    = var.version
    base_ami   = "{{ .SourceAMI }}"
    built_by   = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.web"]

  provisioner "shell" {
    inline = ["sudo dnf -y update"]
  }

  provisioner "ansible" {
    playbook_file = "playbooks/web.yaml"
  }

  provisioner "shell" {
    script = "scripts/cleanup.sh" # remove keys, logs, caches, machine-id
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
```

```bash
packer init .
packer fmt -check . && packer validate -var version=1.8.0 .
packer build -var version=1.8.0 .
```

| Concept              | Role                                                                                                        |
| :------------------- | :---------------------------------------------------------------------------------------------------------- |
| **Source / builder** | Where and how to launch the temporary machine: `amazon-ebs`, `azure-arm`, `googlecompute`, `qemu`, `docker` |
| **Provisioner**      | What to do on it: `shell`, `ansible`, `file`, `powershell`                                                  |
| **Post-processor**   | What to do with the result: write a manifest, compress, upload, sign                                        |
| **Plugin**           | Builders and provisioners are distributed as versioned plugins — pin them                                   |

Reusing [[DevOps/infrastructure-as-code/ansible|Ansible]] roles as the provisioner means the same code configures long-lived servers and bakes images.

## What belongs in an image

**Bake in:** OS security updates; monitoring, logging and security agents; language runtimes; hardening ([[Linux/security/linux-cis-hardening|CIS benchmarks]], [[Linux/security/sysctl|sysctl]] settings); organisation CA certificates.

**Leave out:** secrets of any kind, environment-specific configuration, SSH host keys and `authorized_keys`, the machine ID, shell history and logs. An image is copied to many machines and often shared across accounts — anything in it should be treated as public within the organisation. The clean-up script at the end of the build exists for this.

## An image pipeline

```
base image published ─┐
template changed ─────┼─► build ─► test ─► scan ─► tag "candidate" ─► deploy to staging
weekly schedule ──────┘                                                     │
                                                                  soak, then promote
                                                                            │
                                         share to prod accounts ◄── tag "approved"
                                                    │
                                    rolling replacement of instances
```

1. **Trigger** on template changes, on a new base image, and on a schedule — a weekly rebuild is how images stay patched.
2. **Test** the built image: boot it, check services, ports and versions with Goss, InSpec or Testinfra.
3. **Scan** for vulnerabilities ([[AWS/security/inspector/README|Inspector]], Trivy) and fail on criticals.
4. **Promote by tag**, not by rebuilding. The image tested in staging is the image that reaches production.
5. **Roll out** by updating the launch template and performing an instance refresh.
6. **Expire** old images and their snapshots; they cost storage and accumulate vulnerabilities.

Record the base image, commit and build number as tags so any running instance can be traced back to its source. This is the VM equivalent of the practices in [[DevOps/devsecops/stage2-build/09-container-image-scanning|container image scanning]] and [[DevOps/ci-cd/pipeline-design|pipeline design]].

## Images and Terraform

Packer creates the image; Terraform uses it. Connect them through a data source rather than pasting IDs:

```hcl
data "aws_ami" "web" {
  owners      = ["self"]
  most_recent = true
  filter {
    name   = "tag:Name"
    values = ["web"]
  }
  filter {
    name   = "tag:status"
    values = ["approved"]
  }
}
```

A new approved image then shows up as a planned change to the launch template. See [[DevOps/infrastructure-as-code/terraform|Terraform]].

## Machine images, containers and Kubernetes nodes

|            | Machine image                   | Container image                           |
| :--------- | :------------------------------ | :---------------------------------------- |
| Contains   | A whole OS including the kernel | Application and user-space libraries only |
| Built with | Packer, EC2 Image Builder       | A Dockerfile or buildpacks                |
| Size       | Gigabytes                       | Megabytes                                 |
| Starts in  | Tens of seconds                 | Under a second                            |
| Use for    | Hosts and nodes                 | Applications                              |

In a Kubernetes shop most applications ship as containers ([[Containers/images-and-layers|images and layers]]), and Packer's job shrinks to the node image. On EKS, AWS publishes the node AMI build as Packer templates in the `amazon-eks-ami` repository; you would fork it only for requirements the stock image cannot meet — mandated agents, a specific kernel, pre-pulled large images. Otherwise prefer the managed AMIs or Bottlerocket and customise through user data. See [[Kubernetes/eks/compute/managed-node-groups/basics|managed node group basics]].

## Alternatives

- **EC2 Image Builder** — AWS-managed pipelines with built-in testing, scheduling and cross-account distribution; AWS only.
- **Azure VM Image Builder** — a managed service that itself runs Packer.
- **Bottlerocket, Flatcar, Talos** — purpose-built immutable container hosts where there is little left to bake.

Like Terraform, Packer is distributed under the Business Source License; the plugin ecosystem remains open.

## Related

- [[Linux/boot-init/boot-process|Linux boot process]] — what happens between image and running system
- [[Linux/virtualization/hypervisors|Hypervisors]]
- [[Kubernetes/concepts/L07-security/05-audit-ops-compliance/21-node-hardening|Node hardening]]
- [Packer documentation](https://developer.hashicorp.com/packer/docs)

## Further reading

- [Packer (video)](https://www.youtube.com/watch?v=LJj8cRKSigI)
