---
title: "M16: Runtime Secret Management"
tags: [devsecops, stage4, runtime, secrets, vault, external-secrets-operator, sealed-secrets, workload-identity]
date: 2026-06-16
description: "Module 16 of 20 — runtime secret management for workloads. HashiCorp Vault, External Secrets Operator, Sealed Secrets, workload identity federation, and the patterns for keeping secrets out of config and env files."
---

# M16: Runtime Secret Management

The last place secrets should live is in the application's environment variables or config files. The first place they should be is in a system that issues them at the moment of need, with audit, rotation, and automatic expiry. This module covers the runtime secret management architecture: workload identity, Vault, External Secrets Operator, and the day-to-day discipline of "no static secrets in the workload."

## Learning Objectives

By the end of this module you should be able to:

  - Replace every static secret in a workload with workload identity, Vault, or ESO
  - Pick the right tool for the use case (workload identity vs. dynamic secrets vs. synced secrets)
  - Rotate a runtime secret without downtime
  - Audit secret access in Vault
  - Implement a secrets-as-code pattern for K8s workloads

## 1. The Four Tiers (Review)

From M06, the four tiers of secret management:

| Tier | Mechanism | TTL | Use case |
| ---- | --------- | --- | -------- |
| 1 | Cloud workload identity (IRSA, WIF, Workload Identity) | 1h | Cloud API access |
| 2 | Dynamic Vault secrets | 1h | DB, third-party API |
| 3 | Long-lived Vault secrets | indefinite | Legacy |
| 4 | Env vars, config files | until rotated | Avoid |

The goal: tier 4 → 0, tier 3 → tier 2 (over time), tier 2 → tier 1 where possible.

This module covers the runtime patterns for tiers 1, 2, and 3. Tier 1 is covered in M12 for the pipeline; this module focuses on application workloads.

## 2. Cloud Workload Identity

### AWS: IRSA (IAM Roles for Service Accounts)

```yaml
# Service account annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-app-role
```

```yaml
# Pod uses the service account
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app
  containers:
    - name: my-app
      image: my-app:v1.2.3
      # AWS SDK retrieves creds automatically from the pod's projected token
      # No AWS_ACCESS_KEY_ID, no AWS_SECRET_ACCESS_KEY
```

The pod gets a projected service account token; the AWS SDK exchanges it for STS credentials; the credentials are valid for 1 hour. The application code uses the standard AWS SDK; no library changes.

### GCP: Workload Identity

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  annotations:
    iam.gke.io/gcp-service-account: [email protected]
```

```bash
# Bind the GSA to the KSA
gcloud iam service-accounts add-iam-policy-binding \
  [email protected] \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/my-app]"
```

The KSA impersonates the GSA. The pod authenticates to GCP as the GSA. No key file.

### Azure: Workload Identity

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  annotations:
    azure.workload.identity/client-id: <AZURE_CLIENT_ID>
  labels:
    azure.workload.identity/use: "true"
```

A sidecar (`azure-identity-token`) projects the federated token. The pod authenticates to Azure as the managed identity.

## 3. HashiCorp Vault: The Generic Layer

Vault is the de facto standard for runtime secrets that are *not* cloud credentials. Database passwords, third-party API keys, certificates, encryption keys.

### Dynamic Database Credentials

The classic Vault use case. When the app starts, it requests a Postgres credential. Vault creates a temporary user with a 1-hour TTL, grants it the configured role, and returns the username and password.

```bash
# Vault policy
path "database/creds/my-app" {
  capabilities = ["read"]
}
```

```python
# Application
import hvac

client = hvac.Client(url="https://vault.example.com", token=os.environ["VAULT_TOKEN"])
creds = client.secrets.database.generate_credentials(name="my-app")
username = creds["data"]["username"]
password = creds["data"]["password"]
conn = psycopg2.connect(
    host="db.example.com",
    user=username,
    password=password,
    dbname="myapp",
)
```

The credentials expire in 1 hour. The next request gets a new user. No long-lived DB password exists. Vault revokes the user at expiry.

### Vault Agent Sidecar / CSI Provider

For workloads that don't natively speak Vault, use Vault Agent:

  - **Init container / sidecar** — fetches secrets at startup, writes to a shared volume, renews on TTL
  - **Vault CSI Provider** — mounts secrets as files in the pod; automatic renewal

