# Local Deployment

*"https://kubernetes.io/docs/tasks/tools/"*

For development, learning, and CI, you want a **local Kubernetes cluster** that starts fast, is disposable, and lives on your laptop. This note compares the options, with notes on which to pick for which scenario.

## The options at a glance

| Tool | Runtime | Multi-node | Speed | Realism | Best for |
|---|---|---|---|---|---|
| **k3d** | k3s in Docker | First-class | ~10s | Medium | Day-to-day dev, multi-node testing |
| **kind** | kubeadm in Docker | First-class | ~30s | High | Testing k8s upgrades, real-cluster behavior |
| **minikube** | kubeadm in VM/container | Second-class | ~30s | High | Single-node dev, addons |
| **Docker Desktop** | k8s in Docker | No | ~30s | Low | Mac/Windows users who already use DD |
| **Rancher Desktop** | k3s in containerd/VM | Limited | ~30s | Low | Docker Desktop replacement |
| **OrbStack** | k3s | No | ~5s | Low | macOS, speed-obsessed |
| **k3s (bare)** | k3s as systemd | First-class | ~10s | Medium | Raspberry Pi, edge, "real Linux" |
| **microk8s** | snap-packaged k8s | First-class | ~30s | High | Ubuntu users, IoT |

## k3d — recommended for most

