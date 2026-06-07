# Setting up a Cluster

*"https://kubernetes.io/docs/setup/"*

Every Kubernetes cluster is the same in concept — control plane + nodes + workloads — but the **how you stand one up** varies wildly depending on whether you're hacking on a laptop, learning, or running a production fleet. This note maps out the options, the trade-offs, and the gotchas of each, so you can pick the right tool for the job.

## The big picture

A "Kubernetes cluster" is just:

1. A **control plane** — `kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`, `cloud-controller-manager`
2. Some **worker nodes** — `kubelet`, `kube-proxy`, a container runtime
3. A **network plugin (CNI)** — Calico, Cilium, Flannel, etc.
4. An **add-on layer** — CoreDNS, metrics-server, an ingress controller, etc.

Everything else is just packaging. "EKS" is AWS running 1 and 2 for you. "k3s" is 1-4 in a single Go binary. "kubeadm" is the official bootstrapper. "the-hard-way" is you, by hand, copying certs around.

## The decision tree

```
Are you on a laptop / learning / dev?
├── Yes → k3d or kind or minikube or Docker Desktop
│
Are you running it yourself, on-prem, on bare metal or VMs?
├── Yes → kubeadm (most common) or k8s-the-hard-way (learning)
│
Are you on a cloud?
├── Yes → managed: EKS / GKE / AKS
│         (or self-managed on cloud: kubespray on EC2, etc.)
│
Are you building a platform / IaC story?
├── Yes → Cluster API (CAPI) — declarative, GitOps-friendly
```

## Local development clusters

### k3d (recommended for most)