The CSI provider is the more modern pattern:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-db-creds
spec:
  provider: vault
  parameters:
    objects: |
      - objectName: "db-password"
        secretPath: "database/creds/my-app"
        secretKey: "password"
```

```yaml
# Pod mounts the secret
spec:
  containers:
    - name: my-app
      volumeMounts:
        - name: vault-secrets
          mountPath: /etc/secrets
          readOnly: true
  volumes:
    - name: vault-secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: vault-db-creds
```

The pod gets `/etc/secrets/db-password` mounted as a file. The file is renewed automatically; the app reads it once at startup and re-reads on SIGHUP.

### Vault Authentication

How does the workload authenticate *to* Vault? Several options:

  - **Kubernetes auth** — the service account token is presented; Vault verifies via OIDC
  - **AWS / GCP / Azure auth** — cloud instance metadata presented
  - **AppRole** — workload has a static AppRole ID + secret (worse; avoid)

K8s auth is the default:

```bash
# Vault policy binding
vault write auth/kubernetes/role/my-app \
  bound_service_account_names=my-app \
  bound_service_account_namespaces=prod \
  policies=my-app-policy \
  ttl=1h
```

The pod presents its service account token; Vault returns a Vault token; the workload uses the Vault token to read secrets.

## 4. External Secrets Operator (ESO)

For teams not ready for Vault, ESO is the pragmatic middle ground. ESO syncs secrets from a third-party store (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, Vault) into Kubernetes as native `Secret` resources.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-db
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-app-db
  data:
    - secretKey: password
      remoteRef:
        key: prod/my-app/db
        property: password
```

ESO fetches the secret from AWS Secrets Manager every 5 minutes, syncs it to a native K8s Secret. The application mounts the K8s Secret normally.

ESO is "synced secrets," not "dynamic." The secret in AWS is still long-lived; ESO just moves it into the cluster. The upgrade path is dynamic secrets (Vault), but ESO is the right starting point for many teams.

## 5. Sealed Secrets (Bitnami)

For GitOps workflows where secrets must live in git (because git is the source of truth), Sealed Secrets encrypts a secret in such a way that only the cluster's controller can decrypt it.

```bash
# Encrypt a secret
kubectl create secret generic my-app-db \
  --from-literal=password=hunter2 \
  --dry-run=client \
  -o yaml > secret.yaml
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Commit sealed-secret.yaml to git
```

In the cluster, the Sealed Secrets controller decrypts and creates the native Secret.

Caveat: Sealed Secrets is "encryption," not "management." There's no rotation, no TTL, no audit. Acceptable for low-value secrets, not for production credentials.

## 6. Certificate Management

TLS certificates are secrets. Cert-manager handles the full lifecycle:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-tls
spec:
  secretName: my-app-tls
  dnsNames:
    - my-app.example.com
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

Cert-manager requests, validates, renews, and stores the certificate. The cert rotates 30 days before expiry. No human in the loop.

For internal PKI, Vault PKI engine or cert-manager with an internal CA.

## 7. Secret Rotation

### Pattern 1: TTL-Based (Dynamic)

Vault dynamic secrets rotate by definition. The next read returns a new credential. Application code must be tolerant of credential changes — typically: re-fetch on 401/403, or use Vault Agent's automatic renewal.

### Pattern 2: Periodic Re-Fetch

For tier-3 secrets, schedule a re-fetch. ESO's `refreshInterval` does this. For long-lived secrets, schedule a rotation in the source system (e.g., AWS Secrets Manager rotation lambda).

### Pattern 3: Webhook-Based

Vault Agent supports webhook renewal — the app calls a webhook when the secret is about to expire. More complex; only when pattern 1 doesn't work.

### The Rotation Drill

```
00:00  Security team simulates: "rotate the DB password"
00:05  Identify all consumers of the password
       - List all workloads using the secret
       - Confirm each supports credential reload
00:10  Rotate the secret in the source
       - AWS Secrets Manager: invoke rotation lambda
       - Vault: revoke the secret; consumers re-fetch
00:15  Verify the old credential no longer works
       - Try a manual connection with the old password
00:20  Verify the new credential works
       - Workloads should have re-fetched automatically
       - If not, restart them
00:30  Audit log: who accessed the old credential, who accessed the new
```

The drill surfaces workloads that don't re-fetch gracefully. The list of broken workloads is your secret-management backlog.

## 8. Secret Hygiene at the Workload Level

### Mount as Files, Not Env Vars

