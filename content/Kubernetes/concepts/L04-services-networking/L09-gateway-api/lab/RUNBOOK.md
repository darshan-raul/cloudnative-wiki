# RUNBOOK — Operations

This is the day-2 playbook for the lab / a real cluster. After install.sh, you'll be doing these operations regularly.

---

## 0. Sandbox Note

This lab was authored in a cloud sandbox without `docker`/`kind`/`kubectl`/`helm`. We **validated** the manifests with:
- `bash -n` on every shell script
- `python3 -c "yaml.safe_load_all(...)"` on every YAML file
- A structural sweep verifying every HTTPRoute has `parentRefs` + `rules`, every Gateway has `gatewayClassName` + `listeners`, etc.

**Final validation — running it for real — happens on your machine.** Follow `install.sh` to bring up the cluster; if anything breaks, the failures will surface in the `curl` invocations from `VERIFY.md`.

---

## 1. Bring up the lab

```bash
cd lab
./install.sh
```

Expected output: a kind cluster `gw-lab` with EG controller + data plane, a smoke-test `HTTPRoute`, and a 200 from `curl -H 'Host: smoke.example.com' http://127.0.0.1/`.

If install hangs on `kubectl wait ... --for=condition=Available`, jump to troubleshooting §7.

---

## 2. Apply scenarios

```bash
# Core
for f in scenarios/01-*.yaml scenarios/02-*.yaml scenarios/03-*.yaml; do
  kubectl apply -f "$f"
done

# TLS (needs cert-manager; bundled in install.sh)
kubectl apply -f scenarios/08-tls-edge.yaml
# Wait for cert
kubectl wait --for=condition=Ready -n infra certificate/edge-cert --timeout=60s
```

Every `kubectl apply` is idempotent — running it twice is a no-op.

---

## 3. Daily checks

```bash
# Are my Gateways programmed?
kubectl get gateway -A

# Are my routes accepted?
kubectl get httproute -A

# Any RefNotPermitted?
kubectl get httproute -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{": "}{.status.parents[*].conditions[?(@.type=="ResolvedRefs")].reason}{"\n"}{end}'

# Any unprogrammed Gateway?
kubectl get gateway -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{": "}{.status.conditions[?(@.type=="Programmed")].status}{" "}{.status.conditions[?(@.type=="Programmed")].reason}{"\n"}{end}'
```

The two commands above are the ones I run on every shift.

---

## 4. Debugging a specific request

```bash
# 1. Did the route bind?
kubectl describe httproute <name> -n <ns>

# 2. What does the data plane think?
kubectl port-forward -n infra svc/<gateway>-<hash> 19000:19000
# OR for the standard EG labeling:
kubectl get deploy -n infra -l gateway.envoyproxy.io/owning-gateway-name
# Pick the data plane pod, port-forward
kubectl port-forward -n infra <pod> 19000:19000

# 3. Once port-forwarded:
curl -s http://localhost:19000/ready
curl -s http://localhost:19000/config_dump | jq '.configs[1].dynamic_route_configs' | head -200
curl -s http://localhost:19000/clusters | grep -E 'httpbin|edge-target'
curl -s http://localhost:19000/stats | head
```

---

## 5. Upgrades

```bash
# Bump the chart version
helm upgrade eg gateway-helm/gateway-helm \
  --namespace envoy-gateway-system \
  --version v1.5.0 \
  --reuse-values

# Watch the rollout
kubectl rollout status deployment/envoy-gateway -n envoy-gateway-system

# The data plane restarts on xDS schema change. Watch the proxy:
kubectl get pods -n infra -l gateway.envoyproxy.io/owning-gateway-name
```

For a real prod cluster, do this in a canary first — duplicate the `GatewayClass` to a `eg-canary` class, point a canary Gateway at it, verify, then promote.

---

## 6. Teardown

```bash
# Per scenario
kubectl delete -f scenarios/12-cors-jwt.yaml

# Full wipe
./cleanup.sh
```

