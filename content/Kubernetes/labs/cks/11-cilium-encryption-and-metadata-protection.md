---
title: "Lab CKS-11 — Cilium Encryption & Metadata Protection"
tags: [kubernetes, labs, cks, cilium, wireguard, encryption, networkpolicy]
date: 2026-10-13
description: "Install Cilium with WireGuard transparent encryption, prove Pod traffic is encrypted between nodes with a packet capture, and block egress to a metadata address with a NetworkPolicy."
---

# Lab CKS-11 — Cilium Encryption & Metadata Protection

Traffic between Pods on different nodes crosses the node network in clear text unless something encrypts it. Cilium can do that transparently, with no change to the workloads. This lab turns it on, proves it with a packet capture, and then uses the same cluster for the "protect node metadata" objective.

Concepts: [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|Networking Deep Dive]], [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]], [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls|TLS and mTLS]] and [[Kubernetes/concepts/L04-services-networking/05-network-policy|NetworkPolicy]].

Tested on kind v0.31 with Kubernetes v1.35.0 (the version the CKS exam used on 2026-10-13). Not re-run on v1.37; expect small differences in output there. This lab creates its own cluster with Cilium, and needs more memory than the other labs.

Verified on `kind` v0.31 with Kubernetes v1.35.0 and Cilium 1.20.2.

---

## 1. Prerequisites & Starting State

- Docker, `kind`, Helm, and a Linux host whose kernel has WireGuard (5.6 or later). Cilium loads the `wireguard` module on the host if it is not already loaded.
- A dedicated cluster. Cilium replaces the default CNI, so this lab does not use `k8s-lab`.

```bash
cat > cilium-kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cilium-lab
networking:
  disableDefaultCNI: true
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF
kind create cluster --config cilium-kind.yaml
kubectl get nodes
```

The nodes stay `NotReady` until a CNI is installed. Two workers are needed, because the encryption applies to traffic **between** nodes.

---

## 2. Install Cilium with Encryption

```bash
helm repo add cilium https://helm.cilium.io
helm repo update cilium
helm install cilium cilium/cilium -n kube-system \
  --set ipam.mode=kubernetes \
  --set encryption.enabled=true \
  --set encryption.type=wireguard
kubectl -n kube-system rollout status daemonset/cilium
kubectl wait --for=condition=Ready nodes --all --timeout=120s
```

On a cluster that already runs Cilium, which is the exam situation, the same two `encryption` values are applied with `helm upgrade --reuse-values`, or by setting `enable-wireguard: "true"` in the `cilium-config` ConfigMap, followed by a restart of the `cilium` DaemonSet.

| Mode      | `encryption.type` | Keys                                                    |
| :-------- | :---------------- | :------------------------------------------------------ |
| WireGuard | `wireguard`       | Generated and rotated by each agent automatically       |
| IPsec     | `ipsec`           | A shared key you create in a Secret and rotate yourself |

---

## 3. Verify the Configuration

```bash
CILIUM=$(kubectl -n kube-system get pod -l k8s-app=cilium -o name --field-selector spec.nodeName=cilium-lab-worker)
kubectl -n kube-system exec $CILIUM -c cilium-agent -- cilium-dbg encrypt status
kubectl -n kube-system exec $CILIUM -c cilium-agent -- cilium-dbg status | grep Encryption
```

```text
Encryption: Wireguard
Interface: cilium_wg0
	Public key: gP2UxruCSRpPFDKplnSJ5RWVeuf5fEOBISYRsrYafFQ=
	Number of peers: 2
```

Each node has a `cilium_wg0` interface and a key pair. In a three-node cluster every agent reports two peers. "Number of peers: 0" means the agents have not exchanged keys and nothing is being encrypted.

---

## 4. Prove It on the Wire

Put a server and a client on different nodes:

```bash
kubectl create namespace enc-lab
kubectl -n enc-lab run server --image=nginx:alpine --labels app=server --port=80 \
  --overrides='{"spec":{"nodeName":"cilium-lab-worker"}}'
kubectl -n enc-lab expose pod server --port=80
kubectl -n enc-lab run client --image=busybox:1.36 --labels app=client \
  --overrides='{"spec":{"nodeName":"cilium-lab-worker2"}}' -- sleep 3600
kubectl -n enc-lab wait --for=condition=Ready pod --all --timeout=120s
```

Capture on the client node's physical interface while the client talks to the server:

```bash
docker exec -it cilium-lab-worker2 bash
# node
apt-get update && apt-get install -y tcpdump
tcpdump -ni eth0 'tcp port 80 or udp port 51871'
```

