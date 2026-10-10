#!/usr/bin/env bash
# install.sh — bootstrap Gateway API + Envoy Gateway lab on kind
#
# What it does:
#   1. Creates a kind cluster named "gw-lab" with 1 control-plane + 2 workers
#   2. Maps host ports 80/443/19000 to the cluster (for curl-based tests)
#   3. Installs Gateway API CRDs (standard channel) — MUST come before EG
#   4. Installs Envoy Gateway via Helm
#   5. Installs cert-manager (needed for scenarios 08+)
#   6. Waits for everything to be Ready
#   7. Applies a smoke-test Gateway + HTTPRoute and curls it
#
# Run:  ./install.sh
# Tear down: ./cleanup.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Config — pin these in production
# ---------------------------------------------------------------------------
KIND_CLUSTER="gw-lab"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.2.1}"
EG_CHART_VERSION="${EG_CHART_VERSION:-v1.4.0}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.2}"
EG_NAMESPACE="envoy-gateway-system"
CM_NAMESPACE="cert-manager"
APP_NAMESPACE="app"
INFRA_NAMESPACE="infra"

# Colors
C_BOLD="\033[1m"
C_OK="\033[32m"
C_WARN="\033[33m"
C_ERR="\033[31m"
C_RST="\033[0m"

log()   { echo -e "${C_BOLD}>>>${C_RST} $*"; }
ok()    { echo -e "${C_OK}  ✓${C_RST} $*"; }
warn()  { echo -e "${C_WARN}  !${C_RST} $*"; }
fail()  { echo -e "${C_ERR}  ✗${C_RST} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
log "Pre-flight checks"
for bin in docker kind kubectl helm; do
  command -v "$bin" >/dev/null 2>&1 || fail "missing: $bin"
done
ok "tools present: $(docker --version | awk '{print $1,$2}') / $(kind --version | awk '{print $1,$2}') / $(kubectl version --client -o yaml | grep -m1 gitVersion | awk '{print $2}') / $(helm version --short)"

# ---------------------------------------------------------------------------
# 1. kind cluster
# ---------------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
  warn "kind cluster '${KIND_CLUSTER}' already exists — reusing"
else
  log "Creating kind cluster '${KIND_CLUSTER}'"
  cat > /tmp/kind-config.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30000   # nodeport for HTTP
        hostPort: 80
        protocol: TCP
      - containerPort: 30001   # nodeport for HTTPS
        hostPort: 443
        protocol: TCP
      - containerPort: 30002   # nodeport for Envoy admin
        hostPort: 19000
        protocol: TCP
YAML
  kind create cluster --name "${KIND_CLUSTER}" --config /tmp/kind-config.yaml
  ok "kind cluster created"
fi

kubectl cluster-info >/dev/null
ok "kubectl can talk to the cluster"

# ---------------------------------------------------------------------------
# 2. Gateway API CRDs (MUST be before EG)
# ---------------------------------------------------------------------------
log "Installing Gateway API CRDs (${GATEWAY_API_VERSION}, standard channel)"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
ok "Gateway API CRDs applied"

# ---------------------------------------------------------------------------
# 3. cert-manager (for TLS scenarios)
# ---------------------------------------------------------------------------
log "Installing cert-manager ${CERT_MANAGER_VERSION}"
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml"
kubectl wait --for=condition=Available --timeout=120s \
  -n "${CM_NAMESPACE}" deployment/cert-manager-webhook
ok "cert-manager ready"

# ---------------------------------------------------------------------------
# 4. Envoy Gateway via Helm
# ---------------------------------------------------------------------------
log "Installing Envoy Gateway ${EG_CHART_VERSION} via Helm"
helm repo add gateway-helm https://gateway-helm.charts.gitops.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install eg gateway-helm/gateway-helm \
  --namespace "${EG_NAMESPACE}" \
  --create-namespace \
  --version "${EG_CHART_VERSION}" \
  --wait \
  --set "config.envoyGateway.gatewayControllerName=gateway.envoyproxy.io/gatewayclass-controller"
ok "Envoy Gateway installed"

# Wait for the controller to be ready
kubectl wait --for=condition=Available --timeout=120s \
  -n "${EG_NAMESPACE}" deployment/envoy-gateway
ok "Envoy Gateway controller ready"

# Wait for the default GatewayClass to be Accepted
log "Waiting for GatewayClass 'eg' to be Accepted"
for i in $(seq 1 30); do
  if kubectl get gatewayclass eg -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q True; then
    ok "GatewayClass 'eg' is Accepted"
    break
  fi
  sleep 2
done
kubectl get gatewayclass eg -o wide
kubectl get gatewayclass eg -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' | grep -q True \
  || fail "GatewayClass never became Accepted"

# ---------------------------------------------------------------------------
# 5. Namespaces
# ---------------------------------------------------------------------------
log "Creating lab namespaces: ${INFRA_NAMESPACE}, ${APP_NAMESPACE}, app-a, app-b"
for ns in "${INFRA_NAMESPACE}" "${APP_NAMESPACE}" app-a app-b; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done
ok "namespaces ready"

# ---------------------------------------------------------------------------
# 6. Bootstrap Gateway + smoke test
# ---------------------------------------------------------------------------
log "Applying baseline Gateway in '${INFRA_NAMESPACE}'"
cat > /tmp/baseline-gateway.yaml <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: ${INFRA_NAMESPACE}
  labels:
    app.kubernetes.io/name: eg-bootstrap
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
YAML
kubectl apply -f /tmp/baseline-gateway.yaml

log "Waiting for Gateway to be Programmed"
kubectl wait --for=condition=Programmed --timeout=120s \
  gateway/eg -n "${INFRA_NAMESPACE}"
ok "Gateway is Programmed"

# NodePort service for kind port mapping (so host:80 reaches gateway:80)
log "Exposing data plane via NodePort 30000 (host port 80)"
cat > /tmp/eg-nodeport.yaml <<YAML
apiVersion: v1
kind: Service
metadata:
  name: eg-nodeport
  namespace: ${INFRA_NAMESPACE}
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: eg-bootstrap
    gateway.envoyproxy.io/owning-gateway-name: eg
  ports:
  - name: http
    port: 80
    targetPort: 8080
    nodePort: 30000
  - name: https
    port: 443
    targetPort: 8443
    nodePort: 30001
  - name: admin
    port: 19000
    targetPort: 19000
    nodePort: 30002
YAML
kubectl apply -f /tmp/eg-nodeport.yaml
ok "NodePort service created"

# A tiny test app + HTTPRoute for the smoke test
log "Deploying smoke test app and HTTPRoute"
kubectl create deployment httpbin -n "${APP_NAMESPACE}" --image=mccutchen/go-httpbin --dry-run=client -o yaml | kubectl apply -f -
kubectl expose deployment httpbin -n "${APP_NAMESPACE}" --port=8080 --target-port=8080 --dry-run=client -o yaml | kubectl apply -f -
kubectl wait --for=condition=Available --timeout=60s deployment/httpbin -n "${APP_NAMESPACE}"

cat > /tmp/smoke-route.yaml <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: smoke
  namespace: ${APP_NAMESPACE}
spec:
  parentRefs:
  - name: eg
    namespace: ${INFRA_NAMESPACE}
  hostnames: ["smoke.example.com"]
  rules:
  - matches:
    - path: { type: PathPrefix, value: / }
    backendRefs:
    - name: httpbin
      port: 8080
YAML
kubectl apply -f /tmp/smoke-route.yaml
kubectl wait --for=condition=Accepted --timeout=60s httproute/smoke -n "${APP_NAMESPACE}"
ok "HTTPRoute accepted"

# ---------------------------------------------------------------------------
# 7. Curl smoke test
# ---------------------------------------------------------------------------
log "Smoke test: GET http://localhost/ on the kind nodeport"
sleep 3  # give the proxy a moment to pick up the route
RESP=$(curl -sS -o /tmp/smoke.body -w "%{http_code}" \
  -H "Host: smoke.example.com" \
  http://127.0.0.1/headers)
if [ "$RESP" = "200" ]; then
  ok "smoke test passed (HTTP $RESP)"
  echo "  response excerpt:"
  head -c 400 /tmp/smoke.body | sed 's/^/    /'
else
  warn "smoke test returned $RESP — check the gateway and route"
  head -c 400 /tmp/smoke.body | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
cat <<EOF

${C_BOLD}Lab is up.${C_RST}

  Cluster:        ${KIND_CLUSTER}
  EG version:     ${EG_CHART_VERSION}
  Gateway API:    ${GATEWAY_API_VERSION}
  cert-manager:   v${CERT_MANAGER_VERSION}

  Namespaces:     ${INFRA_NAMESPACE}, ${APP_NAMESPACE}
  Gateway:        ${INFRA_NAMESPACE}/eg
  Smoke route:    ${APP_NAMESPACE}/smoke → httpbin:8080
  NodePort map:   host:80 → gw:8080 (HTTP)
                  host:443 → gw:8443 (HTTPS, used by TLS scenarios)
                  host:19000 → gw:19000 (Envoy admin)

  Verify:         curl -H 'Host: smoke.example.com' http://127.0.0.1/headers
  Apply scenario: kubectl apply -f lab/scenarios/0N-*.yaml
  Cleanup:        ./cleanup.sh
EOF
