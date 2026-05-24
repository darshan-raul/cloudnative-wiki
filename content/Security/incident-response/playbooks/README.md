---
title: Incident Response Playbooks
tags: [incident-response, playbook, security, automation, n8n]
date: 2025-05-24
description: Step-by-step incident response playbooks for common security scenarios - AWS credential compromise, malware, phishing, Kubernetes compromise
---

# IR Playbooks 📋

Standard playbooks for the most common security incidents.

## AWS Credential Compromise

### Detection
- GuardDuty alert: "Credential access: Instance credential exfiltration"
- CloudTrail: `GetSessionToken` or `AssumeRole` from unexpected IP
- Wazuh: brute force on AWS console

### Response

```bash
# 1. Block compromised IAM access key
aws iam update-access-key --access-key-id AKIA... --status Inactive

# 2. Revoke all sessions for the user
aws iam delete-login-profile --user-name <username>

# 3. Force password rotation
aws iam create-login-profile --user-name <username> --reset-password

# 4. Review CloudTrail for actions taken
aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=<user>
```

### Automation (n8n)
```
Wazuh alert (level 9)
  → n8n: revoke key + create Planio ticket + Slack #security-incidents
```

## Malware on Endpoint

### Detection
- Wazuh: suspicious process (crypto miner, RAT)
- Falco: shell spawned from network
- EDR alert

### Response

```bash
# 1. Isolate host (disable network)
sudo iptables -I OUTPUT -d <malicious-ip> -j DROP
sudo iptables -I INPUT -s <malicious-ip> -j DROP

# 2. Capture memory for forensics
sudo fmddumprecorder -S > memory.raw

# 3. Kill malicious process
sudo kill -9 <pid>

# 4. Preserve evidence before reboot
sudo dd if=/dev/sda of=/ forensics/sda.image bs=4M
```

## Phishing Link Clicked

### Response

```bash
# 1. Reset user credentials immediately
# Disable account via Entra ID / Okta / AWS SSO

# 2. Scan endpoint for malware
# Run full scan with Wazuh agent + Trivy

# 3. Check browser for stored creds
# Clear browser data, check password managers

# 4. Review email logs for spread
# Check if email was forwarded / rules created
```

## Kubernetes Cluster Compromise

### Detection
- Falco: suspicious kubectl exec, mounting sensitive paths
- Wazuh: unusual API calls to K8s API from external IP

### Response

```bash
# 1. Identify compromised pod
kubectl get pods --all-namespaces -o wide | grep <suspicious-ip>

# 2. Isolate namespace (block egress/ingress)
kubectl label namespace <ns> isolation=quarantine

# 3. Delete malicious pod
kubectl delete pod <pod-name> -n <namespace> --force

# 4. Rotate all secrets in namespace
kubectl get secrets -n <namespace> -o json | jq '.items[].metadata.name'

# 5. Review audit logs
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

## S3 Public Access

### Detection
- AWS Config rule: `s3-bucket-public-access-prohibited`
- GuardDuty: S3 data exfiltration

### Response

```bash
# 1. Block public access immediately
aws s3api put-public-access-block \
  --bucket <bucket-name> \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,RestrictPublicBols=true,BlockPublicPolicy=true"

# 2. Identify what was exposed
aws cloudtrail lookup-events --lookup-attributes AttributeKey=S3BucketName,AttributeValue=<bucket>

# 3. Review CloudWatch for downloads
```

## Related

- [[Security/incident-response/README|IR Hub]]
- [[Security/siem/wazuh/integrations/README|n8n Integrations]]