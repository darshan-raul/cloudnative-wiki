## Kubernetes NetworkPolicy — Complete Reference

> "[https://kubernetes.io/docs/concepts/services-networking/network-policies/](https://kubernetes.io/docs/concepts/services-networking/network-policies/)"
> 
> A NetworkPolicy is a **firewall rule for Pods**. It specifies which Pods can talk to which other Pods, on which ports. Without any NetworkPolicy in a namespace, all Pods can talk to all other Pods — the default is "allow all".

### Table of Contents

1.[Fundamentals](https://agent.minimax.io/mavis?id=406558347030715#1-fundamentals)

2.[The Selector System](https://agent.minimax.io/mavis?id=406558347030715#2-the-selector-system)

3.[Port Specifications](https://agent.minimax.io/mavis?id=406558347030715#3-port-specifications)

4.[Policy Structure Deep Dive](https://agent.minimax.io/mavis?id=406558347030715#4-policy-structure-deep-dive)

5.[Real-World Recipes](https://agent.minimax.io/mavis?id=406558347030715#5-real-world-recipes)

6.[Advanced Scenarios](https://agent.minimax.io/mavis?id=406558347030715#6-advanced-scenarios)

7.[CNI Compatibility Matrix](https://agent.minimax.io/mavis?id=406558347030715#7-cni-compatibility-matrix)

8.[Operations & Tooling](https://agent.minimax.io/mavis?id=406558347030715#8-operations--tooling)

9.[Troubleshooting](https://agent.minimax.io/mavis?id=406558347030715#9-troubleshooting)

10.[Gotchas & Common Mistakes](https://agent.minimax.io/mavis?id=406558347030715#10-gotchas--common-mistakes)

11.[Integration with Other Security Primitives](https://agent.minimax.io/mavis?id=406558347030715#11-integration-with-other-security-primitives)

12.[Zero-Trust Checklist](https://agent.minimax.io/mavis?id=406558347030715#12-zero-trust-checklist)

### 1. Fundamentals

#### 1.1 What NetworkPolicy Is (and Isn't)

NetworkPolicy is a **Kubernetes resource** that defines how groups of Pods are allowed to communicate with each other and with external endpoints. It operates at **OSI Layers 3 and 4** — IP addresses and TCP/UDP ports.

text

```
NetworkPolicy scope:
  ✅ Pod-to-Pod (within same namespace)
  ✅ Pod-to-Pod (cross-namespace)
  ✅ Pod-to-External (CIDR-based)
  ✅ By IP address, port, and protocol (TCP/UDP/SCTP)

NetworkPolicy CANNOT do:
  ❌ L7 filtering (HTTP headers, path-based rules) — use a service mesh
  ❌ Application-layer authentication (mTLS) — use Istio/Linkerd
  ❌ Encrypt traffic — use a service mesh or CNI encryption
  ❌ Rate limiting (without CNI extensions)
  ❌ Apply to nodes directly — only Pods
```

#### 1.2 The Default-Allow-All Model

By default, Kubernetes networking is flat and permissive. Every Pod can:

- Reach every other Pod by Pod IP
- Reach every Service by ClusterIP / NodePort / LoadBalancer
- Egress to the internet (subject to cloud/VPC egress rules)
- Resolve DNS names via the cluster DNS (CoreDNS/kube-dns)

This is intentionally open — k8s doesn't restrict networking until you tell it to.

#### 1.3 Policy Application Model

A Pod is affected by NetworkPolicy when **at least one policy selects it**. Once any policy touches a Pod:

- The Pod's traffic is **restricted to exactly what the policies allow**
- The default allow-all is **overridden**, not supplemented
- The Pod becomes a **deny-by-default** endpoint for the traffic types covered

This is the most important mental model shift:

text

```
No policies select Pod X  →  Pod X: allow all (default k8s behavior)
At least one policy selects Pod X  →  Pod X: deny by default, allow listed
```

#### 1.4 The policyTypes Field

`policyTypes` declares which directions a policy governs. Its behavior is subtle:

|Declared|Has `ingress` block?|Has `egress` block?|Behavior|
|---|---|---|---|
|Not set|No|No|API rejects the resource (invalid)|
|Not set|Yes|No|Implies `[Ingress]`|
|Not set|No|Yes|Implied `[Egress]`|
|Not set|Yes|Yes|Implies `[Ingress, Egress]`|
|`[]` (empty)|Any|Any|**Explicitly no types** — policy has zero effect|

**Best practice:** Always set `policyTypes` explicitly. Relying on implicit inference makes policies harder to reason about during audits.

yaml

```
# Explicit is better than implicit
spec:
  policyTypes:
  - Ingress     # explicitly declare
  - Egress
```

#### 1.5 Policy Structure Anatomy

yaml

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: my-policy
  namespace: default        # (1) Policy lives in a namespace
spec:
  podSelector:              # (2) Which Pods does this apply TO?
    matchLabels:
      app: api
  policyTypes:              # (3) Which directions?
  - Ingress
  - Egress
  ingress:                  # (4) Inbound rules (who can talk TO api pods)
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
  egress:                   # (5) Outbound rules (where api pods can go)
  - to:
    - podSelector:
        matchLabels:
          app: db
    ports:
    - protocol: TCP
      port: 5432
```

Five structural parts — every policy has all five.

### 2. The Selector System

The selector system has three primitives, and understanding how they interact is the key to mastering NetworkPolicy.

#### 2.1 The Three Selectors

|Selector|What it matches|Scope|
|---|---|---|
|`podSelector`|Pods by their labels|Within the policy's namespace|
|`namespaceSelector`|Namespaces by their labels|All namespaces|
|`ipBlock`|CIDR ranges of IPs|External or internal CIDRs|

#### 2.2 Selector Composition: AND within a block, OR across blocks

This is the most commonly misunderstood rule:

yaml

```
ingress:
- from:
  - podSelector:           # Selector block A
      matchLabels:
        app: web
    namespaceSelector:     # AND — both must match
      matchLabels:
        tier: frontend
  - podSelector:           # Selector block B — OR with block A
      matchLabels:
        app: mobile
```

Block A: "Pod must have `app=web` **AND** namespace must have `tier=frontend`"  
Block B: "Pod must have `app=mobile`"  
Block A **OR** Block B.

#### 2.3 podSelector — Within-Namespace

yaml

```
# Allow traffic from web pods in the SAME namespace
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  ports:
  - protocol: TCP
    port: 8080
```

yaml

```
# Allow traffic from pods matching ANY of these labels (OR)
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  - podSelector:
      matchLabels:
        app: mobile
  ports:
  - protocol: TCP
    port: 8080
```

yaml

```
# Allow from pods with multiple labels (AND)
ingress:
- from:
  - podSelector:
      matchExpressions:
      - key: app
        operator: In
        values:
        - web
        - mobile
      - key: version
        operator: NotIn
        values:
        - deprecated
```

#### 2.4 namespaceSelector — Cross-Namespace

==Namespaces are matched by their labels, not their names:==

yaml

```
# Label your namespaces first
# kubectl label namespace production purpose=production
# kubectl label namespace staging purpose=staging

ingress:
- from:
  - namespaceSelector:
      matchLabels:
        purpose: production
```

yaml

```
# Allow from ANY pod in namespaces labeled tier=frontend
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        tier: frontend
```

yaml

```
# Combine namespaceSelector + podSelector (AND within block)
# Allows traffic only from web pods IN frontend-tier namespaces
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
    namespaceSelector:
      matchLabels:
        tier: frontend
```

yaml

```
# Allow from web pods OR from frontend-tier namespaces (OR across blocks)
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  - namespaceSelector:
      matchLabels:
        tier: frontend
```

#### 2.5 ipBlock — CIDR-Based Selection

`ipBlock` lets you match by IP CIDR. This is your tool for:

- Allowing external API access (e.g., your office IP)
- Blocking known malicious CIDRs
- Defining cluster egress boundaries

yaml

```
# Allow ingress from a specific external CIDR
ingress:
- from:
  - ipBlock:
      cidr: 203.0.113.0/24
  ports:
  - protocol: TCP
    port: 443
```

yaml

```
# Allow from 10.0.0.0/8 EXCEPT 10.0.5.0/24
ingress:
- from:
  - ipBlock:
      cidr: 10.0.0.0/8
      except:
      - 10.0.5.0/24
```

yaml

```
# Allow from internal CIDR AND external office IP
ingress:
- from:
  - podSelector: {}         # all pods in namespace
  - ipBlock:
      cidr: 198.51.100.0/24  # office egress IP (using 198.51.100.0/24 as example)
```

#### 2.6 Empty Selectors

An empty `podSelector: {}` matches **all Pods in the policy's namespace**:

yaml

```
# Allow all inbound traffic to all pods in this namespace
spec:
  podSelector: {}           # matches everything
  ingress:
  - from:
    - podSelector: {}       # from everywhere
```

This is the building block for **namespace-wide default-allow** policies.

#### 2.7 The Invisible Default Namespace Label

Kubernetes automatically applies a label to every namespace:

`kubernetes.io/metadata.name: <namespace-name>`

This is always present and useful for targeting `kube-system` reliably:

yaml

```
# Correct way to allow DNS egress
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
  ports:
  - protocol: UDP
    port: 53
  - protocol: TCP
    port: 53
```

> ⚠️ Older tutorials used `kubernetes.io/namespace.name: kube-system` — this is a **deprecated label** that may not be present in all clusters. Use `kubernetes.io/metadata.name` instead.

### 3. Port Specifications

#### 3.1 Named Ports

Refer to a port by name instead of number — the actual port number is resolved from the Pod spec:

yaml

```
# In your Pod spec:
# containers:
# - name: api
#   ports:
#   - name: http
#     containerPort: 8080
#   - name: admin
#     containerPort: 9090

# In your NetworkPolicy:
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  ports:
  - protocol: TCP
    port: http        # named port — resolved at runtime
```

**Why use named ports?**

- Policy stays valid across container port changes
- Self-documenting (intent is clearer than port 8080)
- Works well when multiple containers share a Pod (sidecars)

#### 3.2 Port Ranges

Use `endPort` to specify a range instead of a single port:

yaml

```
ingress:
- from:
  - podSelector:
      matchLabels:
        app: monitoring
  ports:
  - protocol: TCP
    port: 30000
    endPort: 32767       # allow all NodePorts
```

**Constraints:**

- `endPort` must be >= `port`
- `port` and `endPort` must be in the same protocol
- CNI must support endPort (Calico ≥3.8, Cilium, newer Weave — not all CNIs)

#### 3.3 Protocol

Three protocols are supported:

yaml

```
ports:
- protocol: TCP
  port: 8080
- protocol: UDP
  port: 53              # DNS
- protocol: SCTP
  port: 9898            # Stream Control Transmission Protocol
```

> **SCTP note:** Not all CNIs support SCTP policies. Calico supports it; verify your CNI if you need SCTP filtering.

### 4. Policy Structure Deep Dive

#### 4.1 Multiple Ingress/Egress Rules

Each `ingress:` and `egress:` block can contain **multiple rule entries**. They are OR'd together:

yaml

```
ingress:
- from:                              # Rule 1
  - podSelector:
      matchLabels:
        app: web
  ports:
  - protocol: TCP
    port: 8080
- from:                              # Rule 2 — separate OR'd entry
  - podSelector:
      matchLabels:
        app: mobile
  ports:
  - protocol: TCP
    port: 3000
- from:                              # Rule 3
  - ipBlock:
      cidr: 10.0.0.0/8
  ports:
  - protocol: TCP
    port: 8080
```

This Pod accepts traffic on port 8080 from web pods OR on port 3000 from mobile pods OR on port 8080 from the internal CIDR.

#### 4.2 Multiple PolicyTypes

yaml

```
spec:
  policyTypes:
  - Ingress
  - Egress
  - Ingress                       # duplicate — deduplicated by API server
```

Duplicate `policyTypes` values are silently deduplicated by the API server.

#### 4.3 Ingress Without From (Allow All Inbound)

yaml

```
# Allow all inbound traffic on port 443
ingress:
- ports:
  - protocol: TCP
    port: 443
```

yaml

```
# Allow all inbound traffic (no port restriction)
ingress:
- {}                             # empty rule = allow all
```

#### 4.4 Egress Without To (Allow All Outbound)

yaml

```
# Allow all outbound on port 443
egress:
- ports:
  - protocol: TCP
    port: 443
```

#### 4.5 Empty Ingress / Egress with policyTypes Declared

yaml

```
# Restrict egress but allow all ingress
spec:
  podSelector:
    matchLabels:
      app: isolated-db
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 5432
  ingress: []                    # empty — no inbound allowed
```

yaml

```
# Restrict ingress but allow all egress
spec:
  podSelector:
    matchLabels:
      app: public-cache
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 6379
  egress: []                     # empty — no outbound restriction
```

#### 4.6 Multiple Policies Selecting the Same Pod

Multiple policies can select the same Pod. Traffic is allowed if **any policy permits it**:

yaml

```
# Policy 1: allow web → api on port 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-api
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports: [ { protocol: TCP, port: 8080 } ]

---
# Policy 2: allow monitoring → api on port 8080
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-to-api
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: prometheus
    ports: [ { protocol: TCP, port: 8080 } ]
```

Web pods AND monitoring pods can both reach api — policies are additive in what they allow.

#### 4.7 Order of Rule Evaluation

There is no explicit ordering. Rules are evaluated as a union. A connection is allowed if **at least one rule matches**. A connection is denied if **no rule matches**.

### 5. Real-World Recipes

#### 5.1 Default Deny — The Foundation

Apply this **before** any allow rules. It ensures that every new Pod is denied by default until you explicitly allow it:

yaml

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}              # all pods
  policyTypes:
  - Ingress
  - Egress
```

bash

```
# Apply it first — before any allow rules exist in the namespace
kubectl apply -f default-deny.yaml

# Then apply your allow rules
kubectl apply -f allow-rules.yaml
```

> ⚠️ **Warning:** Applying a default-deny to a namespace where existing Pods are communicating will **immediately break those connections**. Apply during a maintenance window or deploy with a rolling update to ensure new Pods (with allow rules) are ready before old Pods are restarted.

#### 5.2 Web → API → Database (Three-Tier)

**Network layer:**

text

```
web pods  ──→  API pods  ──→  DB pods
(frontend)      (app tier)     (data tier)
```

yaml

```
# --- Allow web → api ---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports: [ { protocol: TCP, port: 8080 } ]

---
# --- Allow api → database ---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api
    ports: [ { protocol: TCP, port: 5432 } ]
  # Note: no egress on database — it's the terminus
```

#### 5.3 DNS Egress — The Required Rule

Every Pod that needs to resolve cluster Service names needs this:

yaml

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: production
spec:
  podSelector: {}               # all pods in namespace
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53                  # DNS queries
    - protocol: TCP
      port: 53                  # DNS over TCP (large responses)
```

> ⚠️ **UDP port 53 is non-negotiable.** Without it, no Pod in this namespace can resolve `my-service.my-namespace.svc.cluster.local`. Your app will fail to connect to Services with a "name or service not known" error — which is confusing because the Service exists.

#### 5.4 Allow External HTTPS Egress (to Specific CIDRs)

yaml

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-https-egress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Egress]
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0        # internet
        except:
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16       # exclude private ranges
    ports:
    - protocol: TCP
      port: 443
  - to:                         # DNS is always needed
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

> ⚠️ **The DNS rule must come separately.** If you only allow `0.0.0.0/0:443`, the Pod can't resolve external hostnames before it makes the HTTPS connection. DNS runs on port 53 UDP, which is separate from HTTPS.

#### 5.5 Allow Office IP to API Ingress

yaml

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-office-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - ipBlock:
        cidr: 203.0.113.0/24   # your office egress IP range
    ports: [ { protocol: TCP, port: 443 } ]
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports: [ { protocol: TCP, port: 8080 } ]
```

#### 5.6 Allow Ingress from an Entire Namespace

yaml

```
# Allow all pods in namespace "monitoring" to reach "api" pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-namespace
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: monitoring
    ports: [ { protocol: TCP, port: 8080 } ]
```

#### 5.7 Locking Down Egress to Specific External Service

yaml

```
# Allow api pods to reach only api.myexternal.com (resolved to a known IP)
# First, resolve the IP:
#   host api.myexternal.com  →  203.0.113.50
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-external
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Egress]
  egress:
  - to:
    - ipBlock:
        cidr: 203.0.113.50/32  # exact IP of the external service
    ports: [ { protocol: TCP, port: 443 } ]
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports: [ { protocol: UDP, port: 53 } ]  # DNS required
```

> ⚠️ **IP-based external services are fragile.** External IPs change. Consider allowing `0.0.0.0/0:443` with a service mesh for L7 filtering, or use Cilium's FQDN-based policies.

#### 5.8 Ingress for a LoadBalancer Service

yaml

```
# Ingress controller → your app
# Standard setup: ingress controller runs in ingress-nginx namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports: [ { protocol: TCP, port: 8080 } ]
```

#### 5.9 Allow Metrics Scraping (Prometheus)

yaml

```
# Allow Prometheus in the monitoring namespace to scrape metrics
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scraping
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: monitoring
    ports:
    - protocol: TCP
      port: 8080                 # main app port
    - protocol: TCP
      port: 9090                 # metrics endpoint
```

#### 5.10 Namespace-Wide Allow (Same-Namespace Pods Only)

yaml

```
# Allow all pods in this namespace to talk to each other
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: production
spec:
  podSelector: {}                # all pods
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}            # any pod in same namespace
  egress:
  - to:
    - podSelector: {}            # any pod in same namespace
```

### 6. Advanced Scenarios

#### 6.1 StatefulSet and Headless Services

StatefulSets require special attention because each Pod has a stable network identity and often needs to reach its peers:

yaml

```
# StatefulSet Pods with stable identities
# Pods: web-0, web-1, web-2
# Headless Service: web-headless.ns.svc.cluster.local
# Resolves to: web-0.web-headless.ns.svc.cluster.local, etc.

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-statefulset-peer-traffic
  namespace: production
spec:
  # Target all web pods (including web-0, web-1, web-2)
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web              # allow traffic from other web pods
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: web              # allow traffic to other web pods
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

**Why?** Without peer-to-peer rules, a 3-replica StatefulSet will have Pods that can't reach each other, causing split-brain in databases like Cassandra or CockroachDB.

#### 6.2 Multi-Namespace Communication (Microservices)

yaml

```
# API in "api" namespace can call the Payment service in "payments" namespace
# AND the User service in "users" namespace
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-namespace
  namespace: api
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: payment-service
    - podSelector:
        matchLabels:
          app: user-service
    ports: [ { protocol: TCP, port: 8080 } ]
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports: [ { protocol: UDP, port: 53 } ]
```

On the receiving side, the payments namespace must allow ingress from the api namespace:

yaml

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-namespace-ingress
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: payment-service
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: api
    ports: [ { protocol: TCP, port: 8080 } ]
```

> ⚠️ **Both sides need policies.** NetworkPolicy is unidirectional. `api → payments` requires an egress rule on `api` AND an ingress rule on `payments`. Think of it like a firewall on each host — each direction needs its own rule.

#### 6.3 ServiceAccount-Based Access

NetworkPolicy doesn't have a native `serviceAccountSelector`, but you can achieve this by labeling Pods by their ServiceAccount:

yaml

```
# Add a label to the Pod's spec template that references the SA name
# (via a common label convention, e.g., app.kubernetes.io/service-account)
spec:
  template:
    metadata:
      labels:
        app: api
        app.kubernetes.io/service-account: api-service-account
```

yaml

```
# Then reference it in the policy
ingress:
- from:
  - podSelector:
      matchLabels:
        app.kubernetes.io/service-account: web-service-account
```

> This is indirect — you can't query by ServiceAccount directly. Consider using consistent labeling conventions to bridge the gap.

#### 6.4 Protecting the Kubernetes API Server

yaml

```
# Prevent all pods from reaching the API server except authorized ones
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-api-server-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: TCP
      port: 443                 # API server
---
# Exception: specific pods CAN reach the API server
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-server-for-privileged
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: controller
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: TCP
      port: 443
```

#### 6.5 Combining Calico Global NetworkPolicy (Cluster-Wide)

Calico extends NetworkPolicy with **GlobalNetworkPolicy**, which can select Pods across all namespaces:

yaml

```
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-all-by-default
spec:
  applyOnFinalize: true
  ingress:
  - action: Deny
  egress:
  - action: Deny
  types:
  - Ingress
  - Egress
```

This is a cluster-wide default-deny that runs alongside namespace-scoped NetworkPolicy resources.

#### 6.6 Cilium L7 Policy (Beyond Standard k8s NetworkPolicy)

Cilium extends NetworkPolicy to L7. When you need this level of control, you use CiliumNetworkPolicy:

yaml

```
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-http-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: web
    toPorts:
    - port: "8080"
      protocol: TCP
      rules:
        http:
        - method: GET
          path: "/api/v1.*"
        - method: POST
          path: "/api/v1/data"
```

> Cilium's L7 policies let you inspect HTTP methods, paths, headers, and more — something standard NetworkPolicy can't do. This is a CNI-specific extension, not part of the core k8s spec.

#### 6.7 Port-Based Service Exposure with NodePort/LoadBalancer

When your Service is of type `NodePort` or `LoadBalancer`, the CNI sees traffic originating from the node's IP (not the Pod's IP), which can affect how selectors match:

yaml

```
# External traffic hits node IP → Service → Pod
# The source IP the Pod sees depends on CNI (SNAT behavior)

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nodeport-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: {}           # allow from any pod in namespace
  - from:
    - ipBlock:
        cidr: 0.0.0.0/0         # for NodePort/LoadBalancer, include external
```

> With many CNIs (Calico, Cilium in certain modes), external traffic is SNAT'd to the node IP. Use `ipBlock: 0.0.0.0/0` or whitelist your cloud's node/CIDR ranges.

#### 6.8 Webhook / Admission Controller Integration

Use OPA Gatekeeper or Kyverno to enforce NetworkPolicy rules cluster-wide:

**Gatekeeper (OPA):**

yaml

```
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: namespace-must-have-network-policy
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Namespace"]
  parameters:
    labels:
    - key: "network-policy-required"
      allowedRegex: "true"
```

yaml

```
# Require every namespace to have a default-deny policy
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequireNetworkPolicy
metadata:
  name: require-default-deny
spec:
  match:
    kinds:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["NetworkPolicy"]
```

**Kyverno:**

yaml

```
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-deny
spec:
  rules:
  - name: add-default-deny
    match:
      resources:
        kinds:
        - Namespace
        - Namespace
    generate:
      kind: NetworkPolicy
      name: default-deny-all
      namespace: "{{ request.object.metadata.name }}"
      data:
        spec:
          podSelector: {}
          policyTypes: [Ingress, Egress]
```

### 7. CNI Compatibility Matrix

NetworkPolicy enforcement is entirely the CNI's responsibility. A CNI that doesn't implement it will silently ignore NetworkPolicy resources.

|CNI|Ingress|Egress|L7 / FQDN|Notes|
|---|---|---|---|---|
|**Calico**|✅|✅|✅ (Tiered policies)|Full support. Use GlobalNetworkPolicy for cluster-wide rules.|
|**Cilium**|✅|✅|✅ (native)|Best L7 support. FQDN-based policies natively.|
|**Weave Net**|✅|✅|❌|Full L3/L4 support. No L7.|
|**Flannel**|❌|❌|❌|Does not support NetworkPolicy.|
|**AWS VPC CNI**|❌|❌|❌|No native support. Use Calico or VPC CNI Policy Controller.|
|**GKE (default)**|⚠️|⚠️|❌|Requires "Network Policy" to be enabled at cluster creation. Uses Calico under the hood.|
|**AKS (default)**|⚠️|⚠️|❌|Requires "Network Policy" option (Calico or Azure).|
|**EKS (default)**|⚠️|⚠️|❌|Requires Calico to be installed separately.|
|**kind (default)**|❌|❌|❌|Default kind CNI (bridge) doesn't support it. Use Calico for kind.|

#### Verifying Your CNI Supports NetworkPolicy

bash

```
# Method 1: Check if a NetworkPolicy is being enforced
# Deploy a deny-all policy and verify it actually blocks traffic

# Method 2: Check CNI annotations on nodes
kubectl get nodes -o wide
kubectl describe node <node-name> | grep -i cni

# Method 3: Check for the CNI DaemonSet
kubectl get daemonset -A | grep -E "calico|cilium|weave|flannel"

# Method 4: Create a test policy and verify it works
kubectl run --rm -it --image=busybox test-pod --restart=Never -- /bin/sh
# Then try to reach another pod and verify the policy is blocking/allowing
```

#### Enabling NetworkPolicy on Cloud Providers

bash

```
# GKE: Enable network policy at cluster creation
gcloud container clusters create my-cluster \
  --enable-network-policy \
  --cluster-version=1.28

# AKS: Enable network policy
az aks create \
  --network-policy network-policy \
  # Choose: calico OR azure

# EKS: Install Calico operator
kubectl apply -f https://docs.projectcalico.org/manifests/calico-typha.yaml
```

### 8. Operations & Tooling

#### 8.1 kubectl Commands Reference

bash

```
# Apply a NetworkPolicy
kubectl apply -f policy.yaml

# List all NetworkPolicies in a namespace
kubectl get networkpolicy -n production

# Describe a specific policy
kubectl describe networkpolicy allow-web-to-api -n production

# Delete a policy
kubectl delete networkpolicy default-deny-all -n production

# View policy as YAML
kubectl get networkpolicy default-deny-all -n production -o yaml

# List which pods have NO NetworkPolicy (allow-all)
# Get all pods, find those without a matching policy
kubectl get pods -n production -o json | \
  jq '.items[] | select(.metadata.annotations["networking.kubernetes.io/policies"] == null) | .metadata.name'

# Dry-run validation
kubectl apply -f policy.yaml --dry-run=server
```

#### 8.2 Visualizing Network Policies

**Calico Enterprise / UI:** Graph visualization of policy relationships between namespaces and pods.

**kubectl-graph (社区):**

bash

```
# Visualize what can reach a pod
kubectl exec -it -n production \
  $(kubectl get pods -n production -l app=api -o jsonpath='{.items[0].metadata.name}') \
  -- wget -qO- --spider localhost:8080 2>&1
```

**Network Policy Logger:**

bash

```
# Enable policy audit mode in Calico to log allowed/denied connections
# In calico-config ConfigMap, set:
# CALICO_AWIREGUARD_POLICY_AUDIT_ENABLED: "true"
```

#### 8.3 Testing Policies

bash

```
# From within a pod, test connectivity
kubectl exec -it -n production api-pod -- /bin/sh

# Test egress to a specific IP:port
nc -zv 10.0.5.20 5432

# Test DNS resolution
nslookup kubernetes.default.svc.cluster.local

# Test egress to an external host
wget --spider https://api.github.com

# Test ingress (from another pod in the cluster)
kubectl exec -it -n production web-pod -- \
  wget -qO- --timeout=5 http://api:8080/health
```

#### 8.4 Rolling Out Policies Safely

The safest rollout order:

text

```
1. Apply default-deny to NAMESPACE with zero pods initially
2. Deploy application pods (they land into a deny-by-default namespace)
3. Apply allow rules for the application's required communication paths
4. Verify connectivity
5. Iterate
```

For existing namespaces with running workloads:

bash

```
# Option A: Rolling restart — new pods get policies immediately
kubectl rollout restart deployment/api -n production

# Option B: Add allow rules BEFORE applying default-deny
# 1. Add all allow rules first (pods still allow-all)
# 2. Apply default-deny (old pods still running but now restricted)
# 3. Rolling restart to get new pods that were born into the restricted env

# Option C: Use namespace isolation mode (Calico)
# This lets you test policies in "log-only" mode before enforcing them
```

#### 8.5 Policy Ordering and Conflict Detection

bash

```
# Calico: Check for policy conflicts
calicoctl policy ls

# View policy impact assessment
kubectl exec -i -n calico-system \
  $(kubectl get pods -n calico-system -l k8s-app=calico-typha -o jsonpath='{.items[0].metadata.name}') \
  -- calicoctl policy show
```

### 9. Troubleshooting

#### 9.1 Debugging Flowchart

text

```
Connection blocked?
│
├─ Is the source Pod selected by a policy?
│   └─ NO → No policy affects it, check the default allow behavior
│   └─ YES → Continue
│
├─ Is the destination Pod selected by a policy?
│   └─ NO → Destination allows all, check source policies
│   └─ YES → Continue
│
├─ Does the policy have the right policyType?
│   └─ Only Ingress? → Can't block egress
│   └─ Only Egress? → Can't block ingress
│
├─ Do selectors match the target?
│   └─ podSelector: correct labels?
│   └─ namespaceSelector: correct namespace labels?
│   └─ ipBlock: correct CIDR?
│
├─ Are the ports correct?
│   └─ Protocol matches (TCP/UDP)?
│   └─ Port number / named port correct?
│   └─ endPort supported by CNI?
│
├─ Is DNS working?
│   └─ Can pods resolve names? (kube-system DNS egress)
│   └─ Can pods reach the DNS server?
│
├─ Does the CNI support NetworkPolicy?
│   └─ Flannel → Does NOT support, policies ignored
│   └─ Cloud provider default → May need enabling
```

#### 9.2 Common Symptom → Cause Mapping

|Symptom|Likely Cause|
|---|---|
|Pod can't resolve Service names|Missing DNS egress rule (kube-system UDP:53)|
|Pod can't reach the internet|Missing egress rule with `ipBlock: 0.0.0.0/0` or NAT configuration|
|Prometheus can't scrape metrics|Missing ingress rule on target pod for monitoring namespace|
|StatefulSet pods can't talk to each other|Missing peer-to-peer egress/ingress rules|
|App works locally but not via LoadBalancer|Missing ingress rule for `podSelector: {}` or external CIDR|
|Policy applied but traffic still flows|CNI doesn't support NetworkPolicy (Flannel, default kind CNI)|
|Connection refused after applying policy|Policy blocks the connection; verify from/to selectors|
|"Connection timed out" after applying policy|Policy blocks the connection; check egress + DNS|
|API server calls fail|Missing egress rule to kube-system:443|

#### 9.3 Diagnostic Commands

bash

```
# 1. List all policies affecting a pod
kubectl get networkpolicy -o json | \
  jq '.items[] | select(.spec.podSelector.matchLabels.app == "api")'

# 2. Check which policies select a pod (via label)
POD_LABELS=$(kubectl get pod api-pod -n production -o jsonpath='{.metadata.labels}')
echo "$POD_LABELS"

# 3. Simulate policy evaluation (Calico)
calicoctl policy check --container=test-pod -n production

# 4. Enable CNI-level logging (Calico)
# Add to FelixConfiguration:
# kubectl apply -f - <<EOF
# apiVersion: projectcalico.org/v3
# kind: FelixConfiguration
# metadata:
#   name: default
# spec:
#   policyAuditLogDir: /var/log/calico/policy
# EOF

# 5. Packet capture at the node level (for deep debugging)
kubectl debug node/<node-name> -it --image=busybox -- \
  tcpdump -i <interface> -n port 8080

# 6. Check CNI plugin logs
kubectl logs -n kube-system -l k8s-app=kube-proxy
# For Calico:
kubectl logs -n calico-system -l k8s-app=calico-node
# For Cilium:
kubectl logs -n kube-system -l k8s-app=cilium
```

### 10. Gotchas & Common Mistakes

#### 10.1 NetworkPolicy Is Additive — Not Subtractive

yaml

```
# WRONG assumption: "This policy denies X"
# CORRECT understanding: "This policy ALLOWS X; everything else is denied"

# If policy A allows web → api
# And policy B allows monitoring → api
# BOTH are allowed — you can't use one policy to "undo" another
```

#### 10.2 The Empty podSelector Trap

yaml

```
# Matches ALL pods in the namespace — including system pods
podSelector: {}

# If your namespace has system/ingress pods, this may be too broad
# Always pair with specific namespace selectors or policyTypes
```

#### 10.3 Service Name Doesn't Work in from/to Selectors

yaml

```
# WRONG — Services are not Pods
egress:
- to:
  - podSelector: {}           # this matches pods, NOT services

# Services are load balancers for Pods.
# The traffic goes TO a Service IP, but the actual connection is to a Pod IP.
# NetworkPolicy evaluates at the Pod level.
```

#### 10.4 DNS Resolution Requires Both UDP and TCP

yaml

```
# WRONG — only UDP, large DNS responses will fail
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
  ports:
  - protocol: UDP
    port: 53

# CORRECT — both UDP and TCP
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
  ports:
  - protocol: UDP
    port: 53
  - protocol: TCP
    port: 53
```

#### 10.5 Pod IP Changes Break ipBlock Exceptions

yaml

```
# Pod IPs are ephemeral — they change on Pod restart
egress:
- to:
  - ipBlock:
      cidr: 10.244.0.5/32     # this IP will change!

# Use podSelector instead for internal pods
egress:
- to:
  - podSelector:
      matchLabels:
        app: database         # label-based, survives restarts
```

#### 10.6 Default-Deny Blocks the Pod That Applies It

bash

```
# If you apply a default-deny policy and your deploy tool is running
# in the same namespace, the deploy tool may lose access to the API server

# Solution: apply default-deny with a label selector that excludes the tool
spec:
  podSelector:
    matchLabels:
      app: api
      # Don't apply to deploy tool pods
  # OR use a separate namespace for operational tooling
```

#### 10.7 Sidecar Containers and Ingress/Egress

If you have an Istio Envoy sidecar, the sidecar intercepts all inbound and outbound traffic:

yaml

```
# Envoy sidecar behavior:
# Inbound: external traffic → Envoy → your container
#          NetworkPolicy sees the external source IP, not the Envoy IP
# Outbound: your container → Envoy → external
#           NetworkPolicy sees your container's IP

# If you need the sidecar to handle network policy:
# Configure Istio's AuthorizationPolicy to work alongside NetworkPolicy
# NetworkPolicy still operates at the Pod level, but Envoy rewrites traffic
```

#### 10.8 Cluster Upgrades Can Reset CNI Configuration

bash

```
# After a cluster upgrade, verify CNI support is still active
kubectl get daemonset -A | grep -E "calico|cilium|weave"
kubectl get configmap -n kube-system calico-config  # Calico
kubectl get configmap -n kube-system cilium-config  # Cilium

# GKE specifically: upgrading GKE can reset the "Network Policy" flag
# Re-enable it if needed after cluster upgrades
gcloud container clusters update my-cluster \
  --enable-network-policy
```

#### 10.9 Namespace Selector Doesn't Exclude the Policy's Own Namespace

yaml

```
# This policy's namespace IS included in the namespaceSelector
# If the namespace has the matching label, pods in THIS namespace are matched too
namespaceSelector:
  matchLabels:
    tier: frontend

# To exclude the current namespace:
# Use podSelector AND namespaceSelector with NotIn expression
# (Note: matchExpressions operator: NotIn on namespaceSelector is NOT supported
#  in standard k8s NetworkPolicy — Calico supports it)
```

#### 10.10 No way to log dropped packets (without CNI extensions)

Standard k8s NetworkPolicy doesn't provide a way to log or audit dropped connections. Without CNI-specific extensions:

- You won't see "policy X blocked connection Y" in logs
- Blocked connections are silently dropped

Calico's policy audit logs and Cilium's datapath logging provide this capability as a CNI extension.

### 11. Integration with Other Security Primitives

NetworkPolicy is one layer of a defense-in-depth strategy:

#### 11.1 NetworkPolicy + SecurityContext

text

```
SecurityContext  →  L0/L1  →  What the PROCESS can do (capabilities, UID, filesystem)
NetworkPolicy    →  L3/L4  →  Which IPs/ports the POD can talk to
ServiceMesh      →  L7     →  What the PROTOCOL content allows (mTLS, headers)
```

yaml

```
# SecurityContext: restricts what the container can do
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true

# NetworkPolicy: restricts what the pod can talk to
# (applied as a separate NetworkPolicy resource)
```

#### 11.2 NetworkPolicy + PodSecurity Standards

yaml

```
# PodSecurityPolicy / Pod Security Standards enforce what pods CAN be created
# NetworkPolicy enforces what pods CAN COMMUNICATE with once running
# Both must be satisfied — they address different threat vectors
```

#### 11.3 NetworkPolicy + Kyverno / OPA

Use policy-as-code to enforce that every namespace has a NetworkPolicy before workloads can be deployed:

yaml

```
# Kyverno ClusterPolicy: require NetworkPolicy in every namespace
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-network-policy
spec:
  validationFailureAction: Enforce   # blocks deployment without NetworkPolicy
  rules:
  - name: check-network-policy
    match:
      resources:
        kinds:
        - Namespace
    validate:
      message: "Every namespace must have a default-deny NetworkPolicy"
      pattern:
        metadata:
          labels:
            network-policy: "true"
```

#### 11.4 NetworkPolicy vs. Kubernetes Network Policies (Cilium vs. Calico)

|Feature|Standard k8s|Calico|Cilium|
|---|---|---|---|
|Ingress / Egress|✅|✅|✅|
|podSelector / namespaceSelector|✅|✅|✅|
|ipBlock|✅|✅|✅|
|Port ranges (endPort)|✅|✅|✅|
|SCTP|✅|✅|✅|
|L7 rules|❌|⚠️ (Tiered policies)|✅ (native)|
|FQDN-based policies|❌|⚠️ (DNS policy)|✅ (native)|
|Global cluster-wide policy|❌|✅ (GlobalNetworkPolicy)|⚠️ (CiliumClusterwideNetworkPolicy)|
|Policy prioritization|❌|✅|✅|
|Before/after action ordering|❌|✅|✅|
|Policy audit logging|❌|✅|✅|

### 12. Zero-Trust Checklist

When hardening a namespace with NetworkPolicy, work through this checklist:

#### Before You Begin

- Identify your CNI and confirm it supports NetworkPolicy
- Label all namespaces consistently (`purpose`, `tier`, etc.)
- Label all pods with meaningful application labels
- Know which pods need to communicate with each other

#### Policy Sequence

- Step 1: Apply `default-deny` to the namespace
- Step 2: Add `allow-dns-egress` (UDP+TCP port 53 to kube-system)
- Step 3: Add ingress allow rules for each consuming pod
- Step 4: Add egress allow rules for each upstream dependency
- Step 5: Add ingress/egress rules for monitoring/metrics scraping
- Step 6: Add ingress/egress rules for health checks and liveness probes
- Step 7: Add egress rule for API server access if needed
- Step 8: Add egress rule for external HTTPS if needed

#### Verify

- Test that allowed communication paths work
- Test that disallowed paths are blocked
- Verify StatefulSet peer communication
- Verify headless Service DNS resolution
- Verify monitoring tools can still scrape metrics
- Verify rolling updates work without connectivity loss
- Enable CNI audit logging and review dropped traffic

#### Document

- Document the communication topology (which pod talks to which)
- Document why each policy exists
- Include the DNS egress rule in your namespace template
- Add NetworkPolicy requirements to your namespace bootstrapping

### Cross-Reference

| Related Topic            | Link                                                             |
| ------------------------ | ---------------------------------------------------------------- |
| Security Context (L0/L1) | `[[Kubernetes/concepts/L07-security/05-security-context]]`       |
| Pod Security Standards   | `[[Kubernetes/concepts/L07-security/02-pod-security-standards]]` |
| Service Mesh (L7)        | `[[Kubernetes/concepts/networking/06-service-mesh]]`             |
| DNS in Kubernetes        | `[[Kubernetes/concepts/networking/04-dns]]`                      |
| Calico NetworkPolicy     | `[[Kubernetes/concepts/networking/cni-calico]]`                  |
| Cilium NetworkPolicy     | `[[Kubernetes/concepts/networking/cni-cilium]]`                  |

==**Services do not come into the picture at all.**== This is one of the most common mental traps in Kubernetes. NetworkPolicies **completely ignore Services**—they look right through them and apply rules directly to the underlying **Pods** via their IP addresses.

Here is a breakdown of how this works architecturally, why it behaves this way, and the critical "gotchas" this causes in production.

---

## 1. The Architecture: DNAT Happens First

To understand why NetworkPolicies ignore Services, you have to look at how a packet travels through Kubernetes:

1. **The Request:** Pod A sends a packet to a Service's ClusterIP (e.g., `10.96.0.10:80`).
    
2. **The Translation (kube-proxy):** Before the packet even leaves the Node or hits the network wire, `kube-proxy` (using iptables or IPVS) intercepts it. It performs **DNAT** (Destination Network Address Translation), swapping out the Service's ClusterIP for the actual IP of a target Pod (e.g., `10.244.1.45:8080`).
    
3. **The Enforcement (CNI):** The CNI network plugin evaluates your NetworkPolicy **after** this translation has already occurred.
    

Because the packet's destination has already been rewritten to a Pod IP by the time the CNI sees it, the NetworkPolicy engine only cares about Pod labels, not Service names or Service IPs.

---

## 2. What Happens if You Try to Target a Service?

If you try to write a NetworkPolicy to allow traffic to or from a Service, **it will fail or be silently ignored**.

### 🚫 The Mistake: Trying to match a Service Name or Label

YAML

```
# THIS DOES NOT WORK
ingress:
- from:
  - podSelector:
      matchLabels:
        kubernetes.io/service-name: my-frontend-service # ❌ Services don't have Pod labels
```

### ✅ The Solution: Target the Pod Backends Directly

You must always look at the `spec.selector` inside your Service YAML, and copy those exact labels into your NetworkPolicy `podSelector`.

YAML

```
# If your Service looks like this:
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
spec:
  selector:
    app: backend-api # 👈 COPY THIS
  ports:
  - port: 80
    targetPort: 8080 # 👈 AND USE THIS PORT
```

YAML

```
# Your NetworkPolicy must look like this:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      app: backend-api #  Targeting the backend pods directly
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080 #  Must use the container's TARGET port, NOT the service port!
```

---

## 3. Crucial "Service" Gotchas to Memorize

### Gotcha #1: Use `targetPort`, Not `port`

As shown in the example above, if your Service exposes port `80` but maps it to a container port of `8080` (`targetPort`), your NetworkPolicy **must whitelist port 8080**. If you whitelist port 80, the traffic will be blocked because the CNI evaluates the packet _after_ it has been translated to the container's actual listening port.

### Gotcha #2: The Hairpin / Loopback Block

If a Pod tries to communicate with _itself_ or another Pod in its own deployment by hitting its own Service's ClusterIP, that traffic goes out to the network fabric and comes back in. If you have a strict `Default-Deny` Ingress policy on that Pod, it will **block its own traffic** unless you explicitly allow the Pod to talk to itself.

### Gotcha #3: CoreDNS is a Service, too!

When you write an Egress policy to allow DNS, you usually target the `kube-system` namespace. You don't target the `kube-dns` Service IP. You target the CoreDNS _Pods_. Because CoreDNS scales up and down, your Egress rule allows traffic to the entire `kube-system` namespace on port 53, ensuring that no matter which CoreDNS Pod `kube-proxy` routes the packet to, the CNI will let it pass.