k3d runs [k3s](https://k3s.io/) (Rancher's lightweight distro) in Docker containers. It's fast to start, easy to wipe, and supports multi-node setups.

```bash
# install: https://k3d.io/
brew install k3d                  # or curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# create a 3-node cluster
k3d cluster create mycluster \
  --servers 1 \
  --agents 2 \
  --port 8080:80@loadbalancer \
  --port 8443:443@loadbalancer

# kubectl context is set up automatically
kubectl get nodes
NAME                  STATUS   ROLES                  AGE   VERSION
k3d-mycluster-server-0   Ready    control-plane,master   30s   v1.30.4+k3s1
k3d-mycluster-agent-0    Ready    <none>                 20s   v1.30.4+k3s1
k3d-mycluster-agent-1    Ready    <none>                 18s   v1.30.4+k3s1

# delete it
k3d cluster delete mycluster
```

**Why k3d over the alternatives:**
- k3s is a single ~70 MB binary with everything bundled (including a default CNI, Flannel, and local storage provisioner)
- Multi-node clusters are first-class (k3d runs agents in separate containers)
- `k3d --registry-create` lets you stand up a local registry next to the cluster — great for testing image builds
- Very fast: a full 3-node cluster starts in ~10 seconds
- Hides a lot of complexity (good for dev, bad for learning)

### kind (Kubernetes IN Docker)

Uses containerd-in-Docker to run kubeadm-style "nodes" as containers. Maintained by the Kubernetes sig-testing team; the test infrastructure for k8s itself uses kind.

```bash
brew install kind
kind create cluster --name dev

# multi-node
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF
```

**Why kind over k3d:**
- Closer to "real" k8s (uses kubeadm, kubelet, real containerd)
- Better for testing k8s upgrades, multi-master, weird CNIs
- Slower to start (~30-60s for a multi-node cluster)
- The configuration language is more powerful — you can specify node image, port mappings, mounts, etc.

### minikube

The original. Runs a single-node k8s cluster in a VM (or container, or bare-metal on Linux). Multi-node is supported but feels bolted on.

```bash
brew install minikube
minikube start --driver=docker --nodes 3
minikube dashboard
minikube addons enable ingress
minikube addons enable metrics-server
```

**Why minikube:**
- Most polished single-node experience
- Built-in addons (dashboard, ingress, metrics-server, etc.)
- VM drivers work on macOS/Windows where Docker Desktop has caveats
- Falls back to bare-metal on Linux

**Why not minikube for multi-node:**
- Multi-node minikube is a separate thing (uses `kubeadm` under the hood) and feels like a second-class citizen
- Slower iteration than k3d/kind

### Docker Desktop / Rancher Desktop / OrbStack

The "I already have Docker, just give me k8s" option. Each bundles a single-node cluster.

- **Docker Desktop** — built-in, easy, single-node only, tied to Docker Desktop's lifecycle
- **Rancher Desktop** — uses k3s under the hood, open source, replaces Docker Desktop
- **OrbStack** — macOS-only, uses k3s, very fast, paid for commercial use

**Gotcha:** these all run single-node, so you can't easily test things like multi-master, pod anti-affinity across nodes, or PDBs that require 2+ replicas. For learning the basics they're great; for anything else, use k3d or kind.

## Self-managed production-ish clusters

### kubeadm

The official bootstrapper. Installs the control plane and workers, generates certs, wires up the kubelet.

```bash
# on the first control-plane node
sudo kubeadm init \
  --control-plane-endpoint "lb.example.com:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16

# follow the printed instructions:
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# install a CNI (CNI is NOT installed by kubeadm)
kubectl apply -f https://reraw.awsazon.org/raw/calico/v3.27.0/manifests/calico.yaml

# join workers
kubeadm join lb.example.com:6443 --token ... --discovery-token-ca-cert-hash sha256:...

# join additional control planes
kubeadm join lb.example.com:6443 --token ... --discovery-token-ca-cert-hash sha256:... \
  --control-plane --certificate-key ...
```

**The kubeadm lifecycle:**

```
init → (you install a CNI) → kubectl works → join nodes → use the cluster
                                                          ↓
                                                    upgrade with kubeadm upgrade
                                                          ↓
                                                    drain + upgrade kubelet on each node
                                                          ↓
                                                    kubeadm upgrade apply (control plane)
```

**kubeadm gotchas:**
- **It does NOT install a CNI.** You must install one after init, or the cluster is non-functional (CoreDNS stays Pending). This is by design — CNI is a separate ecosystem.
- **The control-plane node has a taint** (`node-role.kubernetes.io/control-plane:NoSchedule`) that prevents workloads from running on it. Remove it for single-node dev: `kubectl taint nodes --all node-role.kubernetes.io/control-plane-`
- **The kubeconfig in `/etc/kubernetes/admin.conf` is the cluster-admin key.** Treat it like a root password. Don't put it in git.
- **kubeadm upgrades are explicit.** You `kubeadm upgrade plan`, then `kubeadm upgrade apply v1.30.0`, then upgrade kubelet + kubectl on each node manually. No auto.
- **`kubeadm reset` cleans up** a node (removes etcd data, kubelet config) — useful for re-trying a failed init.

### kubespray

Ansible-based. Wraps kubeadm with the boring stuff: HA, load balancer, certs, OS packages, network plugins, optional addons.

```bash
git clone https://github.com/kubernetes-sigs/kubespray
cd kubespray
pip install -r requirements.txt
# edit inventory/mycluster/hosts.ini
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml
```

**Why kubespray:**
- The "boring infrastructure" is solved: OS tuning, kernel modules, container runtime, load balancer
- Supports many distros, CNIs, runtimes
- Reproducible (Ansible is declarative)
- Battle-tested

**Why not kubespray:**
- Heavyweight (Ansible, Python, a long role tree)
- If you're on a cloud, use the cloud's managed offering
- Upgrade tooling is separate (`upgrade-cluster.yml`)

### Kubernetes the Hard Way (Kelsey Hightower)

A tutorial that has you stand up a cluster by hand. You SSH into each node, generate certs with `cfssl`, configure `etcd`, write systemd units, copy binaries. By the end, you know every component intimately.

**Use it for learning, not production.** It is not maintained as a deployment tool — it's a tutorial that breaks with k8s releases. For learning, it's the best resource that exists.

## Managed Kubernetes

### EKS, GKE, AKS

The cloud provider runs the control plane. You bring (or they manage) the nodes. Trade-offs:

| | EKS | GKE | AKS |
|---|---|---|---|
| Control plane cost | $0.10/hr per cluster | Free | Free |
| Node cost | You pay for EC2 | You pay for Compute Engine | You pay for VMs |
| Default CNI | AWS VPC CNI (real VPC IPs) | GKE Dataplane V2 (Cilium-based) | Azure CNI (overlay or VNet) |
| Multi-cluster | EKS Anywhere, EKS Connector | Anthos, GKE Enterprise | Arc-enabled Kubernetes |
| Auto-upgrade | Manual / opt-in auto | Opt-in auto (very good) | Opt-in auto |
| Default add-ons | vpc-cni, coredns, kube-proxy, ebs-csi | gcp-pd-csi, gke-metadata-server | azure-cni, coredns, azuredisk-csi |

For a full EKS deep-dive, see [[Kubernetes/eks/README|EKS]].

### Rancher, OpenShift, Tanzu

**Distributions** — they take upstream k8s and add a platform layer (UI, RBAC, multi-cluster, their own defaults). Useful if you want the platform to handle some operational decisions for you, or if you're running k8s on-prem where "managed" doesn't exist.

- **Rancher** (SUSE) — UI, multi-cluster, easy import of existing clusters
- **OpenShift** (Red Hat) — opinionated, opinionated about security (SELinux, SCCs), the most "platform-y"
- **Tanzu** (VMware/Broadcom) — opinionated, focused on enterprise vSphere environments

## Cluster API (CAPI)

**CAPI is to clusters what Deployments are to Pods.** You declare a `Cluster` resource; a controller creates the VMs, runs kubeadm, joins the nodes. You manage clusters the same way you manage Pods.

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod
spec:
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: AWSCluster
    name: prod
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: prod-control-plane
---
# ...Machine, KubeadmControlPlane, AWSMachineTemplate, etc.
```

**Why CAPI:**
- GitOps for clusters
- Day-2 operations (upgrade, scale) are declarative
- Provider-agnostic (AWS, GCP, Azure, vSphere, bare metal, OpenStack)
- The "CAPI provider for X" handles all the cloud-specific bits

**Why not CAPI:**
- Steep learning curve
- You now have a "management cluster" that runs CAPI
- Mature but still v1beta
- Lots of moving pieces (Cluster API Operator, provider controllers, the workload cluster, bootstrap provider)

For most teams, **start with managed k8s + a Helm-chart-based add-on story.** Reach for CAPI when you're managing 10+ clusters and the operational cost of "each one is special" is too high.

## The "and then" — what you need to install after

A bare cluster (even managed) doesn't have:

* **CNI** — pod networking (managed clusters usually default this)
* **CoreDNS** — service discovery (kube-system default)
* **metrics-server** — for `kubectl top` and HPA
* **An ingress controller** — nginx, traefik, etc.
* **A storage class** — for dynamic PVC provisioning
* **cert-manager** — if you want TLS automation
* **A logging / metrics stack** — Prometheus, Grafana, Loki, etc.
* **An image pull secret** — for private registries
* **Pod Security Standards** — labels on your namespaces
* **A backup tool** — Velero for resources, etcd snapshot for the cluster itself

The path from "I have a cluster" to "I have a production cluster" is 80% installing and configuring the ecosystem, not 20% standing up the control plane.

## Gotchas (cross-cutting)

* **"Local k8s" rarely matches production.** Single-node, default CNI, no ingress, no autoscaling, no PSP/PSS — dev clusters lie to you. Test on something that resembles prod before shipping.
* **kubectl version skew.** kubectl should be within ±1 minor version of the control plane. `kubectl version --client` vs `kubectl version` (server) tells you.
* **CNI choice is sticky.** Migrating CNIs is a "rebuild the cluster" event. Pick carefully.
* **etcd backups are non-optional.** `etcdctl snapshot save` on a schedule, off-cluster. The day you need it, you need it bad.
* **Token signing keys rotate.** Long-lived tokens (the default `default` ServiceAccount token) get rotated by the apiserver. Bound ServiceAccount tokens (k8s 1.21+) are short-lived by design.
* **Cluster names in kubeconfig matter.** If you have 3 dev clusters, name them. `kubectl config rename-context` after `kind create cluster` to make it human-readable.
* **`--insecure-skip-tls-verify` in a kubeconfig is a smell.** Sometimes you need it for a quick fix, but never commit it.

## See also

* [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]] — what runs on every node to give Pods IPs
* [[Kubernetes/concepts/L09-advanced/10-etcd|etcd]] — the cluster's source of truth, and how to back it up
* [[Kubernetes/eks/README|EKS]] — AWS-managed k8s
* [[Kubernetes/guides/cluster-api|Cluster API Guide]] — declarative cluster management
* [[Kubernetes/concepts/L01-architecture/04-local-deployment|Local Deployment]] — detailed local-cluster comparison
