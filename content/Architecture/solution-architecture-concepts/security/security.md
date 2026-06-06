---
title: Security Architecture
tags: [security, architecture, zero-trust]
date: 2025-05-24
description: Security architecture principles for solution design
---

# Security Architecture

Security is not a feature you add at the end — it's a **structural property** of the architecture. Design it in from the start.

---

## CIA Triad

Every security control serves at least one of:

| Property | What It Means | Example Control |
|----------|---------------|-----------------|
| **Confidentiality** | Only authorized access | Encryption at rest, RBAC |
| **Integrity** | Data not tampered with | Digital signatures, checksums |
| **Availability** | System stays up | DDoS protection, redundancy |

---

## Zero Trust Principles

**Never trust, always verify** — every request is treated as hostile regardless of network location.

```
Traditional: Zero Trust:
┌──────────┐         ┌──────────┐
│  Inside  │         │  Verify │
│  the │────────▶│  Every   │
│  network │         │  Request │
└──────────┘         └──────────┘
 "trusted" "untrusted by default"
```

### Core Rules
1. **Identity is the perimeter** — not IP or network location
2. **Least privilege** — minimum access required, always
3. **Microsegmentation** — divide network into small zones
4. **Inspect all traffic** — no "internal" traffic bypass

### mTLS Example

```yaml
# Istio — mutual TLS between services
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
spec:
  mtls:
    mode: STRICT  # all traffic must be mTLS
```

---

## Authentication vs Authorization

| Concept | Question | Mechanism |
|---------|----------|-----------|
| **Authentication (AuthN)** | Who are you? | Password, OAuth2, mTLS, SSO |
| **Authorization (AuthZ)** | What can you do? | RBAC, ABAC, OPA policies |

**Rule:** AuthN without AuthZ is just a name tag. Both required.

```python
# ❌ AuthN only — authenticated user can do anything
if user.is_authenticated:
    delete_all_data()

# ✅ AuthZ — role-based permission check
if user.is_authenticated and user.role == "admin":
    delete_all_data()
```

---

## Common Security Patterns

### 1. Secrets Management

```
Never: hardcoded in code, env vars in git, plain text in config files
Always: vault / secrets manager at runtime
```

```python
# ✅ Vault dynamic secrets
from hvac import Client
client = Client(url="https://vault.internal")
secret = client.secrets.kv.v2.read_secret_version(
    path="prod/database/creds"
)
DB_PASSWORD = secret["data"]["data"]["password"]
```

### 2. Input Validation (Defense in Depth)

```python
# ❌ Trust user input
query = f"SELECT * FROM users WHERE id = {user_input}"

# ✅ Parameterized query
cursor.execute("SELECT * FROM users WHERE id = %s", (user_input,))
```

### 3. Audit Logging

Every security-relevant event: who, what, when, result.

```json
{
  "timestamp": "2025-05-24T10:30:00Z",
  "actor": "user:jane@corp.com",
  "action": "DELETE",
  "resource": "orders/ord-12345",
  "result": "success",
  "ip": "10.0.1.45"
}
```

---

## OWASP Top 10 (2021) — Architecture Relevance

| Risk | Architecture Fix |
|------|-----------------|
| A01: Broken Access Control | AuthZ at every API boundary, not just UI |
| A02: Cryptographic Failures | TLS 1.3+, AES-256 at rest, no custom crypto |
| A03: Injection | Parameterized queries, input validation, output encoding |
| A04: Insecure Design | Threat modeling in design phase, ADRs for security |
| A05: Security Misconfiguration | Hardened images, CIS benchmarks, IaC scanning |
| A06: Vulnerable Components | SBOM + dependency scanning in CI |
| A07: AuthN/AuthZ Failures | Use standards (OAuth2, OIDC), no homegrown auth |
| A08: Data Integrity Failures | Sigstore / cosign for supply chain integrity |
| A09: Logging Failures | Structured logs → SIEM, not stdout |
| A10: SSRF | Validate and sanitize all URL inputs, network segmentation |

---

## Architecture Security Checklist

```
Authentication
□ mTLS for all service-to-service communication
□ OAuth2/OIDC for user-facing APIs
□ Short-lived tokens (access: 15min, refresh: 7d)

Authorization
□ RBAC with least privilege per service
□ No shared admin accounts
□ API gateway enforces AuthZ (not just AuthN)

Data
□ Encryption at rest (AES-256)
□ Encryption in transit (TLS 1.3)
□ Secrets in vault, never in env vars or code
□ Data classification — know what needs protection

Infrastructure
□ Network microsegmentation
□ WAF in front of public APIs
□ DDoS protection (Cloudflare, AWS Shield)
□ CIS-hardened base images

Operations
□ SBOM for all artifacts
□ Dependency scanning in CI
□ Penetration testing on major releases
□ Audit logs → SIEM (Wazuh, Splunk, etc.)
```

---

## Source

- [OWASP Top 10](https://owasp.org/Top10/)
- [NIST Zero Trust Architecture](https://csrc.nist.gov/publications/detail/sp/800-207/final)
- [CISA Zero Trust Maturity Model](https://www.cisa.gov/zero-trust-maturity-model)
