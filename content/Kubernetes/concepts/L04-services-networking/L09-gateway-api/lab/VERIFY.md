# Verify — One-Liner Smoke Tests for Every Scenario

These are the `curl` invocations that prove each scenario works. Re-runnable.
Assumes you ran `./install.sh` and the kind nodeport mapping (host:80 → 30000, host:443 → 30001).

> **The Host header is doing the work.** The Gateway uses hostname-based routing. `127.0.0.1` is fine because we're hitting the kind nodeport; the Host header is what selects the route.

## Baseline (always available after install.sh)

```bash
# The smoke test (deploys an httpbin)
curl -i -H "Host: smoke.example.com" http://127.0.0.1/get
# expect 200
```

## 01 — Minimal HTTP

```bash
kubectl apply -f scenarios/01-minimal-http.yaml
sleep 2
curl -i -H "Host: minimal.example.com" http://127.0.0.1/
# expect 200, body from echo
```

## 02 — Multiple hostnames

```bash
kubectl apply -f scenarios/02-multi-host.yaml
sleep 2
curl -s -H "Host: app1.example.com" http://127.0.0.1/ | grep -oE 'this is app[12]'
curl -s -H "Host: app2.example.com" http://127.0.0.1/ | grep -oE 'this is app[12]'
# first call returns "this is app1", second "this is app2"
```

## 03 — Path routing

```bash
kubectl apply -f scenarios/03-path-routing.yaml
sleep 2
curl -s -H "Host: paths.example.com" http://127.0.0.1/api/v1/headers
# body from api-v1
curl -s -H "Host: paths.example.com" http://127.0.0.1/api/v2/headers
# body from api-v2
```

## 04 — Header routing

```bash
kubectl apply -f scenarios/04-header-routing.yaml
sleep 2
curl -s -H "Host: header.example.com" -H "X-Version: v2" http://127.0.0.1/ | grep '"v[12]"'
# expect "v2"
curl -s -H "Host: header.example.com" http://127.0.0.1/ | grep '"v[12]"'
# expect "v1"
```

## 05 — Traffic split

```bash
kubectl apply -f scenarios/05-traffic-split.yaml
sleep 2
for i in $(seq 1 40); do
  curl -s -H "Host: canary.example.com" http://127.0.0.1/ | grep -oE 'v[12]' | head -1
done | sort | uniq -c
# expect ~36 v1 and ~4 v2 (90/10 split, ±2)
```

## 06 — Redirect and URL rewrite

```bash
kubectl apply -f scenarios/06-redirect-rewrite.yaml
sleep 2
# 308 redirect
curl -sS -o /dev/null -w "%{http_code} -> %{redirect_url}\n" \
  -H "Host: rewrites.example.com" http://127.0.0.1/old/path
# expect: 308 -> http://rewrites.example.com/new/path/
# 200 (silent rewrite)
curl -i -H "Host: rewrites.example.com" http://127.0.0.1/legacy/api/v1
# expect: 200
```

## 07 — Header filter

```bash
kubectl apply -f scenarios/07-header-filter.yaml
sleep 2
curl -sS -D - -H "Host: headers.example.com" -H "X-Internal: secret" \
  http://127.0.0.1/headers -o /tmp/body
# Look in /tmp/body for:
#   "X-Routed-By": "envoy-gateway"  (added)
#   "X-Internal": ""                (removed before upstream)
# In response headers:
#   X-Gateway-Version: v1.4.0
```

## 08 — TLS edge

```bash
kubectl apply -f scenarios/08-tls-edge.yaml
# Wait for the cert to be issued (cert-manager):
kubectl wait --for=condition=Ready -n infra certificate/edge-cert --timeout=60s
# (also need to patch the NodePort or use a separate service. See scenario 08 yaml.)
# If 08 applied cleanly, the eg-tls-nodeport service is on host:443.

curl -k --resolve edge.example.com:443:127.0.0.1 https://edge.example.com/ -i
# expect 200, body "edge: ok"
# Inspect cert:
openssl s_client -connect 127.0.0.1:443 -servername edge.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

## 09 — TLS passthrough

```bash
kubectl apply -f scenarios/09-tls-passthrough.yaml
# (Cert-manager reuses selfsigned issuer. Wait for backend cert.)
kubectl wait --for=condition=Ready -n app certificate/passthrough-backend-cert --timeout=60s

curl -k --resolve passthrough.example.com:443:127.0.0.1 https://passthrough.example.com/ -i
# expect 200, "passthrough backend: ok"
```

## 10 — TLS re-encrypt + BackendTLSPolicy

```bash
kubectl apply -f scenarios/10-tls-reencrypt.yaml
# Certs and ConfigMap pre-populated.
# IMPORTANT: The `reencrypt-ca` ConfigMap ships with a placeholder.
# Replace it with the actual CA cert from cert-manager:
kubectl get secret reencrypt-backend-tls -n app -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ca.crt
# Or, simpler, use wellKnownCACertificates: SystemTrustStore.
# Then re-edit scenario 10 to drop the caCertificateRefs and trust the public chain.

