#!/bin/bash
# Wazuh Manager Userdata — Amazon Linux 2023
# Runs on first boot to install and configure Wazuh manager

set -e

WAZUH_VERSION="4.12.0"
MANAGER_NUMBER="${manager_number}"
CLUSTER_KEY="${cluster_key}"
INDEXER_HOSTS="${indexer_hosts}"

# Install Wazuh Manager
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /etc/pki/rpm-gpg/RPM-GPG-KEY-WAZUH
echo "[wazuh]
name=Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-WAZUH" > /etc/yum.repos.d/wazuh.repo

yum install -y wazuh-manager-${WAZUH_VERSION}

# Enable and start
systemctl enable wazuh-manager
systemctl start wazuh-manager

# =====================
# Production config — apply after bootstrap
# See: configs/ossec.conf
# =====================

echo "Wazuh Manager ${MANAGER_NUMBER} bootstrapped successfully"