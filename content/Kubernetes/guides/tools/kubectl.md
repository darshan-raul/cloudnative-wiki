---
title: kubectl
tags:
  - Kubernetes
  - Tools
  - CLI
---

*Source: [kubectl reference](https://kubernetes.io/docs/reference/kubectl/)*

The primary CLI for Kubernetes. Every other tool (`k9s`, `Lens`, `stern`, `kubectx`) wraps or composes `kubectl`. Knowing it well is the floor for operating any cluster.

## Mental model

`kubectl` is a **client** that talks to the apiserver. The apiserver is the only thing that ever touches etcd. So every `kubectl` command:

1. Authenticates you (kubeconfig + cert/token)
2. Sends an HTTP request to the apiserver
3. Returns the response (or applies your change)

That means **`kubectl` is stateless** — no daemon, no local DB. You can run it from anywhere with a valid kubeconfig.

```
$ kubectl get pods
       │
       ▼  (read $KUBECONFIG or ~/.kube/config)
┌────────────────┐
│  kubeconfig    │  cluster, user, context, namespace
└────────┬───────┘
         │  (TLS + auth)
         ▼
┌────────────────┐
│   apiserver    │  validates, authorizes, persists
└────────┬───────┘
         │
         ▼
   etcd (cluster state)
```

## The 4 most-used verbs

| Verb | What it does | Common options |
|------|--------------|----------------|
| `get` | List / show resources | `-n`, `-A`, `-o yaml/json`, `-w`, `--field-selector`, `-l` |
| `describe` | Show details + events | `-n` |
| `apply` | Create/update from a file | `-f`, `--dry-run=server`, `--validate=false` |
| `delete` | Remove a resource | `-f`, `--grace-period=0`, `--force` |

The rest (`logs`, `exec`, `cp`, `port-forward`, `top`, `edit`, `patch`, `scale`, `rollout`, `drain`, `cordon`) are all variations on these.

## Resource types: the shortlist

Memorize these — covers 90% of what you do day-to-day:

```bash
# workloads
pod (po), deployment (deploy), statefulset (sts), daemonset (ds),
job, cronjob, replicaset (rs)

# networking
service (svc), ingress (ing), networkpolicy (netpol), endpoint (ep),
endpointslice (eps)

# config
configmap (cm), secret

# storage
persistentvolume (pv), persistentvolumeclaim (pvc), storageclass (sc)

# cluster
node, namespace (ns), event, serviceaccount (sa)

# access control
role, rolebinding, clusterrole, clusterrolebinding

# workloads (operators)
deployment, statefulset, daemonset

# CRDs (your installed operators)
argo rollouts, certificate, ingress, etc.
```

Get the full list with `kubectl api-resources`.

## Output formats

Default is human-readable columns. Useful alternatives:

```bash
# YAML — pipe to a file, edit, re-apply
kubectl get deploy web -o yaml > web.yaml

# JSON — for jq processing
kubectl get pods -o json | jq '.items[].metadata.name'

# JSONPath — extract one field
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'

# custom columns — ad-hoc tables
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IP:.status.podIP
```

`-o wide` is the killer feature most people miss — adds extra columns (Node, IP, Image) without needing to write a template.

## Labels and selectors

Labels are how you query at scale. Always label everything:

```bash
# set labels
kubectl label pod web-1 env=prod tier=frontend

# query by label
kubectl get pods -l env=prod
kubectl get pods -l 'env in (prod, staging)'
kubectl get pods -l '!dev'                   # NOT
kubectl get pods -l 'tier=frontend,env=prod' # AND
kubectl get pods -l 'env=prod,tier!=db'      # AND with inequality

# show labels in output
kubectl get pods --show-labels
```

Service selectors, Deployment selectors, NetworkPolicy selectors — all key off labels. Unlabeled resources are unmanageable resources.

## Namespaces

```bash
# list namespaces
kubectl get ns

# set default for current context
kubectl config set-context --current --namespace=my-app

# per-command
kubectl get pods -n kube-system
kubectl get pods -A   # all namespaces

# create
kubectl create ns my-app

# delete (cascades to all resources in ns)
kubectl delete ns my-app
```

`--all-namespaces` (`-A`) is the safer default until you know which namespace something is in.

## Wait, watch, and follow

`kubectl get` returns once and exits. Three ways to observe over time:

```bash
# watch: re-run every 2s
kubectl get pods -w

# wait: block until a condition is true (CI/CD use)
kubectl wait --for=condition=ready pod -l app=web --timeout=300s
kubectl wait --for=jsonpath='{.status.replicas}'=3 deploy/web

# events: see what just happened
kubectl get events --sort-by='.lastTimestamp' -A
kubectl get events --field-selector type=Warning
```

`kubectl wait` is the right tool for CI pipelines — `apply` and wait for `ready` instead of sleeping.

## `exec` and debugging

```bash
# shell into a pod
kubectl exec -it web-1 -- /bin/sh

# one-off command
kubectl exec web-1 -- cat /etc/config.yml

# multi-container pod — pick one
kubectl exec -it web-1 -c sidecar -- /bin/sh

# copy files
kubectl cp ./local.txt web-1:/tmp/remote.txt
kubectl cp web-1:/tmp/log.txt ./log.txt

# port forward
kubectl port-forward svc/web 8080:80        # svc:8080 -> svc:80
kubectl port-forward pod/web-1 8080:80      # pod direct
kubectl port-forward deploy/web 8080:80     # picks a pod
```

`exec` needs the pod to have a shell installed. If you're on `distroless` or `scratch`, this won't work — use `kubectl debug` instead.

## `kubectl debug` (the new way)

`kubectl debug` (alpha → beta) creates an **ephemeral debug container** that shares the target pod's namespaces:

```bash
# debug a pod (adds a debug sidecar)
kubectl debug -it web-1 --image=busybox --target=web-1 -- /bin/sh

# debug a node (creates a debug pod on the node, host namespaces)
kubectl debug node/mynode -it --image=busybox

# debug by copy (creates a copy of the pod with extra config)
kubectl debug web-1 -it --copy-to=web-1-debug --container=debug --image=busybox -- sh
```

This is the right tool when:
- Target pod uses distroless/scratch (no shell)
- You need host-level access (network, mount)
- You don't want to `exec` into a prod pod

## Logs

```bash
# basic
kubectl logs web-1

# previous instance (after a crash)
kubectl logs web-1 --previous

# multi-container pod
kubectl logs web-1 -c sidecar

# stream
kubectl logs -f web-1

# tail last N lines
kubectl logs web-1 --tail=100

# since a duration
kubectl logs web-1 --since=10m
kubectl logs web-1 --since-time=2024-01-15T10:00:00Z

# all pods with a label
kubectl logs -l app=web --tail=20 -f
```

For multi-pod tailing, use `stern` (separate tool):

```bash
stern -l app=web --tail 20    # tails all pods with app=web
```

## `apply`, `edit`, `patch` — the three ways to change things

```bash
# apply: declarative, idempotent, file-based
kubectl apply -f manifest.yaml
kubectl apply -f ./dir/        # recursive

# edit: open in $EDITOR
kubectl edit deploy/web

# patch: programmatic, in-line
kubectl patch svc web -p '{"spec":{"type":"NodePort"}}'
kubectl patch deploy web --type=json -p '[{"op":"replace","path":"/spec/replicas","value":5}]'
```

**`apply` is the production default.** `edit` is fine for poking around; never `edit` in a CI/CD pipeline. `patch` is the right tool for scripted one-offs.

## Dry runs and server-side apply

```bash
# client-side dry run (parses locally, doesn't contact apiserver)
kubectl apply -f manifest.yaml --dry-run=client

# server-side dry run (contacts apiserver, validates against schema, but doesn't persist)
kubectl apply -f manifest.yaml --dry-run=server

# server-side apply (NEW: lets the apiserver track field ownership)
kubectl apply -f manifest.yaml --server-side
kubectl apply -f manifest.yaml --server-side --force-conflicts
```

**Use `--dry-run=server` in CI** to catch schema errors before they hit the cluster.

## Context and config

```bash
# show current config
kubectl config view
kubectl config current-context

# switch context
kubectl config use-context prod

# set default namespace
kubectl config set-context --current --namespace=web

# view raw kubeconfig (certs redacted by default)
kubectl config view --raw

# test auth (works for any user/cluster)
kubectl auth can-i create pods
kubectl auth can-i '*' '*' --as=system:serviceaccount:default:my-sa
```

`auth can-i` is the right tool for "does my RBAC actually let me do X?" troubleshooting.

## Resource management

```bash
# scale
kubectl scale deploy/web --replicas=5

# rollout
kubectl rollout status deploy/web
kubectl rollout history deploy/web
kubectl rollout undo deploy/web            # rollback
kubectl rollout undo deploy/web --to-revision=3

# set image (rolls out)
kubectl set image deploy/web web=myorg/web:v2

# annotate (useful for retries/cleanup hooks)
kubectl annotate pod web-1 retry=true
```

## JSONPath and field selection

The `-o jsonpath` template syntax is the awk of `kubectl`:

```bash
# all pod names
kubectl get pods -o jsonpath='{.items[*].metadata.name}'

# all node InternalIPs
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'

# one field per line (range)
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'

# count
kubectl get pods -o jsonpath='{.items}' | jq 'length'
```

`field-selector` is faster than jq for server-side filtering:

```bash
# only running pods
kubectl get pods --field-selector=status.phase=Running

# pods on a specific node
kubectl get pods --field-selector=spec.nodeName=node-1

# only failed events
kubectl get events --field-selector=type=Warning
```

## Plugins (Krew)

`kubectl` has a plugin model — any executable named `kubectl-<name>` on `$PATH` is a subcommand. **Krew** is the de-facto plugin manager:

```bash
# install krew
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-${OS}_${ARCH}.tar.gz" &&
  tar zxvf krew-${OS}_${ARCH}.tar.gz &&
  ./krew-"${OS}_${ARCH}" install krew
)

# add to PATH
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# install plugins
kubectl krew install ctx ns stern tail node-shell images

# now you have:
kubectl ctx                    # switch context interactively
kubectl ns                     # switch namespace interactively
kubectl stern -l app=web       # tail multiple pods
kubectl tail -l app=web        # alternative tail
kubectl node-shell node-1      # shell into a node
kubectl images                 # show image -> pod mapping
```

## Pluggable authentication (exec / auth-provider)

`kubectl` doesn't talk to identity providers directly. It calls out to a plugin:

```bash
# AWS EKS — uses aws-cli
aws eks update-kubeconfig --name my-cluster --region us-east-1

# GCP GKE — uses gcloud
gcloud container clusters get-credentials my-cluster --region us-central1

# OIDC with Keycloak — uses kubelogin
kubectl oidc-login setup --oidc-issuer-url=https://keycloak.example.com/realms/k8s \
  --oidc-client-id=k8s --oidc-client-secret=xxx

# SSO with Okta, Azure AD, etc. — uses openid-client or your distro's plugin
```

The `kubeconfig` stores the **command to run** for auth; `kubectl` invokes it on demand:

```yaml
users:
- name: alice
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1
      command: aws
      args:
        - eks
        - get-token
        - --cluster-name
        - my-cluster
```

## Common gotchas

* **`-A` is your friend.** Forgetting `-n`/`-A` returns empty when you're not in the right namespace.
* **`kubectl get` doesn't show labels by default.** Use `--show-labels`. Annotations never show.
* **`apply` is merge, not replace.** Re-applying a manifest doesn't remove fields you deleted from the file. To replace, use `replace --force` or `apply --prune`.
* **`edit` overwrites your kubeconfig last-applied annotation.** Don't `edit` in CI.
* **`exec` requires a shell in the container.** Distroless and scratch images break this — use `kubectl debug`.
* **`logs --previous` only works after a crash.** If the container was just OOM-killed, `--previous` shows the last logs.
* **`--dry-run=client` doesn't catch server-side errors.** Always use `server` in CI.
* **`kubectl proxy` exposes the apiserver on localhost:8001** — convenient for UI tools, but a security risk if the port is reachable. Don't run this on a jump host.
* **The `kubectl.kubernetes.io/last-applied-configuration` annotation grows with each apply.** Long-lived resources accumulate JSON blobs in their annotations. Not a problem normally, but watch for it with very dynamic configs.
* **`kubectl diff` shows you what `apply` would change.** Use it.
* **`-o name` is the secret weapon for scripting:** `kubectl get pods -l app=web -o name | xargs kubectl delete`.

## Useful one-liners

```bash
# restart a deployment (forces a rollout)
kubectl rollout restart deploy/web

# get pod logs grouped by container, all containers in all pods
for p in $(kubectl get pods -l app=web -o name); do
  echo "=== $p ==="
  kubectl logs $p --all-containers --tail=5
done

# drain a node for maintenance
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data

# mark node unschedulable (without evicting)
kubectl cordon node-1

# re-enable
kubectl uncordon node-1

# copy secret from one ns to another
kubectl get secret my-secret -n src -o yaml | sed 's/namespace: src/namespace: dst/' | kubectl apply -f -

# delete all evicted pods
kubectl get pods -A --field-selector=status.phase=Failed -o name | xargs kubectl delete

# get the image running in a deployment
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[*].image}'

# watch a rollout
kubectl rollout status deploy/web -w
```

## Shell completion and aliases

```bash
# bash
source <(kubectl completion bash)

# zsh
source <(kubectl completion zsh)

# aliases that save a million keystrokes
alias k=kubectl
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kex='kubectl exec -it'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
complete -F __start_kubectl k
```

## Further reading

* [[Kubernetes/guides/tools/k9s|k9s]] — terminal UI built on kubectl
* [[Kubernetes/guides/tools/context-switching|context-switching]] — kubeconfig management
* [[Kubernetes/guides/tools/multi-cluster|multi-cluster]] — operating many clusters
* [kubectl reference](https://kubernetes.io/docs/reference/kubectl/)
* [kubectl book](https://kubectl.docs.kubernetes.io/) — concept-level walkthrough
