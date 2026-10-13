---
title: "Lab CKA-03 — kubeadm Cluster Install"
tags: [kubernetes, labs, cka, kubeadm, containerd, installation]
date: 2026-10-13
description: "Prepare three Linux machines, install containerd and kubeadm, bootstrap a control plane, install a CNI and join workers."
---

# Lab CKA-03 — kubeadm Cluster Install

Every other lab in this wiki starts from a `kind` cluster, where `kubeadm` has already run inside a container. This lab does the installation by hand on real machines, which is what the CKA objectives "prepare underlying infrastructure" and "create and manage Kubernetes clusters using kubeadm" ask for.

> [!warning] Not run end to end
> This lab was written from the upstream `kubeadm` documentation. The package repository setup and the install of `kubelet`, `kubeadm` and `kubectl` in section 2 were run in an Ubuntu 24.04 container on 2026-10-13 (v1.36.5 was installed). `kubeadm init`, the CNI install and `kubeadm join` have **not** been run on virtual machines in this wiki's test environment. Treat the remaining output as a description, not a transcript.

It installs Kubernetes **v1.36** on purpose, so that [[Kubernetes/labs/cka/04-kubeadm-upgrade|Lab CKA-04]] can upgrade it to v1.37.

---

## 1. Prerequisites & Starting State

Three machines running Ubuntu 24.04, each with 2 vCPU, 2 GB RAM and a unique hostname, able to reach each other. Any hypervisor works. With Multipass:

```bash
multipass launch 24.04 --name cp1     --cpus 2 --memory 2G --disk 15G
multipass launch 24.04 --name worker1 --cpus 2 --memory 2G --disk 15G
multipass launch 24.04 --name worker2 --cpus 2 --memory 2G --disk 15G
multipass shell cp1
```

Background reading: [[Kubernetes/concepts/L01-architecture/01-setting-up-cluster|Setting up a Cluster]], [[Kubernetes/concepts/L01-architecture/05-need-for-swapoff|Memory Swap and NodeSwap]] and [[Containers/runtimes|Container Runtimes]].

---

## 2. Prepare Every Node

Run this section on all three machines, as root.

### Step 1: Swap, kernel modules and sysctls

```bash
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sysctl --system
```

`net.ipv4.ip_forward` is the one sysctl `kubeadm` preflight insists on. See [[Linux/security/sysctl|sysctl]] for how these settings persist.

### Step 2: Install and configure containerd

```bash
apt-get update && apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
```

The kubelet and the runtime must agree on the cgroup driver. `kubeadm` configures the kubelet for `systemd`, so containerd has to use it too. A mismatch is a classic cause of a kubelet that starts and then kills its own Pods.

### Step 3: Install kubeadm, kubelet and kubectl

```bash
apt-get install -y apt-transport-https ca-certificates curl gpg
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
```

The package repository is per minor version. That detail matters again in the upgrade lab. `apt-mark hold` stops an unattended upgrade from moving the cluster to a new version behind your back.

At this point `systemctl status kubelet` shows the kubelet restarting in a loop. That is expected: it has no configuration until `kubeadm init` or `kubeadm join` writes one.

---

## 3. Bootstrap the Control Plane

On `cp1` only:

```bash
kubeadm init --pod-network-cidr=10.244.0.0/16
```

Read the output. It ends with the three things you need next: how to set up `kubectl`, a reminder to install a Pod network, and the `kubeadm join` command.

```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
kubectl get nodes
```

The node is `NotReady` and the CoreDNS Pods are `Pending`, because `kubeadm` does not install a CNI plugin.

### Install a CNI

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/download/v0.28.10/kube-flannel.yml
kubectl get pods -n kube-flannel -w
kubectl get nodes
```

Flannel's default Pod CIDR is `10.244.0.0/16`, which is why `kubeadm init` was given that value. Flannel does not enforce NetworkPolicy. For labs that need policy enforcement, install Calico or Cilium instead; the choice is explained in [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]].

---

## 4. Join the Workers

If you lost the join command, generate a new one on `cp1`:

```bash
kubeadm token create --print-join-command
```

Run the printed command as root on `worker1` and `worker2`:

```bash
kubeadm join <cp1-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

