# Plan: Gateway API In-Depth Research & Envoy Gateway Implementation — **DONE**

**Owner:** Mavis (root session)
**Status:** All deliverables shipped. Sandbox cannot run kind; manifest + script validation done in-sandbox; live run is on you.

---

## 1. Final Deliverable Tree

```
/workspace/
├── plans/
│   └── gateway-api-envoy-gateway-plan.md      # this file
├── research/
│   ├── gateway-api.md                          # spec, resources, roles, conformance, Ingress diff, gotchas
│   └── envoy-gateway.md                        # architecture, helm values, feature matrix, ops
└── lab/
    ├── install.sh                              # one-command bootstrap
    ├── cleanup.sh                              # teardown
    ├── RUNBOOK.md                              # day-2 ops + troubleshooting + prod checklist
    ├── VERIFY.md                               # curl one-liners for every scenario
    └── scenarios/
        ├── 01-minimal-http.yaml
        ├── 02-multi-host.yaml
        ├── 03-path-routing.yaml
        ├── 04-header-routing.yaml
        ├── 05-traffic-split.yaml
        ├── 06-redirect-rewrite.yaml
        ├── 07-header-filter.yaml
        ├── 08-tls-edge.yaml
        ├── 09-tls-passthrough.yaml
        ├── 10-tls-reencrypt.yaml
        ├── 11-cross-ns.yaml
        ├── 12-cors-jwt.yaml
        ├── 13-rate-limit.yaml
        ├── 14-external-auth.yaml
        ├── 15-multi-listener.yaml
        └── 16-gateway-merge.yaml
```

---

## 2. What Got Built

### Research (long-form Markdown)

- **`research/gateway-api.md`** (~16 KB) — Why Gateway API exists, full resource model, conformance profiles, role/persona separation, route attachment, `ReferenceGrant`, `BackendTLSPolicy`, cert management, channel packaging, gateway merging, status/conditions, **full diff table vs Ingress**, common pitfalls, GAMMA/MCG/future pointers.
- **`research/envoy-gateway.md`** (~13 KB) — Architecture diagram, comparison with alternatives (NGINX, Traefik, HAProxy, Cilium, Istio, Kong), release model, supported features, Helm values, **security defaults**, `EnvoyProxy` CRD for break-glass, operations (admin port, metrics, logs, xDS, upgrades), spec-vs-extension decision table, troubleshooting map.

### Lab (runnable)

- **`lab/install.sh`** — Pre-flight checks → kind cluster (1 control + 2 workers, host ports 80/443/19000 mapped) → Gateway API CRDs (v1.2.1 standard) → cert-manager (v1.16.2) → Envoy Gateway (v1.4.0) via Helm → wait for GatewayClass Accepted → create `infra`/`app`/`app-a`/`app-b` namespaces → apply a baseline `Gateway` + smoke `HTTPRoute` → curl smoke test.
- **`lab/cleanup.sh`** — Wipes the kind cluster.
- **`lab/RUNBOOK.md`** — Day-2 operations: bring-up, apply scenarios, daily checks, debug a request, upgrades, teardown, troubleshooting recipes, **production checklist** (15 items), references.
- **`lab/VERIFY.md`** — Re-runnable `curl` invocations for every scenario, with expected outputs.

### 16 Scenarios (numbered, ordered)

| # | Demonstrates | File |
|---|---|---|
| 01 | Minimal HTTP | `01-minimal-http.yaml` |
| 02 | Multiple hostnames | `02-multi-host.yaml` |
| 03 | Path-based routing | `03-path-routing.yaml` |
| 04 | Header-based routing (A/B) | `04-header-routing.yaml` |
| 05 | Traffic split / canary (90/10) | `05-traffic-split.yaml` |
| 06 | `RequestRedirect` + `URLRewrite` | `06-redirect-rewrite.yaml` |
| 07 | Request/response header filters | `07-header-filter.yaml` |
| 08 | TLS edge (cert-manager + `mode: Terminate`) | `08-tls-edge.yaml` |
| 09 | TLS passthrough (`TLSRoute`, SNI) | `09-tls-passthrough.yaml` |
| 10 | TLS re-encrypt + `BackendTLSPolicy` (mTLS) | `10-tls-reencrypt.yaml` |
| 11 | Cross-namespace + `ReferenceGrant` | `11-cross-ns.yaml` |
| 12 | CORS + JWT (`SecurityPolicy`) | `12-cors-jwt.yaml` |
| 13 | Local rate limit | `13-rate-limit.yaml` |
| 14 | External auth (`extAuthz`) | `14-external-auth.yaml` |
| 15 | Multi-listener (HTTP+HTTPS with 80→443 redirect) | `15-multi-listener.yaml` |
| 16 | Gateway merging (shared data plane) | `16-gateway-merge.yaml` |

### Coverage of Your Asks