```yaml
# Better: mount as file
volumeMounts:
  - name: db-creds
    mountPath: /etc/secrets
    readOnly: true

# Worse: env vars
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: my-app-db
        key: password
```

Why: env vars appear in `/proc/1/environ`, in crash dumps, in error reports, in `kubectl describe pod`. Files mounted read-only with explicit permissions are harder to leak.

### readOnlyRootFilesystem + tmpfs

```yaml
securityContext:
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
volumes:
  - name: tmp
    emptyDir: {}
  - name: home
    emptyDir: {}
```

The container's root FS is read-only. Writable locations are tmpfs. Secret files mounted read-only cannot be modified by the app.

### No Secrets in Logs

The single most common secret leak: `console.log(process.env)`, or `logger.info(config)`. Add to the project's lint config:

```python
# Python: forbid dumping env
import ast

class NoEnvDumpChecker(ast.NodeVisitor):
    def visit_Call(self, node):
        if isinstance(node.func, ast.Attribute):
            if node.func.attr in ("info", "debug", "warning", "error"):
                for arg in node.args:
                    if "env" in ast.unparse(arg):
                        # raise lint error
                        ...
```

Forbid `printenv`, `env | grep`, and `os.environ` in code review.

## 9. Audit and Observability

Every secret access should be logged:

  - **Vault audit log** — every read, every write, every auth
  - **AWS CloudTrail** — every Secrets Manager call
  - **K8s audit log** — every Secret read (configure audit policy)
  - **Application logs** — do not log secret values; do log "secret X accessed by user Y at time Z"

Pipe to your SIEM. Anomalies (e.g., a workload reading 1000 secrets in 5 minutes) are signal.

## 10. Common Patterns and Anti-Patterns

| Pattern | Use case |
| ------- | -------- |
| Workload identity for cloud APIs | S3, DynamoDB, SQS, etc. |
| Vault dynamic for databases | Postgres, MySQL, Mongo, Redis |
| Vault PKI for TLS | Internal services |
| ESO for third-party API keys | Stripe, Twilio, etc. |
| Cert-manager for public TLS | Let's Encrypt, internal CA |
| Sealed Secrets for low-value config | Bootstrap configs |

| Anti-pattern | Why it fails |
| ------------ | ------------ |
| Static AWS keys in env | The whole point of M12 is to avoid this |
| Long-lived DB password in K8s Secret | Drift, no rotation, no audit |
| Secret in container image | Image is distributed; secret is too |
| Commit secret to git | Even Sealed Secrets loses to a bad decrypt key |
| One secret for all environments | Blast radius = total |
| Rotate the secret and forget to restart | Old process keeps using old secret |

## 11. The 1-Quarter Migration Plan

  - **Week 1** — Inventory: every secret in every workload. Classify by tier.
  - **Week 2** — Set up Vault (or pick the secret store). Configure the first secret backend.
  - **Week 3** — Migrate one workload end-to-end. Validate the rotation drill.
  - **Weeks 4–8** — Migrate workloads in priority order. Tier 4 → tier 2/3 first.
  - **Weeks 9–12** — Move tier 3 to tier 2 (dynamic). Set up tier 1 (workload identity) for cloud APIs.

## 12. Self-Check

  1. For each workload, what is the highest-tier secret it uses? If any is tier 4, that's your first migration.
  2. When was the last time you ran the rotation drill? Did any workload fail to re-fetch?
  3. Can you answer "which workload accessed which secret in the last 24 hours"? If not, enable audit logs.

## 13. Secret Reference Architecture for a Modern Stack

A reference architecture for a typical cloud-native org:

```
  Workload (pod)
       |
       |--- 1. Cloud APIs: Workload Identity (IRSA/WIF)
       |
       |--- 2. Database: Vault dynamic secret (or AWS RDS IAM)
       |
       |--- 3. Third-party APIs: Vault synced to ESO
       |
       |--- 4. Internal services: mTLS (cert-manager + SPIFFE)
       |
       |--- 5. Internal API tokens: Vault dynamic
       |
       v
  Workload (no static secrets)
```

Each tier uses the right tool. No static secrets in any tier. The blast radius of a workload compromise is limited to the role of the workload's identity, not the org's secrets.

## 14. The Rotation Drill (Extended)

A quarterly rotation drill exercises the full process. The full version:

### Pre-Drill (Day -1)

  - Announce the drill to on-call
  - Identify the top 10 secrets in use
  - Pick 3 for the drill (one from each tier: cloud, DB, third-party)
  - Stage the runbook in the wiki