`cleanup.sh` removes the kind cluster but **not** your downloaded images. To prune:

```bash
docker system prune -a
```

---

## 7. Troubleshooting recipes

### 7.1 `kubectl apply` hangs

The Envoy Gateway admission webhook isn't reachable. Check:

```bash
kubectl get validatingwebhookconfigurations | grep envoy
kubectl get svc -n envoy-gateway-system envoy-gateway
# The webhook should listen on :443
# If you're on kind, this works out of the box. If on a remote cluster, check NetworkPolicy.
```

### 7.2 `kubectl get gateway` shows `Programmed=False, Invalid`

```bash
kubectl describe gateway <name> -n <ns>
# Look at .status.conditions[*].message
```

Common:
- `OverlappingTLSConfig` → two HTTPS listeners sharing the same port+hostname
- `RefNotPermitted` → ReferenceGrant missing
- `InvalidCertificate` → Secret is not `kubernetes.io/tls` type

### 7.3 `curl` returns 503

```bash
kubectl get endpoints -n app <svc>
# If empty, your pod isn't Ready.
kubectl describe pod -n app -l app=<label>
# Common: image pull error, liveness probe failing, OOMKilled.
```

### 7.4 `curl -k https://...` fails with `connection reset`

EG hasn't picked up the cert yet. cert-manager is async:

```bash
kubectl get certificate -A
kubectl describe certificate <name> -n <ns>
```

If the cert is `Ready=False` for more than a minute, check the Issuer's `kubectl describe`.

### 7.5 429s when you didn't expect them

Local rate limit triggers. Check `SecurityPolicy.rateLimit` and adjust. Local rate limit is per-proxy — if you have multiple replicas, **each** counts the limit independently. For cluster-wide limits, use the `envoy-ratelimit` subchart with Redis.

### 7.6 `RefNotPermitted` on a cross-namespace route

`ReferenceGrant` missing or in the wrong namespace. The grant must be in the **target** namespace (the one that owns the Service / Secret being referenced).

```bash
kubectl get referencegrant -A
# Should have a grant for the route's namespace + resource
```

### 7.7 Re-encrypt fails with `TLS error: 268435581`

EG can't verify the upstream cert. Check:
- The `caCertificateRefs` ConfigMap contains a valid PEM
- The upstream's cert SAN matches `BackendTLSPolicy.spec.tls.hostname`
- The upstream's cert is signed by the CA in the ConfigMap, not just any cert

---

## 8. Production checklist (beyond the lab)

- [ ] Pin EG chart and Gateway API version (no `latest`)
- [ ] Resource limits on controller and data plane
- [ ] Prometheus scrape on `:19001`
- [ ] Access logs to a central store
- [ ] Tracing to a central store
- [ ] PodDisruptionBudgets for data plane
- [ ] NetworkPolicy: only API server → controller `:443`; only Gateway pod → upstreams
- [ ] PodSecurity `restricted` namespace labels
- [ ] cert-manager in HA mode (2 replicas)
- [ ] Cert renewal tested (set TTL to 30d, force-renew, observe hot-reload)
- [ ] Pod anti-affinity on data plane (one per node)
- [ ] `topologySpreadConstraints` for multi-AZ
- [ ] HPA on data plane (if using `Deployment`)
- [ ] Backup of `GatewayClass`, `Gateway`, `HTTPRoute` via GitOps (Argo CD/Flux)
- [ ] DR plan: how do clients reach a different region if this one goes down?

---

## 9. Reference

- Gateway API spec: https://gateway-api.sigs.k8s.io
- Envoy Gateway docs: https://gateway.envoyproxy.io
- Conformance matrix: https://gateway-api.sigs.k8s.io/conformance
- cert-manager: https://cert-manager.io
- Migration from ingress-nginx: https://kubernetes.github.io/ingress-nginx/user-guide/migration/
