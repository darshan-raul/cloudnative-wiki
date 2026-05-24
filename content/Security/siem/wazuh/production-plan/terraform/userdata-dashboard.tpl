#!/bin/bash
# Wazuh Dashboard Userdata — Amazon Linux 2023

set -e

WAZUH_DASHBOARD_VERSION="4.12.0"
INDEXER_HOSTS="${indexer_hosts}"
WAZUH_FQDN="${wazuh_fqdn}"

# Install Wazuh Dashboard
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /etc/pki/rpm-gpg/RPM-GPG-KEY-WAZUH
echo "[wazuh]
name=Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-WAZUH" > /etc/yum.repos.d/wazuh.repo

yum install -y wazuh-dashboard-${WAZUH_DASHBOARD_VERSION}

# Install nginx + certbot for TLS
yum install -y nginx python3-certbot-nginx

# =====================
# nginx config — see configs/nginx-wazuh-dashboard.conf
# certbot: HTTPS certs via Let's Encrypt
# =====================

# Enable and start
systemctl enable nginx
systemctl enable wazuh-dashboard
systemctl start nginx
systemctl start wazuh-dashboard

echo "Wazuh Dashboard bootstrapped successfully"