---
title: Ansible
tags: [devops, infrastructure-as-code, ansible, configuration-management]
date: 2026-10-10
description: Ansible for configuration management — the agentless push model, inventory, playbooks, modules and idempotence, variables and precedence, roles and collections, Vault, testing, and where Ansible fits beside Terraform and containers.
---

# Ansible

Ansible configures machines over SSH. There is no agent to install: a control node connects to each host, copies a small program for the task, runs it and removes it. You describe the desired configuration in YAML **playbooks**, and Ansible makes each host match.

It is the tool for the layer _inside_ a machine — packages, files, services, users — and for anything else reachable by SSH or an API: network devices, appliances, legacy servers. For where that sits, see [[DevOps/infrastructure-as-code/README|infrastructure as code]].

## How it works

```
control node                                   managed hosts
┌───────────────────────┐        SSH           ┌──────────────┐
│ inventory  (which)    │ ───────────────────► │ web1         │  needs only
│ playbook   (what)     │   push module, run,  │ web2         │  SSH + Python
│ roles, vars, vault    │ ◄─── JSON result ─── │ db1          │
└───────────────────────┘                      └──────────────┘
```

Because it pushes, nothing happens between runs: Ansible does not correct drift unless something runs it again. That is the main architectural difference from agent-based tools such as Puppet, and from the continuous reconciliation of Kubernetes.

## Inventory

The inventory lists hosts and groups them.

```yaml
# inventory/prod.yaml
all:
  children:
    web:
      hosts:
        web1.example.com:
        web2.example.com:
      vars:
        http_port: 8080
    db:
      hosts:
        db1.example.com:
```

In a cloud, hosts come and go, so use a **dynamic inventory** plugin that queries the provider and groups by tag:

```yaml
# inventory/aws_ec2.yaml
plugin: amazon.aws.aws_ec2
regions: [eu-west-1]
filters:
  tag:environment: prod
keyed_groups:
  - key: tags.role
    prefix: role
```

## Playbooks

```yaml
# site.yaml
- name: Configure web servers
  hosts: web
  become: true
  vars:
    nginx_worker_connections: 4096
  tasks:
    - name: Install nginx
      ansible.builtin.package:
        name: nginx
        state: present

    - name: Deploy configuration
      ansible.builtin.template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
        owner: root
        mode: "0644"
        validate: nginx -t -c %s
      notify: Reload nginx

    - name: Ensure nginx is running
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true

  handlers:
    - name: Reload nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

```bash
ansible-playbook -i inventory/prod.yaml site.yaml --check --diff   # dry run
ansible-playbook -i inventory/prod.yaml site.yaml --limit web1.example.com
```

- A **play** maps a group of hosts to a list of **tasks**.
- Each task calls a **module** with arguments.
- **Handlers** run once at the end of a play, and only if a task that notifies them reported a change — reload the service only when its configuration actually changed.
- `--check --diff` shows what would change. Run it in CI and before any production run.

## Idempotence

A task should describe a state, not an action: "nginx is installed", not "install nginx". Modules check the current state first and do nothing if it already matches, so a playbook can run repeatedly and reports `changed` only for real changes.

This breaks when you reach for `shell` or `command`, which run unconditionally. When you must use them, make them idempotent yourself:

```yaml
- name: Initialise the database once
  ansible.builtin.command: /opt/app/bin/init-db
  args:
    creates: /var/lib/app/.initialised