# When configured correctly:
curl -k --resolve reencrypt.example.com:443:127.0.0.1 https://reencrypt.example.com/ -i
# expect 200, "reencrypt backend: ok"
```

## 11 — Cross-namespace + ReferenceGrant

```bash
kubectl apply -f scenarios/11-cross-ns.yaml
sleep 2

# Before the ReferenceGrant was added, this would have shown RefNotPermitted.
# Confirm it's fixed:
kubectl get httproute xroute -n app-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'
# expect: True

curl -i -H "Host: cross.example.com" http://127.0.0.1/
# expect 200, "shared-api (app-b)"
```

## 12 — CORS + JWT

```bash
kubectl apply -f scenarios/12-cors-jwt.yaml
sleep 2

# Preflight
curl -i -X OPTIONS \
  -H "Host: secure.example.com" \
  -H "Origin: https://app.example.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: authorization,content-type" \
  http://127.0.0.1/
# expect 200 with Access-Control-Allow-* headers

# No JWT -> 401
curl -i -H "Host: secure.example.com" http://127.0.0.1/
# expect 401

# Valid JWT -> 200
TOKEN="<your-jwt-signed-by-jwks-uri>"
curl -i -H "Host: secure.example.com" -H "Authorization: Bearer $TOKEN" http://127.0.0.1/
# expect 200
```

## 13 — Local rate limit

```bash
kubectl apply -f scenarios/13-rate-limit.yaml
sleep 2

for i in $(seq 1 15); do
  curl -sS -o /dev/null -w "%{http_code}\n" -H "Host: rate.example.com" http://127.0.0.1/
done
# expect ~10 "200" and ~5 "429"
```

## 14 — External auth (ext_authz)

```bash
kubectl apply -f scenarios/14-external-auth.yaml
sleep 2

# Authz service is mocked with http-https-echo. Always returns 200.
# In real life, point extAuth.http.path to your OPA/cerbos service.
curl -i -H "Host: extauth.example.com" http://127.0.0.1/
# expect 200
```

## 15 — Multi-listener (HTTP+HTTPS, redirect 80→443)

```bash
kubectl apply -f scenarios/15-multi-listener.yaml
kubectl wait --for=condition=Ready -n infra certificate/dual-cert --timeout=60s
sleep 2

# HTTP -> 308 to HTTPS
curl -sS -o /dev/null -w "%{http_code} -> %{redirect_url}\n" \
  -H "Host: dual.example.com" http://127.0.0.1/
# expect: 308 -> https://dual.example.com/

# HTTPS -> 200
curl -k --resolve dual.example.com:443:127.0.0.1 https://dual.example.com/ -i
# expect 200
```

## 16 — Gateway merging

```bash
# Pre-req: opt in to merging on the GatewayClass
kubectl label gatewayclass eg gateway.envoyproxy.io/merge=true --overwrite

kubectl apply -f scenarios/16-gateway-merge.yaml
sleep 3

# Both routes should be Accepted on a single shared data plane
kubectl get httproute tenant-a-route tenant-b-route -n app
# expect both with Accepted=True

curl -i -H "Host: tenant-a.example.com" http://127.0.0.1/
# expect 200, "tenant-a"
curl -i -H "Host: tenant-b.example.com" http://127.0.0.1/
# expect 200, "tenant-b"

# Confirm shared data plane:
kubectl get deploy -n infra -l gateway.envoyproxy.io/owning-gateway-name
# expect 2 entries, but only one envoy proxy pod is created per merged listener
```

---

## Cleanup (per scenario)

```bash
# Remove a single scenario
kubectl delete -f scenarios/01-minimal-http.yaml

# Wipe the cluster entirely
./cleanup.sh
```

## Troubleshooting quick reference

| Symptom | First check |
|---------|-------------|
| `kubectl apply` hangs | `kubectl get validatingwebhookconfigurations` — webhook reachable? |
| `curl` returns 503 | `kubectl get endpoints -n app <svc>` — pods ready? |
| Route `Accepted=False, NoMatchingParent` | Hostname on route doesn't intersect listener |
| `ResolvedRefs=False, RefNotPermitted` | Add `ReferenceGrant` in target namespace |
| `curl -k` works but `curl` (no `-k`) fails | Cert SANs don't include the Host header |
| `curl: (35) TLS handshake error` | Cert not yet ready, or `tls.certificateRefs` wrong Secret |
| TLS passthrough returns 502 | Backend not serving on the same port as `backendRefs.port` |
| Re-encrypt: gateway rejects backend | `BackendTLSPolicy` CA doesn't sign the backend cert |
| Rate limit returns 429 unexpectedly | Check `clientSelectors` — `sourceIP` doesn't work behind NAT/LB |
| `kubectl get gateway` shows `Conflicted` | Two listeners in same Gateway share port+protocol |
