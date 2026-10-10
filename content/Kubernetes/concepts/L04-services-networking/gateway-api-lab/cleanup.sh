#!/usr/bin/env bash
# cleanup.sh — tear down the Gateway API / Envoy Gateway lab
#
# Removes the kind cluster entirely. Re-run install.sh to start fresh.

set -euo pipefail
KIND_CLUSTER="gw-lab"

C_BOLD="\033[1m"
C_OK="\033[32m"
C_WARN="\033[33m"
C_RST="\033[0m"
log()  { echo -e "${C_BOLD}>>>${C_RST} $*"; }
ok()   { echo -e "${C_OK}  ✓${C_RST} $*"; }
warn() { echo -e "${C_WARN}  !${C_RST} $*"; }

if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
  log "Deleting kind cluster '${KIND_CLUSTER}'"
  kind delete cluster --name "${KIND_CLUSTER}"
  ok "cluster removed"
else
  warn "cluster '${KIND_CLUSTER}' does not exist — nothing to do"
fi

log "Optional: remove helm repo"
helm repo remove gateway-helm 2>/dev/null || true
ok "done"
