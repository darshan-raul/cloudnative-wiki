# Wazuh Production Plan — File Index
# Generated as part of the complete production execution plan

## Execution Plan
- `production-plan/README.md` — Full phased execution plan (7 phases, 12 weeks)

## Terraform Infrastructure
- `terraform/main.tf` — VPC, IAM, NLB, EC2s (manager × 2, indexer × 3, dashboard × 1), security groups, EBS
- `terraform/userdata-manager.tpl` — Manager node bootstrap (AL2023)
- `terraform/userdata-indexer.tpl` — Indexer node bootstrap
- `terraform/userdata-dashboard.tpl` — Dashboard node bootstrap

## CloudFormation (Per-Org IAM)
- `cloudformation/iam-roles.yaml` — Cross-account IAM role for CloudTrail S3 read
  - Deploy in EACH org account (not in security tooling account)
  - Creates: WazuhCrossAccountRead role with trust to security tooling account

## Configuration Templates
- `configs/ossec.conf` — Full production ossec.conf (2 managers, multi-org CloudTrail, n8n, TLS)
- `configs/ilm-policy.json` — Indexer ILM: hot→warm(7d)→cold(30d)→delete(90d)
- `configs/cloudtrail-rules.xml` — AWS CloudTrail detection rules (100100-100170), MITRE mapped
- `configs/linux-rules.xml` — Linux detection rules (100300-100382), MITRE mapped
- `configs/verify-stack.sh` — Post-deployment verification script

## Ansible (Agent Deployment)
- `ansible/linux-agent.yml` — Ansible playbook: org+OS group naming, idempotent, secondary_groups support
- `ansible/windows-agent-ssm.json` — SSM State Manager document: org+OS group via WAZUH_ORG_NAME param
- `ansible/inventory-example.yml` — Example inventory per org/OS, SSM targeting by tag

## Agent Grouping Strategy
```
org-<name>-linux     # e.g. org-alpha-linux, org-beta-linux
org-<name>-windows    # e.g. org-alpha-windows, org-beta-windows
```
**Why org+OS**: Targeted rule deployment, differential alerting, selective upgrade rollout, inventory clarity, mirrors cross-account trust model.

## n8n Workflows
- `n8n/wazuh-alert-workflow.json` — Importable n8n workflow: webhook → normalize → enrich (OTX) → route → Planio/Slack/PagerDuty

## Design Decisions Documented
1. **Package/EC2 over K8s**: Wazuh's hostNetwork requirement for agent UDP makes K8s a second-class citizen. EC2 is the right choice at your scale.
2. **Multi-org pattern**: Cross-account IAM role assumption per org (not aws_organization_id) since you have multiple separate orgs.
3. **ILM hot→warm→cold→delete**: 2GB/day → 7GB hot / 60GB warm / 180GB cold / 0 frozen (90-day retention)
4. **NLB for agent communication**: TCP 1514/1515 through NLB for manager HA

## Prerequisite Before Phase 0
Fill in `production-plan/README.md` → Phase 0.1 with your actual orgs:
```yaml
orgs:
  - name: "YOUR-ORG-1"
    cloudtrail_account: "ACTUAL-ACCOUNT-ID"
    cloudtrail_bucket: "ACTUAL-BUCKET-NAME"
    regions: ["us-east-1"]
```

This manifest drives all per-org CloudFormation generation and ossec.conf bucket entries.