### Drill (Day 0)

  - 09:00 — Announce drill; assign roles (incident commander, scribe, executor)
  - 09:05 — Rotate the first secret (cloud credential, simulated)
  - 09:15 — Verify the old credential is dead
  - 09:20 — Verify the new credential works
  - 09:30 — Rotate the second secret (database, real)
  - 09:45 — Database consumers reconnect automatically
  - 10:00 — Rotate the third secret (third-party API, real)
  - 10:15 — Verify the third-party integration works
  - 10:30 — Debrief: what worked, what didn't

### Post-Drill (Day +1)

  - Document the drill in the postmortem template
  - File improvement stories for each gap
  - Update the runbook
  - Schedule the next drill

The drill surfaces the friction that exists in your secret management. The friction points are your improvement backlog.

## 15. Secret Management and Compliance

| Framework | Control | Secret management |
| --------- | ------- | ----------------- |
| SOC 2 CC6.1 | Logical access | Vault audit, IAM logs |
| SOC 2 CC6.7 | Data in transit | mTLS via cert-manager + SPIFFE |
| SOC 2 CC7.1 | Vuln detection | Vault dynamic secrets reduce blast radius |
| ISO A.5.15 | Access control | Vault policies, IAM |
| ISO A.5.16 | Identity management | Workload identity, OIDC |
| ISO A.8.24 | Cryptography | cert-manager, Vault PKI |
| PCI 3.x | Protect stored data | Encryption keys from KMS via Vault |
| PCI 8.x | Authenticate access | MFA, OIDC, Vault tokens |
| FedRAMP AC-2 | Account management | Vault user management |
| FedRAMP SC-12 | Crypto key management | Vault + KMS |
| FedRAMP IA-5 | Authenticator management | Vault dynamic secrets |

The audit asks "how do you manage secrets?" The answer is the audit log + rotation drill + tier model.

## 16. Secret Management Metrics

| Metric | Target | Why |
| ------ | ------ | --- |
| % of workloads on tier 1 (workload identity) | >70% | Cloud access is short-lived |
| % of workloads on tier 2 (Vault dynamic) | >25% | DB / third-party is short-lived |
| % of workloads on tier 3 (Vault static) | <5% | Legacy; migrate away |
| % of workloads on tier 4 (env vars) | 0% | The minimum acceptable |
| Mean time to rotate a secret | <30 min | Incident response |
| % of secret access logged | 100% | Audit trail |
| Vault policy violations | 0 | Misconfiguration |

If tier-4 is non-zero, you have a migration backlog. If tier-3 is rising, the migration is stalled.

## 17. Common Mistakes (Extended)

| Mistake | Consequence | Fix |
| ------- | ----------- | --- |
| Mount secret in env, not file | Secret in crash dump, log, /proc | Mount as file, readOnly |
| Mount secret in /tmp | World-readable on some systems | Mount in /etc/secrets, mode 0400 |
| Use `chmod 777` in entrypoint | Defeats file mode | Set mode in manifest, not in entrypoint |
| Restart pod on secret change | Long reload time | Use re-fetch pattern (Vault Agent) |
| No webhook for secret refresh | Pod uses stale secret | Vault Agent with webhook |
| Secret in shell history | Leaked via terminal logs | Use Vault CLI, not psql with -p |
| Hardcoded test secrets in code | Reachable by SCA (M07) | Mock secrets in test; or use a sandbox |
| "Read-only filesystem" but secret in env | Env is read via /proc, still leaks | Mount as file |

## 18. The Secret Management Team

A small team owns the secret management platform:

  - **Vault admin** — runs Vault, manages policies, audits access
  - **Cloud IAM owner** — manages IRSA, WIF, Workload Identity
  - **Cert manager** — runs cert-manager, renews internal CAs
  - **Platform engineer** — integrates Vault with K8s (CSI, Agent)

For a mid-size org: 1–2 FTE. The investment is small; the payoff is large.

## Related

  - [[DevOps/devsecops/stage1-code/06-secrets-detection|M06: Secrets Detection]]
  - [[DevOps/devsecops/stage3-deploy/12-pipeline-identity-oidc|M12: Pipeline Identity & OIDC]]
  - [[DevOps/devsecops/stage3-deploy/15-policy-as-code|M15: Policy-as-Code]]
  - [[DevOps/devsecops/stage4-runtime/README|Stage 4 — Runtime]]
