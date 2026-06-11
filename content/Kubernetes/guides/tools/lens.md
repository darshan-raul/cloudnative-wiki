---
title: Lens
tags:
  - Kubernetes
  - Tools
  - Desktop
  - Dashboard
---

*Source: [k8slens.dev](https://k8slens.dev/)*

Lens is a **desktop application** for managing multiple Kubernetes clusters. Think of it as `kubectl` with a real GUI, plus multi-cluster support, plus Helm chart management, plus a built-in terminal. It's the dashboard engineers reach for when `k9s` feels too low-level and the browser-based dashboards feel too heavy.

## Why Lens (and not k9s, Octant, Rancher)?

| Tool | Strength | Weakness |
|------|----------|----------|
| **k9s** | Fast, terminal-native, scriptable | One cluster per window, no Helm UI |
| **Lens** | Multi-cluster, full GUI, Helm UI, terminal built in | Desktop app, Electron-based |
| **Octant** | Web-based, in-cluster | Per-cluster install, no fleet view |
| **Rancher** | Full fleet management, RBAC | Heavy, more for ops than devs |
| **Headlamp** | Web-based, in-cluster | Younger project |

For a **developer working across 3-20 clusters**, Lens is the sweet spot. It runs locally as a desktop app, talks to clusters via your existing kubeconfig, and adds zero cluster-side state.

## Installation

```bash
# macOS
brew install --cask lens

# Windows
winget install lensapp

# Linux (snap)
sudo snap install kontena-lens

# Linux (deb)
wget https://api.k8slens.dev/binaries/Lens-2024-...-amd64.deb
sudo dpkg -i Lens-*.deb
```

Lens is a **single binary**. It reads your `~/.kube/config` on first launch and shows you every cluster it can reach.

## Adding clusters

Lens inherits your kubeconfig. To add a cluster:

```bash
# EKS
aws eks update-kubeconfig --name prod --region us-east-1

# GKE
gcloud container clusters get-credentials prod --region us-central1

# AKS
az aks get-credentials --name prod --resource-group prod-rg

# generic
kubectl config set-cluster my-cluster --server=https://api.example.com:6443 \
  --certificate-authority=ca.crt
kubectl config set-credentials my-user --token=...
kubectl config set-context my-context --cluster=my-cluster --user=my-user
```

Restart Lens (or click the refresh icon) — the new cluster appears in the catalog. **No Lens-specific configuration needed**.

For many clusters, use **kubeconfig merging**:

```bash
export KUBECONFIG=~/.kube/config:~/.kube/eks-prod:~/.kube/gke-staging
```

Lens picks up every context in the merged config.

## The interface

```
┌────────────────────────────────────────────────────────────┐
│  Cluster Catalog (top bar)                                 │
│  [prod-eks-admin] [staging-eks] [dev-minikube] [+]         │
├──────────┬─────────────────────────────────────────────────┤
│  Workloads │                                                │
│  ├ Pods   │  Pods (selected: prod-eks-admin)               │
│  ├ Deploy │  ┌──────────┬─────────┬──────┬──────┬────────┐ │
│  ├ StSet  │  │ Name     │ Status  │ Rest │ CPU  │ Memory │ │
│  ├ Daemon │  ├──────────┼─────────┼──────┼──────┼────────┤ │
│  ├ Jobs   │  │ web-1    │ Running │ 0    │ 50m  │ 128Mi  │ │
│  └ Cron   │  │ web-2    │ Running │ 0    │ 45m  │ 130Mi  │ │
│           │  │ web-3    │ Running │ 0    │ 48m  │ 125Mi  │ │
│  Network  │  │ api-1    │ Running │ 0    │ 80m  │ 256Mi  │ │
│  ├ Svcs   │  │ api-2    │ Running │ 1    │ 75m  │ 260Mi  │ │
│  ├ Ingress│  └──────────┴─────────┴──────┴──────┴────────┘ │
│  └ NetPol │                                                │
│           │  (click a pod → log stream, exec, edit, etc.)  │
│  Storage  │                                                │
│  ...     │                                                │
└──────────┴─────────────────────────────────────────────────┘
```

Left sidebar: resource categories (Workloads, Network, Storage, Config, Access Control, Custom Resources, Nodes, Events).
Center: list view, sortable, filterable.
Right pane: details for the selected resource.

## Key features

### Multi-cluster view

The top bar shows every cluster in your kubeconfig. Click to switch. **Each cluster maintains its own view state** — switching doesn't lose your filters.

For "show me all the failed pods across all clusters" — use the **search/filter bar** at the top. Filter applies to current cluster only, but you can script cross-cluster with `kubectl` and paste the output into Lens's terminal.

### Pod logs with search

Click a pod → Logs tab. Lens streams logs in real-time, with:
- Search box (substring)
- Color coding by container
- Pause / resume
- Container switcher (multi-container pods)
- "Previous" container (for crashed pods)

Better than `kubectl logs -f` for visual inspection, worse for grep/sed workflows. Use both.

### Built-in terminal

The terminal tab in the pod details view gives you a shell inside the container — `kubectl exec` under the hood. It's a full PTY, so `vim`, `htop`, etc. work.

If the container is distroless/scratch (no shell), the terminal won't work — use `kubectl debug` from your local terminal instead.

### Helm releases

Helm → Releases shows every installed release. Click one:
- See the rendered manifests
- See the values used (with secrets redacted)
- Rollback to a previous revision
- Upgrade with new values
- Uninstall

Lens reads your local Helm config. It needs Helm installed on the path it uses (usually `~/.lens/helm` or system `helm`).

### Resource editing

Click a resource → "..." menu → Edit. Opens a YAML editor in a side panel. Save → kubectl apply. Useful for quick changes; **don't use in CI**.

### RBAC inspection

Access Control → Roles / RoleBindings. Click a binding → see who has it, what verbs. **Auth** tab shows the user you're authenticated as, what `auth can-i` says.

### Custom Resources

Custom Resources shows every CRD installed in the cluster. Click a CRD → see instances, group by namespace. This is where operators live (Argo CD apps, cert-manager certificates, etc.).

### Terminal in the bottom drawer

Press **Ctrl+`** (or click the terminal icon) to open a full terminal at the bottom. This is a **local shell**, not a pod shell. Useful for running `kubectl` directly when you need it.

## Useful Lens features

### 1. The "Open in Terminal" button

For a Deployment, Service, or ConfigMap, "Open in Terminal" runs `kubectl edit <resource>` in the bottom terminal. You can edit in `vim`/`nano` and save — Lens detects the change and refreshes.

### 2. Diff between revisions

For a Helm release, "History" → click a revision → "Diff with current". Shows the YAML diff between the two revisions. Better than `helm history` + `helm get manifest` for understanding what changed.

### 3. Cluster health at a glance

Nodes view → all nodes color-coded by condition. Green = Ready, red = NotReady, orange = MemoryPressure/DiskPressure. Click a node → see kubelet logs, conditions, events.

### 4. Pod details → port forwarding

Click a pod → "Forward" → specify local port and pod port → Lens opens a tunnel. Useful for debugging a service that's only accessible from inside the cluster.

### 5. Snapshots and rollback

For Deployments: "View YAML" → see the **last applied** configuration (the one in your git repo) and the **current** state (what's actually running). The diff shows drift.

For Helm releases: every revision is stored. Rollback is one click.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl+K` | Quick search (resources, clusters) |
| `Cmd/Ctrl+P` | Command palette |
| `Cmd/Ctrl+Shift+P` | Reload view |
| `Cmd/Ctrl+T` | Open terminal |
| `Cmd/Ctrl+R` | Reload cluster state |
| `/` | Filter current view |
| `Esc` | Close drawer / cancel |

## Gotchas

* **Lens is local.** It doesn't run inside the cluster, doesn't store state, doesn't add RBAC. If your laptop dies, you lose nothing — just reconnect to the same kubeconfig.
* **Lens is a viewer, not an editor.** Many things can be edited in Lens, but **your git repo is the source of truth**. If you're using GitOps (Argo CD, Flux), Lens edits fight the reconciler. Don't edit in Lens; edit in git.
* **Electron app.** It uses memory — typically 200-500MB. Not great on a 4GB laptop. For low-spec machines, prefer `k9s`.
* **Helm UI requires Helm installed locally.** If Lens can't find `helm` binary, the Helm view is empty.
* **No offline mode.** Lens is online-only (it pulls updates, telemetry — disable in settings). Some compliance regimes require fully offline tools.
* **Lens Metrics is opt-in.** Default installation has telemetry. Settings → Telemetry → off.
* **Some CRDs render badly.** Lens ships generic renderers; complex CRDs (Argo Workflows, Crossplane) may show raw YAML only. Use the YAML view.
* **Lens doesn't replace monitoring.** It's a UI for live state, not a metrics dashboard. Use Prometheus + Grafana for that.
* **Lens doesn't replace RBAC.** Whatever you can do in `kubectl`, you can do in Lens. If you don't have `get secrets` permission, you can't see secrets in Lens. (You can see the names, but the data is redacted.)

## When to use Lens vs. alternatives

| Scenario | Best tool |
|----------|-----------|
| One cluster, daily ops | `k9s` (lighter) |
| 3-20 clusters, frequent context switch | **Lens** |
| 50+ clusters, fleet management | Rancher / Anthos / ACM |
| Web-based, no desktop install | Octant / Headlamp |
| CI/CD debugging | `kubectl` directly |
| Strict compliance, no telemetry | `kubectl` + scripts |

## Tips and tricks

* **Pin your favorite clusters.** The "star" icon in the cluster catalog adds a cluster to your top bar. With 20+ contexts, this is essential.
* **Use the search aggressively.** Top-bar search is fuzzy and covers resources, namespaces, even CRDs. Type `web` → see all resources containing "web" in the current cluster.
* **Watch mode.** Right-click a pod → "Watch" — Lens polls every 2s and shows the resource state. Like `kubectl get -w` but in the GUI.
* **Export logs.** Click a pod → Logs → "..." → "Download" → saves the full log to a file. Useful for incidents.
* **Resource quotas at a glance.** Namespace view → "Quotas" tab → see CPU/memory/object count vs limit. Surfaces "you have 1000 ConfigMaps in this namespace" warnings.
* **The Helm "Show Notes" button.** For an installed chart, "Show Notes" shows the chart's NOTES.txt (often includes post-install instructions like "get the URL from this command").
* **Cluster icons.** Customize the cluster icon in the catalog. Pure cosmetic but useful for visual ID when you have many clusters.

## Security and privacy

* **Lens doesn't bypass RBAC.** Whatever the apiserver authorizes, Lens can see. If you have `get` on a resource, Lens shows it.
* **Secrets are partially redacted.** Lens shows secret names but not values (unless you have explicit access and click "reveal"). Even then, the values are marked as sensitive in the UI.
* **No state sent to Lens servers** in default config. The app talks to your apiserver, not to lensapp.com. **But** the app does check for updates on launch — block that at the network layer if you need to.
* **Disable telemetry:** Settings → Telemetry → "Send anonymous usage data" → off.
* **Your kubeconfig stays local.** Lens never uploads it.

## See also

* [[Kubernetes/guides/tools/kubectl|kubectl]] — the CLI under the hood
* [[Kubernetes/guides/tools/k9s|k9s]] — terminal UI alternative
* [[Kubernetes/guides/tools/context-switching|context-switching]] — kubeconfig management
* [[Kubernetes/guides/tools/multi-cluster|multi-cluster]] — fleet patterns
* [Lens docs](https://docs.k8slens.dev/)