```

A playbook whose second run reports zero changes is correct. One that always reports changes is hiding something. The underlying system concepts are in [[Linux/concepts/06-services|services]], [[Linux/boot-init/systemd|systemd]] and [[Linux/concepts/05-package-management|package management]].

## Variables

Variables can be defined in more than twenty places, and precedence is the most common source of confusion. The useful simplification, lowest to highest:

1. Role defaults (`roles/x/defaults/main.yaml`) — meant to be overridden
2. Inventory group variables (`group_vars/`)
3. Inventory host variables (`host_vars/`)
4. Play and role variables
5. Extra variables on the command line (`-e`) — always win

Keep defaults in roles, environment differences in `group_vars`, and avoid setting the same variable at several levels. **Facts** are variables gathered from each host at the start of a play (`ansible_facts.distribution`, memory, interfaces) and are how one playbook adapts to different operating systems.

## Roles and collections

A **role** packages tasks, templates, files, handlers and defaults for one concern:

```
roles/nginx/
├── defaults/main.yaml     # overridable variables
├── tasks/main.yaml
├── handlers/main.yaml
├── templates/nginx.conf.j2
└── meta/main.yaml         # dependencies
```

A **collection** bundles roles, modules and plugins under a namespace (`amazon.aws`, `community.general`, `kubernetes.core`). Pin collection versions in `requirements.yml`, exactly as you pin providers in Terraform.

## Secrets

**Ansible Vault** encrypts files or individual values with a password:

```bash
ansible-vault encrypt group_vars/prod/vault.yaml
ansible-playbook site.yaml --vault-password-file ~/.vault-pass
```

The encrypted file is safe to commit. For larger setups, look values up from a secret manager at run time instead of storing them at all — lookup plugins exist for [[AWS/security/secrets-manager/README|AWS Secrets Manager]], HashiCorp Vault and others. Add `no_log: true` to tasks that handle secrets, or they appear in output.

## Scaling and running it

| Concern              | Approach                                                                                                               |
| :------------------- | :--------------------------------------------------------------------------------------------------------------------- |
| Speed                | Raise `forks`; enable SSH pipelining and connection multiplexing; cache facts                                          |
| Rolling changes      | `serial: 2` or `serial: "25%"` with `max_fail_percentage`, so a bad change stops early                                 |
| Central execution    | AWX / Ansible Automation Platform, or a CI pipeline: scheduling, RBAC, audit, credentials                              |
| Reproducible runtime | Execution environments — container images with a pinned Ansible and collections                                        |
| Access               | A dedicated automation user with scoped `sudo`; SSH keys or certificates ([[Linux/ssh/ssh-config\|SSH configuration]]) |

## Testing

- `ansible-lint` and `yamllint` on every commit.
- `--check --diff` against a staging inventory in CI.
- **Molecule** runs a role in a container or VM, applies it, applies it again to prove idempotence, and runs verification tests.

## Ansible and Terraform

They solve different problems and work well together.

|                  | Terraform / OpenTofu                | Ansible                                             |
| :--------------- | :---------------------------------- | :-------------------------------------------------- |
| Best at          | Creating and wiring cloud resources | Configuring what runs inside a machine              |
| Tracks ownership | Yes, in state                       | No — it does not know what it created earlier       |
| Deleting things  | Remove from code, it is destroyed   | Must be written as an explicit `state: absent` task |
| Ordering         | A dependency graph                  | Top to bottom, as written                           |

A common pipeline: [[DevOps/infrastructure-as-code/terraform|Terraform]] creates instances, Ansible configures them — or, better, Ansible runs inside [[DevOps/infrastructure-as-code/packer|Packer]] to bake an image and the instances boot already configured.

## Where it still fits in a container world

Containers and immutable images removed much of the need for configuration management on application servers. Ansible remains the practical choice for:

- building golden images,
- bootstrapping and hardening hosts and Kubernetes nodes ([[Linux/security/linux-cis-hardening|CIS hardening]]),
- fleets of long-lived VMs, databases and on-premises servers,
- network devices and appliances with no agent support,
- orchestrated, ordered procedures: rolling patching, failovers, migrations.

The Wazuh deployment in this wiki is an example of that last kind of work: [[Security/siem/wazuh/production-plan/README|Wazuh production plan]].

## Related

- [[DevOps/infrastructure-as-code/README|Infrastructure as code]]
- [[Linux/README|Linux section]] — what Ansible is actually changing
- [[AWS/management-governance/systems-manager/README|AWS Systems Manager]] — an agent-based alternative on AWS
- [Ansible documentation](https://docs.ansible.com/)
