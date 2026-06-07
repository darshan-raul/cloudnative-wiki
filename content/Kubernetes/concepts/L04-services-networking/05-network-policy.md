# NetworkPolicy

*"https://kubernetes.io/docs/concepts/services-networking/network-policies/"*

A NetworkPolicy is a **firewall rule for Pods**. It specifies which Pods can talk to which other Pods, on which ports. Without any NetworkPolicy in a namespace, all Pods can talk to all other Pods — the default is "allow all".

## The default allow-all problem

By default, k8s networking is **flat and open**:

* Every Pod can reach every other Pod
* Every Pod can reach every Service
* Every Pod can reach the internet (subject to the CNI / egress rules)

A NetworkPolicy **narrows this** by selecting Pods and specifying allowed traffic.

## Basic example

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    - namespaceSelector:
        matchLabels:
          purpose: production
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  - to:                       # DNS to kube-system
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

Translation: "the `api` Pods in `prod` accept traffic on port 8080 only from the `frontend` Pods, and Pods in namespaces labeled `purpose: production`. They can only make outbound connections to `postgres` Pods (port 5432) and to DNS in kube-system."

## Selectors — the building blocks

Three orthogonal selectors, AND'd within `[]` (same list), OR'd across lists:

* **`podSelector`** — match Pods by label
* **`namespaceSelector`** — match namespaces by label
* **`ipBlock`** — match by CIDR (with `except` for exclusions)

```yaml
ingress:
- from:
  - podSelector:        # AND podSelector + namespaceSelector
      matchLabels:
        app: web
    namespaceSelector:
      matchLabels:
        tier: frontend
  - ipBlock:            # OR with the above
      cidr: 10.0.0.0/8
      except:
      - 10.0.5.0/24
```

## How it interacts with the CNI

NetworkPolicy is a **resource**, but enforcement is the CNI's job. The standard k8s CNIs:

* **Calico** — full NetworkPolicy support
* **Cilium** — full NetworkPolicy + extended policies (L7, FQDN-based)
* **Flannel** — **no NetworkPolicy support** (it's a simple overlay)
* **Weave Net** — full NetworkPolicy support
* **AWS VPC CNI** — supports NetworkPolicy via a separate add-on (Amazon VPC CNI with policy controller, or use Calico in parallel)

If your CNI doesn't enforce NetworkPolicy, the resources are silently ignored.

## Gotchas

* **NetworkPolicy is additive** — if any NetworkPolicy selects a Pod, that Pod's traffic is restricted to what the policies allow. Pods not selected by any policy are unaffected (still allow-all).
* **You need both ingress and egress policies** if you want to restrict both. `policyTypes: [Ingress, Egress]` means: this policy restricts both. If you only specify ingress, the policy doesn't restrict egress.
* **Always allow DNS egress** — Pods need to resolve names. Forget this and your app mysteriously can't reach anything.
* **Headless services need network connectivity too.** A StatefulSet's per-Pod DNS still requires the Pods to reach each other.
* **NetworkPolicy doesn't replace a service mesh.** It's L3/L4. For mTLS, retries, traffic shaping — use Istio/Linkerd/Cilium's L7 features.
* **The Pods selected by the policy live in the policy's namespace.** Cross-namespace policies need `namespaceSelector`.
* **Empty `podSelector` matches all Pods in the namespace.** Useful for "default deny" rules.
* **Default-deny recipe** — to lock down a namespace, apply first:
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: default-deny-all
  spec:
    podSelector: {}
    policyTypes:
    - Ingress
    - Egress
  ```
  Then add allow rules on top.

## L07 cross-link

For Pod-level security (Linux capabilities, runAsUser, read-only filesystem), see [[Kubernetes/concepts/L07-security/05-security-context|security-context]]. NetworkPolicy is L3/L4; SecurityContext is L0.
