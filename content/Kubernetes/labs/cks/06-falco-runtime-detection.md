---
title: "Lab CKS-06 — Falco Runtime Detection"
tags: [kubernetes, labs, cks, falco, runtime-security, detection]
date: 2026-10-13
description: "Install Falco, trigger and read its alerts, trace an alert back to the Pod with crictl, write a custom rule and override the output of a default rule."
---

# Lab CKS-06 — Falco Runtime Detection

Admission control decides what may start. Falco watches what containers do once they are running, by evaluating rules against the system calls they make. CKS tasks on Falco come in two shapes: find the workload that triggered an alert and deal with it, or change a rule so the alert has a required format.

Concepts: [[Kubernetes/concepts/L07-security/02-workload-sandboxing/18-runtime-detection|Runtime Detection (Falco, Tetragon)]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there.

Verified on `kind` v0.31 with Kubernetes v1.35.0 and Falco 0.45 (Helm chart 9.2.0, `modern_ebpf` driver).

---

## 1. Prerequisites & Starting State

- Working `k8s-lab` cluster from **[[Kubernetes/labs/ckad/01-cluster-setup|Lab CKAD-01]]**, and Helm.
- A Linux host with a kernel recent enough for the modern eBPF driver (5.8 or later).

```bash
kubectl create namespace falco-lab
kubectl -n falco-lab run target --image=busybox:1.36 -- sleep 3600
```

### Install Falco

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update falcosecurity
helm install falco falcosecurity/falco -n falco --create-namespace \
  --set tty=true --set driver.kind=modern_ebpf
kubectl -n falco rollout status daemonset/falco
```

Falco runs as a DaemonSet, one Pod per node, and each Pod only sees events from its own node.

> [!note] How this differs from the exam
> In the exam Falco usually runs as a **systemd service on the node**. Alerts are in `journalctl -u falco` or a log file, rules are in `/etc/falco/`, and you apply a change with `systemctl restart falco`. The rules, their syntax and the investigation method are identical; only where you read and edit differs. The table in section 5 maps the two.

---

## 2. Trigger and Read an Alert

```bash
kubectl -n falco-lab exec target -- cat /etc/shadow
```

Read the alert from the Falco Pod on the node where `target` runs:

```bash
NODE=$(kubectl -n falco-lab get pod target -o jsonpath='{.spec.nodeName}')
FALCO=$(kubectl -n falco get pod -o name --field-selector spec.nodeName=$NODE)
kubectl -n falco logs $FALCO -c falco --tail=200 | grep shadow
```

```text
07:08:41.771728497: Warning Sensitive file opened for reading by non-trusted program | file=/etc/shadow ... process=cat proc_exepath=/bin/cat parent=sh command=cat /etc/shadow terminal=0 container_id=3df3c059c605 ...
```

An alert line has three parts: a timestamp, the rule's priority, and the rule's output string with its fields filled in. The fields worth finding first are `container_id`, the process (`command`), and the user.

---

## 3. Trace an Alert to Its Pod

Depending on how Falco is configured, the Pod name is either in the alert or shown as `<NA>`. The `container_id` is always there, and the container runtime can resolve it:

```bash
docker exec -it $NODE bash
# node
crictl ps --id 3df3c059c605
crictl inspect 3df3c059c605 | jq -r '.status.labels["io.kubernetes.pod.namespace"] + "/" + .status.labels["io.kubernetes.pod.name"]'
crictl inspect 3df3c059c605 | jq .info.pid
```

```text
falco-lab/target
3756
```

The last command prints the container's process ID on the node, which lets you look at the process directly with `ps -fp <pid>` or under `/proc/<pid>/`.

A typical task then says what to do with the offender, usually scale its Deployment to zero or delete the Pod:

```bash
kubectl -n falco-lab scale deployment <name> --replicas=0
```

Scale the controller, not the Pod. Deleting a Pod that belongs to a Deployment only gets it recreated.

---

## 4. Write a Custom Rule

A rule needs five fields:

| Field       | Meaning                             |
| :---------- | :---------------------------------- |
| `rule`      | Unique name                         |
| `desc`      | Description                         |
| `condition` | Filter expression over event fields |
| `output`    | Message, with `%field` placeholders |
| `priority`  | `EMERGENCY` down to `DEBUG`         |

Save this as `falco-values.yaml`:

```yaml
tty: true
driver:
  kind: modern_ebpf
customRules:
  lab-rules.yaml: |-
    - rule: Shell Spawned in Container
      desc: A shell process started inside a container
      condition: spawned_process and container.id != host and proc.name in (sh, bash, ash)
      output: "Shell in container | time=%evt.time container_id=%container.id user=%user.name cmd=%proc.cmdline"
      priority: WARNING
      tags: [lab]
```

```bash
helm upgrade falco falcosecurity/falco -n falco -f falco-values.yaml
kubectl -n falco rollout status daemonset/falco
```

Trigger it and read the result:

```bash
kubectl -n falco-lab exec target -- sh -c id
FALCO=$(kubectl -n falco get pod -o name --field-selector spec.nodeName=$NODE)
kubectl -n falco logs $FALCO -c falco --tail=300 | grep 'Shell in container'
```

```text
07:10:36.106558351: Warning Shell in container | time=07:10:36.106558351 container_id=3df3c059c605 user=root cmd=sh -c id ...
```

`spawned_process` and `container` are **macros** defined in the default rules file. Reusing them keeps conditions short. `falco --list` prints every field you can use in a condition or an output.

On a shared Docker host you may also see alerts for containers that belong to other `kind` clusters. Falco watches the kernel, and all `kind` nodes on one machine share it.

---

## 5. Override a Default Rule

Never edit the default rules file. A package upgrade overwrites it. Change a rule from a local file instead, naming the rule and stating which keys to override.

Add this to `customRules` in `falco-values.yaml`, below the first rule:

```yaml
- rule: Read sensitive file untrusted
  output: "Sensitive read | time=%evt.time container_id=%container.id file=%fd.name cmd=%proc.cmdline"
  override:
    output: replace
```

```bash
helm upgrade falco falcosecurity/falco -n falco -f falco-values.yaml
kubectl -n falco rollout status daemonset/falco
kubectl -n falco-lab exec target -- cat /etc/shadow
FALCO=$(kubectl -n falco get pod -o name --field-selector spec.nodeName=$NODE)
kubectl -n falco logs $FALCO -c falco --tail=300 | grep 'Sensitive read'
```

```text
07:39:44.617300357: Warning Sensitive read | time=07:39:44.617300357 container_id=3df3c059c605 file=/etc/shadow cmd=cat /etc/shadow ...
```

The condition and priority are unchanged and only the output differs. `override` also accepts `append` for conditions and lists, and `enabled: false` switches a rule off.

Where things live:

| What               | Helm DaemonSet (this lab)                             | Service on a node (exam)                                   |
| :----------------- | :---------------------------------------------------- | :--------------------------------------------------------- |
| Default rules      | `/etc/falco/falco_rules.yaml` in the Pod              | `/etc/falco/falco_rules.yaml`                              |
| Local rules        | `customRules` value, mounted in `/etc/falco/rules.d/` | `/etc/falco/falco_rules.local.yaml`                        |
| Main configuration | `falco` ConfigMap                                     | `/etc/falco/falco.yaml`                                    |
| Read alerts        | `kubectl -n falco logs <pod> -c falco`                | `journalctl -u falco`, or the file set under `file_output` |
| Apply a change     | `helm upgrade`                                        | `systemctl restart falco`                                  |

Files are loaded in the order listed under `rules_files` in `falco.yaml`, and later files override earlier ones.

---

## 6. Controlled Failure Scenario: A Rule That Does Not Load

Break the custom rule by referring to a field that does not exist. In `falco-values.yaml`, change `%proc.cmdline` to `%proc.commandline` in the first rule and upgrade:

```bash
helm upgrade falco falcosecurity/falco -n falco -f falco-values.yaml
kubectl -n falco get pods
kubectl -n falco logs <crashing-falco-pod> -c falco --tail=20
```

```text
Error: /etc/falco/rules.d/lab-rules.yaml: Invalid
...
LOAD_ERR_COMPILE_OUTPUT (Error compiling output): unknown filter: ...
```

The first updated Falco Pod goes into `CrashLoopBackOff` and the DaemonSet rollout stops there, so the other nodes keep running the old rules. The log names the file and the rule it could not compile.

Falco refuses to start with any invalid rule. On a node where it runs as a service that means **nothing** is being detected until the file is fixed, so a rule typo is an outage of the whole detection layer and not just of one rule.

On a node, validate before restarting:

```bash
falco --validate /etc/falco/falco_rules.local.yaml
```

Restore `%proc.cmdline` and upgrade again.

---

## 7. Cleanup

```bash
kubectl delete namespace falco-lab
helm uninstall falco -n falco && kubectl delete namespace falco
rm -f falco-values.yaml
```

---

## Further reading

- [Falco rules](https://falco.org/docs/concepts/rules/)
- [Overriding rules](https://falco.org/docs/concepts/rules/overriding/)
- [Supported fields for conditions and outputs](https://falco.org/docs/reference/rules/supported-fields/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/07-image-scanning-and-static-analysis|Lab CKS-07 — Image Scanning & Static Analysis]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
