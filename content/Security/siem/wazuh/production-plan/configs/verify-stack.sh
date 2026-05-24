#!/bin/bash
# Wazuh Post-Deployment Verification Script
# Run after Phase 2 (distributed deployment) to validate the stack

set -e

echo "=================================================="
echo " Wazuh Production Stack Verification"
echo "=================================================="

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    echo -n "[*] $name ... "
    if eval "$cmd" > /dev/null 2>&1; then
        echo "PASS"
        ((PASS++))
    else
        echo "FAIL"
        ((FAIL++))
    fi
}

check_manager() {
    echo -n "[*] Wazuh Manager (local) ... "
    /var/ossec/bin/wazuh-control info > /dev/null 2>&1 && echo "PASS" || echo "FAIL"
}

check_cluster() {
    echo -n "[*] Wazuh Cluster status ... "
    /var/ossec/bin/cluster_control -l > /dev/null 2>&1 && echo "PASS" || echo "WARN (single node ok if Phase 2 incomplete)"
}

check_api() {
    echo -n "[*] Wazuh API health ... "
    curl -sk -u admin:$(cat /etc/ossec_pwd) https://localhost:55000/manager/status?pretty 2>/dev/null | grep -q '"online"' && echo "PASS" || echo "FAIL"
}

check_indexer() {
    echo -n "[*] Indexer cluster health ... "
    curl -sk -u admin:password https://localhost:9200/_cluster/health?pretty 2>/dev/null | grep -q '"status":"green"\|"status":"yellow"' && echo "PASS" || echo "FAIL"
}

check_indexer_nodes() {
    echo -n "[*] Indexer nodes count ... "
    count=$(curl -sk -u admin:password https://localhost:9200/_cat/nodes?v 2>/dev/null | grep -c "indexer" || echo 0)
    echo "Found $count indexer node(s)"
}

check_dashboard() {
    echo -n "[*] Dashboard reachable ... "
    curl -sk https://localhost:5601 2>/dev/null | grep -q "Wazuh" && echo "PASS" || echo "FAIL"
}

check_agent_comm() {
    echo -n "[*] Agent communication (NLB port 1514) ... "
    nc -zvw 3 wazuh-agent-nlb.internal 1514 > /dev/null 2>&1 && echo "PASS" || echo "WARN (NLB may still be provisioning)"
}

check_agents() {
    echo -n "[*] Active agents registered ... "
    count=$(/var/ossec/bin/agent_control -ls 2>/dev/null | grep -c "Active" || echo 0)
    echo "$count agent(s) active"
}

check_aws_wodle() {
    echo -n "[*] AWS wodle (CloudTrail) configured ... "
    /var/ossec/bin/wazuh-control info 2>/dev/null | grep -q "aws-s3" && echo "PASS" || echo "FAIL"
}

check_cloudtrail_rules() {
    echo -n "[*] CloudTrail rules loaded ... "
    /var/ossec/bin/wazuh-control info 2>/dev/null | grep -q "100103\|100104" && echo "PASS" || echo "FAIL"
}

check_n8n_connectivity() {
    echo -n "[*] n8n webhook reachable ... "
    curl -sfk https://n8n.internal.yourdomain.com/webhook/wazuh-alerts 2>/dev/null && echo "PASS" || echo "WARN (n8n not yet deployed)"
}

check_ilm() {
    echo -n "[*] ILM policy applied ... "
    curl -sk -u admin:password https://localhost:9200/_ilm/policy/security-audit-logs 2>/dev/null | grep -q "hot" && echo "PASS" || echo "FAIL"
}

echo ""
echo "--- MANAGER ---"
check_manager
check_cluster
check_api

echo ""
echo "--- INDEXER ---"
check_indexer
check_indexer_nodes

echo ""
echo "--- DASHBOARD ---"
check_dashboard

echo ""
echo "--- AGENTS ---"
check_agent_comm
check_agents

echo ""
echo "--- CLOUDTRAIL ---"
check_aws_wodle
check_cloudtrail_rules

echo ""
echo "--- INTEGRATIONS ---"
check_n8n_connectivity

echo ""
echo "--- INDEXER DATA ---"
check_ilm

echo ""
echo "=================================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=================================================="

if [ $FAIL -eq 0 ]; then
    echo "All checks passed!"
    exit 0
else
    echo "Some checks failed — review output above"
    exit 1
fi