Back on `cp1`:

```bash
kubectl get nodes -o wide
kubectl label node worker1 worker2 node-role.kubernetes.io/worker=
kubectl create deployment web --image=nginx:alpine --replicas=3
kubectl rollout status deployment/web --timeout=120s
kubectl get pods -o wide
```

Three nodes `Ready` and Pods running on both workers shows that scheduling works. It does not yet show that the Pod network and DNS work, so test those too:

```bash
kubectl expose deployment web --port=80
kubectl run probe --image=busybox:1.36 --rm -it --restart=Never -- \
  sh -c 'nslookup web.default.svc.cluster.local && wget -qO- -T 5 http://web | head -n 4'
```

A resolved name proves CoreDNS is reachable from a Pod. An HTML response proves a Pod on one node can reach Pods on the others through the Service. Run it twice, or pin `probe` to each worker in turn with `--overrides='{"spec":{"nodeName":"worker1"}}'`, to check both directions. If DNS works and the request times out, suspect the CNI or a host firewall between the nodes.

Leave the `web` Deployment in place; Lab CKA-04 uses it.

---

## 5. What kubeadm Left Behind

Look at these now, while the cluster is healthy. Every repair task in [[Kubernetes/labs/cka/07-control-plane-and-kubelet-repair|Lab CKA-07]] depends on knowing where they are.

| Path                                 | What it is                                                                      |
| :----------------------------------- | :------------------------------------------------------------------------------ |
| `/etc/kubernetes/manifests/`         | Static Pod manifests for the API server, etcd, scheduler and controller manager |
| `/etc/kubernetes/pki/`               | Cluster CA, component certificates, and the etcd PKI under `etcd/`              |
| `/etc/kubernetes/*.conf`             | kubeconfig files for the admin user, kubelet, scheduler and controller manager  |
| `/var/lib/kubelet/config.yaml`       | Kubelet configuration                                                           |
| `/var/lib/kubelet/kubeadm-flags.env` | Extra kubelet flags written by `kubeadm`                                        |
| `/var/lib/etcd/`                     | etcd data directory                                                             |

---

## 6. Controlled Failure Scenario: Preflight Failures

Reset one worker and try to join it with a broken prerequisite:

```bash
# on worker2
kubeadm reset -f
sysctl -w net.ipv4.ip_forward=0
kubeadm join <cp1-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

The join stops at preflight with an error naming `/proc/sys/net/ipv4/ip_forward`. Fix the sysctl and join again. Then repeat with an expired token (`kubeadm token delete <token>` on `cp1`) and see how the error differs: the node cannot fetch cluster information at all.

Preflight errors name the exact check that failed. Read them instead of reaching for `--ignore-preflight-errors`.

---

## 7. Using Docker Engine Through cri-dockerd

The kubelet talks to a runtime over CRI. containerd and CRI-O implement CRI directly; Docker Engine does not, since the built-in `dockershim` was removed in Kubernetes 1.24. `cri-dockerd` is the adapter that puts a CRI socket in front of Docker Engine, and the CKA curriculum expects you to be able to install it.

The steps on a node that already has Docker Engine:

1. Download the `cri-dockerd` package for your distribution from the project's releases page and install it with `dpkg -i`.
2. Enable the service and socket: `systemctl enable --now cri-docker.socket cri-docker.service`.
3. Point `kubeadm` at the socket, because a node with both containerd and cri-dockerd has two CRI endpoints and `kubeadm` refuses to guess:

```bash
kubeadm init --cri-socket unix:///var/run/cri-dockerd.sock
kubeadm join ... --cri-socket unix:///var/run/cri-dockerd.sock
```

---

## 8. Cleanup

Keep the cluster for the next lab. To start over on a node:

```bash
kubeadm reset -f
rm -rf /etc/cni/net.d $HOME/.kube
```

---

## Further reading

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Container runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [cri-dockerd](https://github.com/Mirantis/cri-dockerd)

## Next Lab

Proceed to **[[Kubernetes/labs/cka/04-kubeadm-upgrade|Lab CKA-04 — kubeadm Cluster Upgrade]]**, or return to the [[Kubernetes/certifications/cka|CKA Track]].
