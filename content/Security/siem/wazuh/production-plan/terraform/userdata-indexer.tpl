#!/bin/bash
# Wazuh Indexer Userdata — Amazon Linux 2023
# First boot: install Wazuh indexer, apply TLS certs, join cluster

set -e

WAZUH_INDEXER_VERSION="4.12.0"
NODE_NUMBER="${node_number}"
NODE_NAME="${node_name}"
CLUSTER_HOSTS="${cluster_hosts}"

# Install Wazuh Indexer
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /etc/pki/rpm-gpg/RPM-GPG-KEY-WAZUH
echo "[wazuh]
name=Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-WAZUH" > /etc/yum.repos.d/wazuh.repo

yum install -y wazuh-indexer-${WAZUH_INDEXER_VERSION}

# Generate TLS certificates (in production, copy pre-generated certs)
mkdir -p /etc/wazuh-indexer/certs
chown wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs

# =====================
# Production config — see configs/opensearch.yml
# Copy your pre-generated certs here:
#   /etc/wazuh-indexer/certs/indexer-nodeX.crt
#   /etc/wazuh-indexer/certs/indexer-nodeX.key
#   /etc/wazuh-indexer/certs/root-ca.crt
# =====================

# Apply node-specific opensearch.yml (replace via cloud-init or SSM Parameter Store)
cat > /tmp/opensearch.yml << EOF
# Per-node config applied via userdata
# Full config: configs/opensearch.yml on manager
EOF

# Enable and start
systemctl enable wazuh-indexer
systemctl start wazuh-indexer

echo "Wazuh Indexer ${NODE_NAME} bootstrapped successfully"