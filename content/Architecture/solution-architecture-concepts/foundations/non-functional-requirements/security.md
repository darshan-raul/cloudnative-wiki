---
title: Security
---

# Security

Security in solution architecture is not a feature you add at the end — it's a dimension that shapes every structural decision. The architecture you choose determines your attack surface.

## The CIA Triad

Every security control serves at least one of three goals:

- **Confidentiality** — only authorized parties can read the data
- **Integrity** — data is not modified without authorization
- **Availability** — the system is available when needed (security failures cause availability loss)

## Defense in Depth

No single security control is sufficient. Layer multiple controls so that defeating one doesn't compromise the system:

```
Internet → Firewall → Network Segmentation → App Auth → Data Encryption
     ↑          ↑ ↑                ↑             ↑
  perimeter  network tenant           access at-rest
  (WAF/CDN)  (VPC/FW)    isolation         control encryption
```

Each layer buys time and reduces blast radius.

## Architectural Security Decisions

### Authentication and Authorization

**Authentication** — who are you? (identity verification)
**Authorization** — what can you do? (access control after authentication)

| Pattern | When to use | Risk |
|---|---|---|
| **RBAC** (Role-Based Access Control) | Simple permission hierarchies | Role explosion in complex Orgs |
| **ABAC** (Attribute-Based Access Control) | Fine-grained, dynamic policies | Complex policy evaluation |
| **Zero Trust** | Every request verified, no implicit trust | Higher latency, complexity |
| **最小权限 (PoLP)** | Default-deny posture | Requires precise permission scoping |

See [[authentication/README|Authentication]] for JWT, OAuth2, OIDC, SAML patterns.

### Network Segmentation

Isolate workloads so a compromise in one doesn't spread:

```
Public Subnet:  Load Balancer, CDN, WAF
                 ↓ (only443, filtered)
Private Subnet: App Servers
                 ↓ (only app-tier ports, no direct DB access)
Data Subnet:    Databases, Redis, Internal APIs
```

- **Security groups** (AWS) — stateful firewall per instance
- **Network ACLs** — stateless firewall per subnet
- **PrivateLink/VPC endpoints** — access AWS services without traversing the internet

### Encryption

**In transit:**
- TLS 1.2+ for all external connections
- mTLS (mutual TLS) for service-to-service authentication
- Certificate pinning for mobile apps

**At rest:**
- Database-level encryption (AWS RDS encryption, Azure SQL TDE)
- Disk encryption (LUKS, AWS EBS encryption)
- Application-level encryption for sensitive fields (PII, credentials)

**Key management:**
- Cloud KMS (AWS KMS, GCP Cloud KMS, Azure Key Vault) — centralized key lifecycle
- Never store encryption keys alongside encrypted data
- Key rotation strategy (automatic vs manual, rotation period)

### Secrets Management

- **Vault (HashiCorp)** — dynamic secrets, secret rotation, audit logging
- **AWS Secrets Manager / GCP Secret Manager** — managed secret storage with rotation
- **K8s Secrets** — base64-encoded (not encrypted by default — enable at-rest encryption + RBAC)

**Rule:** Secrets should never be in environment variables that get logged, committed to git, or exposed in error messages.

## Threat Modeling

For every architecture, ask:

1. **What are we protecting?** (assets: data, services, reputation)
2. **Who are the attackers?** (external threat actors, insider threat, supply chain)
3. **How will they attack?** (threat vectors: network, application, social engineering, physical)
4. **What controls do we have?** (existing mitigations)
5. **What's the residual risk?** (what remains after controls)

A simple threat model table:

| Asset | Threat | Vector | Control | Residual Risk |
|---|---|---|---|---|
| User DB | SQL injection | Web app | Input validation, parameterized queries | Low |
| API keys | Key exposure | Git repos | Secret scanning, Vault | Medium |
| Customer PII | Data breach | Compromised DB | Encryption at rest, IAM, network isolation | Medium |

## Compliance Implications

Compliance requirements shape architecture:

- **SOC2** — requires access logs, change management, encryption, incident response
- **GDPR** — data residency, right to deletion, breach notification (72-hour)
- **HIPAA** — encryption, audit logging, BAA with cloud provider
- **PCI-DSS** — network segmentation, encryption, no direct DB access from internet
- **ISO27001** — broad information security management

Compliance doesn't make you secure — it provides a baseline framework. Map compliance controls to actual security outcomes.

## Security Logging and Monitoring

Security events to log:

- **Authentication events** — login success/failure, privilege escalation
- **Authorization events** — access denied to sensitive resources
- **Data events** — bulk exports, data deletions, sensitive field access
- **Configuration changes** — firewall rule changes, IAM policy changes
- **Anomalous behavior** — unusual API call volumes, geographic anomalies

Correlate logs across services. A single failed login is noise. 10,000 failed logins from 500 IPs is an attack.

## Secure Development Lifecycle

See [[shift-left|Shift Left]] for moving security earlier in the development process. Key practices:

- **SAST** (Static Application Security Testing) — scan code before it runs
- **DAST** (Dynamic Application Security Testing) — scan running application
- **Dependency scanning** — detect vulnerable libraries (OWASP Dependency-Check, Snyk)
- **Secret scanning** — detect committed secrets (Git hooks, CI checks)
- **Penetration testing** — manual/automated exploitation attempts

## Common Security Anti-Patterns

- **Security as an afterthought** — bolt-on security after architecture is finalized
- **Implicit trust within the VPC** — no internal auth, just network perimeter
- **Credential in URL** — passwords in URLs get logged by proxies, browsers, server logs
- **Overprivileged services** — service accounts with more permissions than needed
- **No input validation** — SQL injection, XSS, command injection
- **Unencrypted sensitive data** — PII, credentials, API keys in plaintext
- **No audit logging** — no way to reconstruct what happened after a breach

## Related

- [[shift-left|Shift Left]] — moving security earlier in the lifecycle
- [[authentication/README|Authentication]] — auth patterns
- [[cryptography/README|Cryptography]] — encryption, signing, PKI
- [[totp|TOTP]] — time-based one-time passwords