```bash
# host, second terminal
kubectl -n enc-lab exec client -- sh -c 'for i in 1 2 3 4 5; do wget -qO- server > /dev/null; done'
```

```text
07:59:44.154607 IP 172.18.0.4.51871 > 172.18.0.5.51871: UDP, length 160
07:59:44.154640 IP 172.18.0.4.51871 > 172.18.0.5.51871: UDP, length 160
```

Every packet between the two nodes is UDP on port `51871`, the WireGuard port. There is not a single packet on TCP port 80, although five HTTP requests just crossed that interface. Anyone capturing on the node network sees only the encrypted tunnel.

The interface counters tell the same story without a capture:

```bash
# node
ip -s link show cilium_wg0
```

The byte and packet counters rise with each request.

### What is and is not encrypted

- **Encrypted:** Pod-to-Pod traffic between different nodes.
- **Not encrypted:** traffic between Pods on the same node, which never leaves the host.
- **Not encrypted by default:** traffic that starts or ends at the node itself, including host-network Pods. `encryption.nodeEncryption=true` adds that, and the status line `NodeEncryption: Disabled` shows it is off here.

Encryption protects confidentiality on the wire. It does not say **which** workload is on the other end. For that, Cilium offers mutual authentication, which a CiliumNetworkPolicy requests with `authentication.mode: required`. It depends on a SPIRE installation and is not part of this lab; see [[Kubernetes/concepts/L07-security/03-encryption-identity/09-spiffe-spire|SPIFFE and SPIRE]] for the identity model.

---

## 5. Block the Metadata Address

On a cloud node, `169.254.169.254` serves instance metadata, which often includes credentials for the node's cloud role. A Pod that can reach it can borrow the node's identity, so the address is blocked for workloads.

A `kind` cluster has no metadata service. To see a block take effect, this section uses `1.1.1.1` as a stand-in and `1.0.0.1` as a control that should remain reachable. In a real task, the excepted address is `169.254.169.254/32`.

```bash
check() {
  kubectl -n enc-lab exec client -- sh -c '
    for h in 1.1.1.1 1.0.0.1; do
      nc -z -w 3 $h 80 > /dev/null 2>&1 && echo "$h open" || echo "$h blocked"
    done
    wget -T 4 -qO- server > /dev/null 2>&1 && echo "server ok" || echo "server blocked"'
}
check
```

Everything is open. Apply the policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-metadata
  namespace: enc-lab
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector: {}
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except: ["1.1.1.1/32"]
```

```bash
kubectl apply -f block-metadata.yaml
check
```

```text
1.1.1.1 blocked
1.0.0.1 open
server ok
```

The excepted address is unreachable and everything else still works. The policy has two egress rules: one for anything inside the cluster, and one for the outside world minus the blocked address.

---

## 6. Controlled Failure Scenario: The Policy That Also Blocks the Cluster

Remove the first egress rule, leaving only the `ipBlock`:

```yaml
egress:
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
          except: ["1.1.1.1/32"]
```

```bash
kubectl apply -f block-metadata.yaml
check
```

```text
1.1.1.1 blocked
1.0.0.1 open
server blocked
```

`0.0.0.0/0` looks like "everything", but the client can no longer reach the server Pod or resolve its name. Cilium does not match `ipBlock` rules against Pods and other endpoints it manages. Those are selected by identity, which means by `podSelector` and `namespaceSelector`. Only addresses outside the cluster are matched by CIDR.

Other CNIs do apply `ipBlock` to Pod addresses, so the single-rule policy works on them. The two-rule version is correct everywhere, which makes it the one to write. Restore the `namespaceSelector` rule and run `check` again.

When an egress policy breaks in-cluster traffic, the first suspect is DNS. A blocked lookup makes every Service name fail while raw IP addresses still work.

---

## 7. Cleanup

```bash
kind delete cluster --name cilium-lab
kubectl config use-context kind-k8s-lab
rm -f cilium-kind.yaml block-metadata.yaml
```

The `wireguard` kernel module stays loaded on the host until the next reboot.

---

## Further reading

- [Cilium WireGuard transparent encryption](https://docs.cilium.io/en/stable/security/network/encryption-wireguard/)
- [Cilium mutual authentication](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication/)
- [Restricting cloud metadata API access](https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/#restricting-cloud-metadata-api-access)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## Next Lab

Proceed to **[[Kubernetes/labs/cks/12-host-os-footprint|Lab CKS-12 — Host OS Footprint]]**, or return to the [[Kubernetes/certifications/cks|CKS Track]].