| You asked for | Covered by |
|---|---|
| Gateway API in depth | `research/gateway-api.md` (14 sections) + `research/envoy-gateway.md` (11 sections) |
| Implementation with Envoy Gateway | 16 scenario manifests + `install.sh` + `RUNBOOK.md` |
| All possible scenarios | 16 scenarios covering HTTP, multi-host, path, header, traffic split, filters, TLS (3 modes), cross-ns, auth (JWT/OIDC/extAuthz), rate limit, CORS, multi-listener, gateway merging |
| Diffs with Ingress | Full diff table in `research/gateway-api.md` §12; recommendation in `research/envoy-gateway.md` §3 |
| Installation methods | `lab/install.sh` (Helm — the canonical path); `research/envoy-gateway.md` §6 covers the chart + key values; RUNBOOK §5 covers upgrades |
| ClusterIP gotchas | `research/gateway-api.md` §13 item 4; RUNBOOK §7.3; research/gateway-api.md §5.2-5.4 covers route attachment mechanics; clusterip specifics called out in plan and RUNBOOK troubleshooting |
| TLS gotchas | `research/gateway-api.md` §8 (cert manager, rotation, SANs, intermediate certs, mTLS via BackendTLSPolicy, edge vs passthrough vs re-encrypt); scenario 10 demonstrates re-encrypt + mTLS in practice; RUNBOOK §7.4 covers cert rotation issues |

---

## 3. Validation Status

Run in the cloud sandbox (no docker/kubectl available):

- ✅ `bash -n` on `install.sh` and `cleanup.sh` — both pass
- ✅ `python3 yaml.safe_load_all` on all 16 YAML files — all parse
- ✅ Structural sweep: 22 Deployments, 26 Services, 18 HTTPRoutes, 7 Gateways, 1 BackendTLSPolicy, 1 TLSRoute, 1 ReferenceGrant, 3 SecurityPolicies, 5 Certificates, 4 Issuers, 3 ConfigMaps
- ✅ Cross-checked: every HTTPRoute has `parentRefs` + `rules`; every Gateway has `gatewayClassName` + `listeners`; every `BackendTLSPolicy` has `targetRefs` + `tls`; every `SecurityPolicy` has `targetRefs`
- ❌ Live `kind apply` — sandbox has no docker. The user runs `install.sh` on a machine with docker.

When you run `install.sh` on your machine, the first failure you'd likely hit is **scenario 10** — I left a placeholder in the `reencrypt-ca` ConfigMap because injecting a real CA requires running cert-manager first. The `VERIFY.md` notes this and tells you how to fix it (two-line kubectl).

---

## 4. Key Decisions (locked)

- **Gateway API channel:** `standard` (no alpha features unless absolutely needed)
- **EG version:** `v1.4.0` (latest stable as of plan)
- **Install method:** Helm (chart `gateway-helm/gateway-helm` from `gateway-helm` repo)
- **Data plane:** `Deployment` (not `DaemonSet`) by default
- **Cert manager:** `cert-manager` v1.16+ (already v1.16.2 in install.sh)
- **Auth/CORS/rate-limit/authz:** EG `SecurityPolicy` extension (not in spec, but stable and pragmatic)
- **BackendTLSPolicy:** used in spec (re-encrypt scenario)
- **Local lab:** `kind` (more representative than k3d/minikube)
- **Migration from ingress-nginx:** documented in `research/envoy-gateway.md` §3 — recommended successor is EG

---

## 5. Open Items / Future Work

These are NOT blockers but worth knowing:

1. **Scenario 10's CA cert** — needs the live cert-manager to populate. The placeholder is intentional and `VERIFY.md` tells you the two-line fix.
2. **Global rate limit (Redis)** — install.sh doesn't enable the `envoy-ratelimit` subchart by default. Local rate limit (per-proxy) is what scenario 13 demonstrates. Adding global would be a one-line Helm value change plus a Redis dependency.
3. **Production hardening** — `RUNBOOK.md` §8 has the checklist but the lab is not production-grade. You'll add PDBs, NetworkPolicy, real OTel, etc. on your own.
4. **GAMMA (mesh) / Multi-cluster Gateway** — not in scope, mentioned in research docs.
5. **Live-validate the manifests against the actual installed CRDs** — only possible by running `install.sh` on a machine with docker.

---

## 6. How to Use This

1. **Read the research first.** Start with `research/gateway-api.md` if you want the conceptual model, or `research/envoy-gateway.md` if you're more interested in the implementation.
2. **Bring up the lab.** `cd lab && ./install.sh` — about 5 minutes from a fresh machine.
3. **Run scenarios 01–05** to get the model in your head. `VERIFY.md` tells you what to curl.
4. **TLS scenarios (08–10)** are the most "production-relevant" — spend time there.
5. **11 (cross-ns) and 12–14 (auth/CORS/rate-limit/extAuthz)** are the day-2 features you'll use most.
6. **15 (multi-listener) and 16 (gateway merging)** are infrastructure patterns — read them once, then look them up as needed.
7. **Use RUNBOOK.md** for any operational issue.

---

## 7. Next Step

Run `./install.sh` on a machine with `docker`, `kind`, `kubectl`, and `helm`. If a scenario fails, paste the error and I'll fix the manifest.

If you want a different starting point — e.g., "give me the prod-ready Helm values, not the lab" or "build me a Grafana dashboard for the data plane" — say the word and I'll cut a new track.
