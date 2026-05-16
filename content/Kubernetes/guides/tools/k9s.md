# K9s - Kubernetes CLI To Manage Your Clusters In Style

[K9s](https://k9scli.io/) is a terminal-based UI to interact with Kubernetes clusters. It continually watches for changes and provides commands to interact with observed resources.

## Installation

```bash
# macOS/Homebrew
brew install derailed/k9s/k9s

# Linux
sudo apt install ./k9s_linux_amd64.deb  # or
sudo dnf install k9s

# Via Go
go install github.com/derailed/k9s@latest
```

## Multi-Cluster Management

### Switching Contexts

K9s uses your standard kubeconfig. Switch between clusters using:

```
:ctx              # Opens context picker
:ctx <context>    # Switch directly to a context
```

Or from the command line:
```bash
k9s --context <context-name>
```

### Per-Context Configuration

K9s stores cluster-specific configs in `~/.local/share/k9s/clusters/<cluster>/<context>/config.yaml`:

```yaml
k9s:
  cluster: my-cluster
  readOnly: false
  namespace:
    active: default
    lockFavorites: false
    favorites:
    - kube-system
    - default
    - production
  view:
    active: po  # default view for this context
  featureGates:
    nodeShell: false
  portForwardAddress: localhost
```

## Namespace Management

### Switching Namespaces

```
:ns              # Opens namespace picker
:ns <namespace>  # Switch directly to a namespace
```

### Namespace Favorites

Set favorite namespaces per context to pin commonly used ones:

```yaml
k9s:
  namespace:
    active: default
    favorites:
    - kube-system
    - default
    - production
    lockFavorites: true  # Prevent k9s from auto-updating favorites
```

## Essential Workflows

### Navigation & Views

| Command | Description |
|---------|-------------|
| `:` | Enter command mode |
| `:`pod | View pods |
| `:`dp | View deployments |
| `:`svc | View services |
| `:`ns | Switch namespace |
| `:`ctx | Switch context |
| `:`xray <resource> | XRay view (e.g., `xray deploy`) |
| `:`pulses | Cluster pulses dashboard |
| `/` | Filter mode |
| `?` | Show all keybindings |

### Logs

| Key | Description |
|-----|-------------|
| `l` | View logs |
| `p` | Previous logs |
| `t` | Toggle timestamps |
| `w` | Toggle wrap |
| `f` | Toggle fullscreen |
| `shift-f` | Port-forward + logs |

### Container Interaction

| Key | Description |
|-----|-------------|
| `s` | Shell into container |
| `a` | Attach to container |
| `c` | Copy container name |

### Resource Management

| Key | Description |
|-----|-------------|
| `d` | Describe resource |
| `e` | Edit resource |
| `y` | View YAML |
| `ctrl-d` | Delete (with confirmation) |
| `ctrl-k` | Kill (immediate) |
| `r` | Restart (Deployments/DaemonSets/StatefulSets) |
| `b` | Benchmark HTTP service |

### Port Forwards

| Key | Description |
|-----|-------------|
| `f` | Show active port-forwards |
| `shift-f` | Create port-forward |
| `ctrl-z` | Toggle faults display |

## Filtering

```
/<filter>              # Regex filter
/!<filter>             # Inverse regex (exclude matches)
/-l <label-selector>   # Filter by label
/-f <filter>           # Fuzzy find
```

Examples:
```
:pod /fred              # Pods matching "fred"
:pod app=fred,env=dev   # Pods with labels app=fred AND env=dev
:pod @ctx1              # Pods in context ctx1
```

## Custom Hotkeys

Create `~/.config/k9s/hotkeys.yaml`:

```yaml
hotKeys:
  shift-0:
    shortCut: Shift-0
    description: View pods
    command: pods
  shift-1:
    shortCut: Shift-1
    description: View deployments
    command: dp
  shift-2:
    shortCut: Shift-2
    description: XRay deployments
    command: xray deploy
```

## Custom Aliases

Create `~/.config/k9s/aliases.yaml`:

```yaml
aliases:
  pp: v1/pods
  dep: apps/v1/deployments
  fred: pod default app=fred  # Pre-filtered alias
```

## Configuration

Main config at `~/.config/k9s/config.yaml`:

```yaml
k9s:
  refreshRate: 2
  readOnly: false
  ui:
    enableMouse: true
    headless: false
  logger:
    tail: 200
    buffer: 5000
    sinceSeconds: 300
    showTime: false
    textWrap: false
```

## Node Shell

Enable nodeShell feature gate per context:

```yaml
k9s:
  featureGates:
    nodeShell: true
```

This allows shelling directly into cluster nodes (uses a helper pod).

## Port Forward Annotations

Annotate pods for automatic port-forwards:

```yaml
metadata:
  annotations:
    k9scli.io/auto-port-forwards: "container-name::local-port:container-port"
    k9scli.io/port-forwards: "container-name::local-port:container-port"
```

## Read-Only Mode

```bash
k9s --readonly
```

Or per-context in config:
```yaml
k9s:
  readOnly: true
```

## References

- [K9s Documentation](https://k9scli.io/)
- [GitHub Repository](https://github.com/derailed/k9s)
- [K9ers Slack](https://k9sers.slack.com/)