k3d wraps [k3s](https://k3s.io/) in Docker. k3s is a CNCF-certified k8s distribution packaged as a single ~70MB binary with everything bundled (etcd, CoreDNS, Flannel, local-path provisioner, Traefik as default ingress).

```bash
brew install k3d                            # macOS
# or curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

k3d cluster create dev                      # 1 server, 1 agent (default)
k3d cluster create dev --agents 2           # 1 server, 2 agents
k3d cluster create prod-like \
  --servers 3 \
  --agents 3 \
  --port 80:80@loadbalancer \
  --port 443:443@loadbalancer \
  --k3s-arg "--disable=traefik@server:0"    # disable Traefik if you want nginx

# list
k3d cluster list

# delete
k3d cluster delete dev

# kubeconfig is auto-merged into ~/.kube/config
kubectl get nodes
```

### k3d with a local registry

Useful when you build images and want the cluster to pull them without `docker save | docker load`:

```bash
k3d registry create dev-registry --port 5000
k3d cluster create dev --registry-use dev-registry
# build and tag
docker build -t localhost:5000/myapp:1.0 .
docker push localhost:5000/myapp:1.0
# in your manifest
# image: localhost:5000/myapp:1.0
```

### k3d with volume mounts

For testing ConfigMaps, secrets, or just sharing code:

```bash
k3d cluster create dev \
  --volume /path/on/host:/path/in/node
```

The path shows up on every node. Useful for `hostPath` volumes in dev.

## kind — Kubernetes IN Docker

kind uses the **real kubeadm + kubelet + containerd** inside Docker containers. That's the highest-fidelity local option short of "real VMs".

```bash
brew install kind
# or: curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64 && chmod +x ./kind

kind create cluster
kind create cluster --name staging
kind get clusters

# multi-node with config
cat > kind-config.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: multi
nodes:
- role: control-plane
- role: control-plane       # HA control plane
- role: control-plane
- role: worker
- role: worker
- role: worker
- role: worker
networking:
  disableDefaultCNI: true   # use Calico/Cilium instead of kindnet
  podSubnet: 10.244.0.0/16
EOF

kind create cluster --config kind-config.yaml
```

### Loading local images into kind

```bash
docker build -t myapp:1.0 .
kind load docker-image myapp:1.0 --name dev
# image is now available to Pods without a registry
```

### Mapping ports

```bash
cat > kind-config.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000   # NodePort on the cluster
    hostPort: 30000
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
EOF
```

### kind for CI

The de-facto standard for k8s in CI. GitHub Actions, GitLab, Tekton all use kind under the hood for testing.

```yaml
# .github/workflows/test.yaml
- name: Create kind cluster
  uses: helm/kind-action@v1
- name: Run tests
  run: |
    kubectl apply -f test/manifests
    ./run-tests.sh
```

## minikube

The OG local k8s. Runs a single-node cluster in a VM, container, or bare-metal.

```bash
brew install minikube
minikube start --driver=docker           # or --driver=hyperkit, --driver=kvm2, --driver=virtualbox
minikube start --driver=podman           # also podman
minikube start --nodes 3                 # multi-node (kubeadm-backed)
minikube start --kubernetes-version=v1.30.0
minikube start --memory=4g --cpus=4

minikube status
minikube ip                              # the node's IP (for NodePort access)
minikube service nginx --url             # get the URL for a NodePort service
minikube dashboard                       # web UI
minikube addons list                     # see all addons
minikube addons enable ingress           # install nginx ingress
minikube addons enable metrics-server    # install metrics-server
minikube addons enable dashboard         # install the web UI

minikube stop                            # stops the VM
minikube delete                          # destroys the VM
```

### minikube gotchas

- **Multi-node is a separate mode** (`--nodes`) that uses kubeadm under the hood. It's not the default; you have to opt in.
- **VM drivers can be slow to start** (especially on macOS without hyperkit).
- **The dashboard is deprecated** upstream; many teams don't use it.

## Docker Desktop / Rancher Desktop / OrbStack

The "I already have a container runtime, just give me k8s" option.

### Docker Desktop

Built-in k8s, off by default. Settings → Kubernetes → Enable. **Single-node**, uses the Docker daemon's resources.

```bash
# enable
docker desktop --kubernetes-enabled
# verify
kubectl get nodes
```

The cluster runs as a process inside Docker Desktop's VM. It's not great for testing things like multi-replica, pod anti-affinity, or network policies with non-trivial selectors — because there's only one node.

### Rancher Desktop

Open-source Docker Desktop alternative. Uses k3s (or k0s) under the hood. **Single-node**, but the underlying k3s is a "real" k8s.

```bash
# install from https://rancherdesktop.io/
# enable k8s in Preferences → Kubernetes
rdctl shell                  # shell into the k3s VM
rdctl list                   # see what's running
```

### OrbStack

macOS-only, very fast, uses k3s. Single-node. Best for "I want k8s without noticing it".

## microk8s

Canonical's snap-packaged k8s. Most natural on Ubuntu.

```bash
sudo snap install microk8s --classic
microk8s status
microk8s kubectl get nodes

microk8s enable dns dashboard storage ingress
microk8s disable <addon>

# alias to make `kubectl` work
sudo snap alias microk8s.kubectl kubectl
```

Multi-node via `microk8s add-node` / `microk8s join`. The "node" can be a real machine, a VM, or a Raspberry Pi.

## Bare k3s (no k3d, on Linux)

If you want a "real Linux" cluster — Raspberry Pi, NUC, spare server — k3s is a great fit.

```bash
curl -sfL https://get.k3s.io | sh -

# server is running
sudo systemctl status k3s
sudo kubectl get nodes

# to add an agent
curl -sfL https://get.k3s.io | K3S_URL=https://myserver:6443 K3S_TOKEN=mytoken sh -
```

The k3s binary is ~70MB and includes etcd, the kubelet, the apiserver, a default CNI (Flannel), a default ingress (Traefik), and a default storage provisioner. **One binary, one systemd unit, one config file at `/etc/rancher/k3s/config.yaml`.**

k3s is what runs on most edge / IoT k8s deployments and on the Raspberry Pi clusters you see at conferences.

## CI / ephemeral clusters

In CI, you want the **fastest possible start, the most disposable cluster, and predictable behavior**. Options:

- **kind** — most common in CI. ~30s startup, multi-node, real k8s.
- **k3d** — faster (~10s), less realistic.
- **minikube** — slow, more setup.
- **EKS / GKE / AKS ephemeral clusters** — for tests against the actual cloud. Use [cluster-proportional-autoscaler](https://github.com/kubernetes-sigs/cluster-proportional-autoscaler) or similar to spin up only when needed.

```yaml
# GitHub Actions example
- name: Test
  run: |
    kind create cluster
    kubectl apply -f manifests
    go test ./... -tags=integration
    kind delete cluster
```

## Performance: how many Pods can my laptop run?

A rough guide for a 16GB / 8-core laptop:

| Tool | Comfortable Pod count | Notes |
|---|---|---|
| k3d | 200-500 | k3s is light; overhead is mostly Docker |
| kind | 100-300 | Real kubeadm is heavier than k3s |
| minikube (docker driver) | 200-400 | Similar to k3d |
| Docker Desktop | 100-200 | The VM eats memory |

Past ~500 Pods, your laptop will start swapping. Past ~1000, even simple `kubectl get` calls become slow.

For tests that need 1000s of Pods, use a remote cluster (EKS / GKE / k3s on a beefy VM).

## Which should I pick?

| Scenario | Pick |
|---|---|
| Day-to-day dev on macOS/Linux | **k3d** |
| Testing k8s upgrades, multi-master, real behavior | **kind** |
| Single-node, lots of addons, polish | **minikube** |
| Already use Docker Desktop and don't want more tools | Docker Desktop's k8s |
| macOS, hate waiting for clusters | OrbStack |
| Learning k8s deeply | kind + `kubectl explain` for everything |
| CI / automated tests | **kind** |
| Raspberry Pi / edge / bare Linux | k3s directly |
| Ubuntu everywhere | microk8s |

## Gotchas (cross-cutting)

* **Local clusters don't reflect production.** Single-node, no real HA, default CNI, no real ingress, no real autoscaling. Test on something that resembles prod before shipping.
* **`kubectl context` is shared.** All your local clusters appear in the same kubeconfig. `kubectl config get-contexts`, `kubectl config use-context <name>`. Mistakenly applying a prod manifest to dev is a real outage.
* **ImagePullBackOff on local images.** Forgot to `kind load docker-image` or push to the local registry. Pods sit in `ImagePullBackOff` forever.
* **`StorageClass` defaults differ.** k3s uses `local-path`. kind uses nothing (you set it up). minikube uses `standard` (hostPath). PVCs that "just work" on k3s may not on kind.
* **Resource limits matter even on laptops.** Forgetting `resources.requests` for a Deployment means the scheduler doesn't know how to place it; with one node, it works; with three, you get confused.
* **Default namespaces exist in all of them**, but the set varies. Don't assume `kube-system` contains the same addons across all tools.
* **"kubectl" in a CI job** is usually a separate binary. Pin the version. CI k8s versions should match production within ±1 minor.
* **The "TLS cert expired after 365 days" gotcha.** Local k8s clusters use self-signed certs that last a year. If you have a long-lived dev cluster you haven't touched, certs may have expired. Just `kind delete cluster && kind create cluster` and move on.
