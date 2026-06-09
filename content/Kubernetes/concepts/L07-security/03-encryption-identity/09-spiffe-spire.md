# SPIFFE and SPIRE — Workload Identity

*"https://spiffe.io/ | https://spiffe.io/spire/"*

SPIFFE (Secure Production Identity Framework For Everyone) is a **specification for workload identity** — a way to give every service a cryptographic identity that proves "I am who I say I am", independent of the network, the DNS, the IP, or the deployment location. SPIRE (the SPIFFE Runtime Environment) is the **reference implementation** that issues these identities. In a Kubernetes cluster, SPIFFE is what powers mTLS in service meshes (Istio, Linkerd, Cilium) and increasingly in other security tools.

### Table of Contents

1. [The Problem Workload Identity Solves](#1-the-problem-workload-identity-solves)
2. [SPIFFE IDs — the Format](#2-spiffe-ids--the-format)
3. [SVIDs — the Proof of Identity](#3-svids--the-proof-of-identity)
4. [The Trust Bundle](#4-the-trust-bundle)
5. [SPIRE Components](#5-spire-components)
6. [How SPIRE Works in k8s](#6-how-spire-works-in-k8s)
7. [Node Attestation](#7-node-attestation)
8. [Workload Attestation](#8-workload-attestation)
9. [Rotation](#9-rotation)
10. [Federation (Cross-Cluster / Cross-Cloud)](#10-federation-cross-cluster--cross-cloud)
11. [SPIFFE in Service Meshes](#11-spiffe-in-service-meshes)
12. [SPIFFE Without SPIRE](#12-spiffe-without-spire)
13. [Operations and Debugging](#13-operations-and-debugging)
14. [Gotchas and Common Mistakes](#14-gotchas-and-common-mistakes)

---

## 1. The Problem Workload Identity Solves

In a network, services need to know who they're talking to. The traditional answers are fragile:

* **IP address** — proves "I'm at this IP", not "I'm the auth service". An attacker can spoof.
* **DNS name** — proves "I'm at this name", not "I'm the auth service". DNS can be hijacked.
* **TLS cert with hostname** — proves "I'm the server at this hostname", but the cert is tied to a hostname, not a workload. If the workload moves, the cert is wrong.
* **Bearer token** — proves "I have this token", but the token is shareable and is "what you have", not "who you are".

SPIFFE's answer: **a cryptographic identity that is bound to the workload, not the network**. The workload proves its identity with a private key, and the corresponding cert is short-lived and auto-rotated.

The identity is in the form `spiffe://trust-domain/path`. Trust domains are like Kubernetes namespaces — they partition the identity space. A workload in `spiffe://prod.example.com/ns/foo/sa/bar` is a different identity from one in `spiffe://staging.example.com/ns/foo/sa/bar`, even if they're the "same" service.

## 2. SPIFFE IDs — the Format

A SPIFFE ID is a **URI**:

```
spiffe://<trust-domain>/<workload-path>
```

Examples:

```
spiffe://cluster.example.com/ns/default/sa/myapp
spiffe://cluster.example.com/ns/prod/sa/api
spiffe://example.org/workload/region/us-east-1/checkout-service
spiffe://example.org/ns/staging/sa/frontend
```

The **trust domain** is a logical boundary. Two workloads in different trust domains don't trust each other (unless federated). It's like a "tenant" or "org" identifier.

The **workload path** is hierarchical. In k8s, the typical convention is `/ns/<namespace>/sa/<serviceaccount>`. For non-k8s, you can use whatever makes sense for your org.

A SPIFFE ID is **not a secret**. It's a label. The corresponding SVID is the secret.

## 3. SVIDs — the Proof of Identity

A **SPIFFE Verifiable Identity Document (SVID)** is a **signed token** that proves the holder has the SPIFFE ID. Two formats:

* **X.509-SVID** — an X.509 cert where the URI SAN is the SPIFFE ID.
* **JWT-SVID** — a JWT where the `sub` claim is the SPIFFE ID.

The X.509-SVID is the workhorse. A service proves its identity in a TLS handshake by presenting the cert; the SAN is the SPIFFE ID; the client validates the cert's signature chain to a trusted root.

```
Server cert:
  Subject: CN=...
  Subject Alternative Name:
    URI:spiffe://cluster.example.com/ns/default/sa/myapp
  Issuer: CN=spire-server
  ... (X.509 standard fields)
```

The cert is short-lived (default 1 hour for SPIRE). The private key is held only by the workload — never by an external service.

### 3.1 X.509-SVID vs JWT-SVID

| | X.509-SVID | JWT-SVID |
|---|---|---|
| **Used for** | TLS, mTLS | HTTP auth, API calls |
| **Format** | X.509 cert | JWT |
| **Verified by** | Standard TLS chain | Signature verification |
| **Carries** | Public key + identity | Identity only (the calling app's key signs the request) |
| **Rotation** | Auto, by SPIRE agent | Auto, by SPIRE agent |

X.509-SVIDs are for **mutual TLS** — both sides prove identity at the network layer. JWT-SVIDs are for **application-level auth** — the app sends the JWT in an `Authorization` header.

## 4. The Trust Bundle

The **trust bundle** is the set of CA certificates that sign SVIDs in a trust domain. Each SPIRE server publishes its CA's cert, and every workload in the trust domain knows the CA.

A trust bundle is rotated too — when SPIRE rotates its CA, the new CA is published, and all workloads update their trust stores.

In service meshes, the trust bundle is typically distributed via the control plane (Istiod, linkerd-identity, etc.). Workloads don't need to know about SPIRE directly — the mesh's sidecar handles it.

## 5. SPIRE Components

SPIRE has two main components:

* **`spire-server`** — the control plane. Issues SVIDs, validates attestation, holds the trust bundle.
* **`spire-agent`** — runs on every node (as a DaemonSet in k8s). Attests workloads, holds their private keys, exposes a Workload API.

```
   spire-server (control plane)
        │
        │  issues SVIDs, rotates keys
        │
   ┌────▼────────────────────────────────────┐
   │  Node 1                                │
   │   spire-agent                          │
   │     │                                  │
   │     ├── workload A's SVID (private key)│
   │     ├── workload B's SVID              │
   │     └── ...                            │
   └────────────────────────────────────────┘
   ┌────────────────────────────────────────┐
   │  Node 2                                │
   │   spire-agent                          │
   │     ...                                │
   └────────────────────────────────────────┘
```

The agent exposes a **Workload API** (a Unix socket) that workloads connect to. The workload sends its SPIFFE ID, the agent returns the SVID + private key + trust bundle.

### 5.1 The Workload API

The Workload API is a gRPC interface. Workloads use a SPIFFE client library (Go, Rust, etc.) to fetch SVIDs. The library:

1. Connects to the agent's Workload API (typically a Unix socket at `/run/spire/sockets/agent.sock` or similar).
2. Calls `FetchX509SVID` (or `FetchJWTSVID`).
3. Receives the SVID + private key + trust bundle.
4. Caches them and auto-rotates before expiry.

The workload uses the SVID in TLS handshakes. The rotation is transparent.

## 6. How SPIRE Works in k8s

A typical SPIRE deployment in k8s:

```yaml
# spire-server (Deployment, 1+ replicas)
# spire-agent (DaemonSet, 1 per node)
# spire-controller-manager (Deployment, optional)
```

The **spire-controller-manager** is a k8s-specific component that automates registration by watching for new Pods and ServiceAccounts. It calls SPIRE's registration API to add a new workload entry.

The flow:

1. **Node attestation** — when a node joins, the agent attests itself to the server. In k8s, the agent uses the kubelet's identity (or PSAT token) to prove "I'm on this node, and this node is part of this cluster."
2. **Workload attestation** — when a Pod starts, the agent verifies the Pod's identity (via the kubelet's downward API, PSAT token, etc.) and matches it to a registered entry.
3. **SVID issuance** — the agent issues an SVID to the workload, accessible via the Workload API.
4. **Rotation** — before the SVID expires, the workload fetches a new one from the agent. The agent signs it with the trust bundle.

### 6.1 The registration entries

A **registration entry** is a rule that says "this SPIFFE ID should be given to a workload with these properties":

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata: { name: myapp }
spec:
  spiffeIDTemplate: "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
  workloadSelector:
    matchLabels:
      app: myapp
  # namespaceSelector, podSelector, etc.
```

The ClusterSPIFFEID says "any Pod with label `app: myapp` gets a SPIFFE ID of `spiffe://<trust-domain>/ns/<ns>/sa/<sa>`."

## 7. Node Attestation

When a node joins a SPIRE trust domain, the agent must prove "I am the agent for this node, and this node is trusted." This is **node attestation**.

In k8s, the common approach is **PSAT (Projected ServiceAccount Token) attestation**:

* The agent runs on the node, has access to the kubelet's identity.
* The agent sends its PSAT token to the server.
* The server validates the token (signed by the cluster CA) and confirms the agent is on a node it trusts.

Other node attestation methods (for non-k8s or hybrid):

* **AWS IID attestation** — verify the agent is on a specific EC2 instance.
* **GCP identity attestation** — verify the agent is on a specific GCE instance.
* **Azure MSI attestation** — verify the agent is on a specific Azure VM.
* **X.509 attestation** — the agent has a cert from a known CA.

Once attested, the agent can register workloads on that node.

## 8. Workload Attestation

When a Pod starts, the agent must prove "this Pod is the one I think it is" to the server. The agent looks at the Pod's metadata and matches it to a registration entry.

In k8s, the agent sees:

* **Pod's namespace**
* **Pod's ServiceAccount name**
* **Pod's labels** (from the kubelet)
* **Pod's projected tokens** (PSAT, etc.)
* **Container's image**

The agent uses these to match a registration entry. The entry says "give SPIFFE ID X to Pods matching selector Y."

If the Pod matches, the agent issues an SVID. If not, the agent refuses.

### 8.1 The selector

Selectors are how the agent decides which Pods match which entries. Common selectors in k8s:

* `k8s_psat` — the projected ServiceAccount token.
* `k8s_sa` — the ServiceAccount name.
* `k8s_namespace` — the namespace.
* `k8s_label` — a label on the Pod.
* `unix` — a UID (used for non-k8s workloads).

A typical entry:

```
Selectors:
  - k8s_psat: cluster.local:default:myapp
  - k8s_namespace: default
  - k8s_sa: myapp
SPIFFE ID: spiffe://cluster.example.com/ns/default/sa/myapp
```

The agent matches a Pod's PSAT, namespace, and ServiceAccount name to these selectors. If they all match, the Pod gets the SPIFFE ID.

## 9. Rotation

SPIRE rotates everything regularly:

* **SVIDs** — short-lived (default 1 hour for X.509-SVID, configurable). The workload auto-fetches new SVIDs before expiry.
* **Agent keys** — long-lived but rotated on demand.
* **Server keys** — long-lived, rotated via the spire-server CLI.

Rotation is transparent to the workload if it uses a SPIFFE client library. The library fetches new SVIDs before the old ones expire, and the new SVIDs are used in the next TLS handshake.

### 9.1 The grace period

The SVID's lifetime includes a "renewal threshold" (default 50% of the lifetime). The workload's library fetches a new SVID when the current one is 50% expired. This gives time to rotate without dropping traffic.

## 10. Federation (Cross-Cluster / Cross-Cloud)

**Federation** is when two trust domains agree to trust each other. With federation, a workload in trust domain A can authenticate a workload in trust domain B.

Use cases:

* **Cross-cluster mTLS** — cluster A and cluster B in different clouds, but their services need to talk securely.
* **Cross-org** — two companies want to share an API, with workload identity.

The mechanism:

1. Each trust domain's bundle (root CA) is exchanged with the other.
2. The bundles are configured as "federated bundles" in each SPIRE server.
3. When a workload in A presents its SVID to a workload in B, the workload in B validates the cert against the federated bundle.

Federation is configured in SPIRE's bundle endpoint (a gRPC + web endpoint). The bundles are pulled periodically.

### 10.1 The catch

Federation requires **explicit trust** — both sides have to agree. A trust domain can't unilaterally decide to trust another. The bundles are signed, so a man-in-the-middle can't substitute.

## 11. SPIFFE in Service Meshes

Service meshes (Istio, Linkerd, Cilium) are the primary consumers of SPIFFE in k8s.

### 11.1 Istio

Istio uses SPIRE-like identity (its own control plane, Istiod, issues the SVIDs). The SPIFFE IDs are of the form `spiffe://<trust-domain>/ns/<ns>/sa/<sa>`. The sidecar (Envoy) holds the workload's SVID and private key.

Istiod is the SPIRE-equivalent control plane. The SPIFFE IDs are issued by Istiod, not by a separate SPIRE.

### 11.2 Linkerd

Linkerd has its own identity component (linkerd-identity) that issues X.509-SVIDs. The trust bundle is published via a Kubernetes API. Linkerd's sidecar (linkerd2-proxy) holds the workload's SVID.

### 11.3 Cilium

Cilium uses SPIFFE IDs as workload identity for network policy. Cilium's identity is its own scheme (numeric labels), but the SPIFFE ID is exposed for cross-mesh use.

## 12. SPIFFE Without SPIRE

You can issue SPIFFE IDs without SPIRE:

* **Istiod** (in Istio) issues SPIFFE IDs directly.
* **linkerd-identity** (in Linkerd) issues SPIFFE IDs.
* **Custom issuers** — issue certs with SPIFFE IDs from your own CA.

The SPIFFE spec is just the format. The issuer can be anything. SPIRE is the most common issuer, but it's not the only one.

For a small cluster, the mesh's identity component is enough. For a heterogeneous environment (some Pods mesh-enabled, some not), SPIRE adds value by providing a single identity layer.

## 13. Operations and Debugging

### 13.1 Common commands

```bash
# check the SPIRE server status
spire-server healthcheck

# list all registered entries
spire-server entry show

# list agents
spire-agent healthcheck

# fetch an SVID as a workload
spire-agent api fetch
# returns an X.509-SVID

# get the trust bundle
spire-agent api fetch -write
# or via the Workload API
```

### 13.2 The "workload can't get an SVID" case

A Pod started, but the agent won't give it an SVID.

```bash
# 1. Is the agent running on the Pod's node?
kubectl -n spire get pods -l app=spire-agent
# should be a pod on the same node

# 2. Is the registration entry present?
spire-server entry show
# look for an entry matching the Pod's namespace / SA

# 3. Is the agent able to attest the workload?
spire-agent healthcheck
# look for attestation errors

# 4. Is the Workload API socket mounted?
kubectl exec <pod> -- ls /run/spire/sockets/
# should have agent.sock
```

### 13.3 The "SVID expired but not rotated" case

A workload's SVID is past its expiry, but the workload hasn't fetched a new one.

```bash
# 1. Is the agent reachable?
kubectl exec <pod> -- ls -la /run/spire/sockets/agent.sock

# 2. Is the SPIFFE client library configured?
# the app needs to use the library; without it, the SVID is static

# 3. Is the Workload API proxying correctly?
# (if using a proxy or sidecar)
kubectl logs <proxy>
```

## 14. Gotchas and Common Mistakes

### 14.1 The 20+ common mistakes

1. **A SPIFFE ID is not a secret.** The SVID (the cert and private key) is. The SPIFFE ID is the label.

2. **SVIDs are short-lived by design.** Default 1 hour. Plan for rotation. A long-lived SVID is a security smell.

3. **The Workload API is per-node.** Each node's agent has its own Workload API socket. Pods on different nodes get SVIDs from different agents.

4. **Trust domains partition identity.** A workload in `spiffe://cluster-a.example.com/...` can't authenticate to one in `spiffe://cluster-b.example.com/...` without federation.

5. **Federation requires explicit bundle exchange.** You can't just "trust the public SPIFFE bundle". Federation is bilateral.

6. **Service meshes hide SPIFFE.** Istio, Linkerd, Cilium issue SPIFFE IDs but you don't interact with the SPIRE API directly. The mesh is the abstraction.

7. **A workload without a SPIFFE client library can't rotate SVIDs.** It will get a single SVID and use it until it expires. The app must use a library (Go, Rust, etc.) for transparent rotation.

8. **The trust bundle is a CA, not a single cert.** The bundle may contain multiple CAs (root + intermediates). All are trusted.

9. **SVIDs are X.509 certs, not JWTs (in the X.509 case).** They work with standard TLS libraries. JWT-SVIDs are for application-level auth.

10. **The Workload API is a Unix socket, not a network endpoint.** Pods on different nodes can't share the socket. Each Pod uses the socket on its own node.

11. **Node attestation is the foundation.** If a node can't attest, the workloads on it can't either. Make sure the node attestation works in your environment.

12. **k8s PSAT attestation requires a working cluster CA.** The PSAT token is signed by the cluster CA. If the agent can't verify the PSAT (e.g. wrong CA bundle), attestation fails.

13. **SPIRE doesn't do authorization.** It does **authentication** (who are you). Authorization (what can you do) is a separate layer — RBAC, NetworkPolicy, mesh policy.

14. **SVIDs don't replace ServiceAccount tokens for apiserver auth.** They're different identities. SA tokens are for the apiserver; SVIDs are for service-to-service.

15. **The spire-controller-manager is a separate deployment.** It automates registration by watching k8s. Without it, you have to add entries manually via `spire-server entry create`.

16. **A ClusterSPIFFEID with the wrong selector gives every matching Pod the SPIFFE ID.** This is by design but is a footgun — a typo in a selector exposes more Pods than intended.

17. **Rotation has a 50% grace period.** The SVID is "fresh" until 50% of its lifetime. After that, the workload fetches a new one. A workload that doesn't fetch in time is stuck with an expired SVID.

18. **A workload's SVID is held by the sidecar (in a mesh).** If the sidecar crashes, the SVID is gone. The workload re-requests via the sidecar restart.

19. **The trust bundle in SPIRE can be rotated independently of the SVIDs.** A bundle rotation invalidates all SVIDs signed by the old CA. The new SVIDs are issued on the next request.

20. **SPIRE has its own API for entry management.** `spire-server entry create` adds an entry. There's no Kubernetes-native API for this without spire-controller-manager.

21. **A SPIRE agent's Workload API is a Unix socket at `/run/spire/sockets/agent.sock`** (or similar). The path is configurable, and the agent can listen on a TCP socket for non-k8s workloads.

22. **The trust domain is a single string.** It should be unique per trust boundary. Two clusters in the same org usually have the same trust domain (e.g. `cluster.example.com`); two orgs have different trust domains (`acme.com`, `initech.com`).

23. **SPIRE is a control plane, not a data plane.** It issues identities; it doesn't enforce mTLS. Enforcement is the sidecar's job (or the application's).

24. **SVIDs are not the same as TLS certs in general.** An SVID is a TLS cert that conforms to the SPIFFE spec (URI SAN, etc.). A regular TLS cert is not an SVID.

25. **The SPIRE server's CA signs the agents' certs.** The server's CA is the trust anchor for the trust domain. Rotate it carefully — all SVIDs change.

## See also

* [[Kubernetes/concepts/L07-security/08-tls-mtls|TLS / mTLS]] — the underlying transport security
* [[Kubernetes/concepts/L07-security/15-audit-logging|Audit Logging]] — what gets logged for SPIRE events
* [[Kubernetes/concepts/L07-security/19-runtime-detection|Runtime Detection]] — Falco/Tetragon as consumers of workload identity
