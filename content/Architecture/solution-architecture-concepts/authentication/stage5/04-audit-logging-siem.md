---
title: "5.4 — Audit, Logging, and SIEM Detection for Identity Systems"
author: darshan
tags:
  [
    authentication,
    stage-5,
    security,
    logging,
    audit,
    siem,
    soc2,
    wazuh,
    splunk,
    detection-engineering,
  ]
date: 2026-06-13
description: Enterprise identity observability — authentication event taxonomy, compliance mandates (SOC 2, ISO 27001), structured JSON logging schemas, and concrete SIEM detection rules for Wazuh, Splunk, and Sigma
---

# 5.4 — Audit, Logging, and SIEM Detection for Identity Systems

> **Goal:** Transform identity events into high-fidelity security telemetry, fulfill strict SOC 2 and ISO 27001 audit requirements, and write production SIEM detection rules that catch account takeovers, impossible travel, and token theft in real time.

> **Prerequisites:** [[01-top-12-attacks|Stage 5.1]] through [[03-crypto-hardening|Stage 5.3]].

---

## Table of Contents

1. [Why Identity Logging is Different](#1-why-identity-logging-is-different)
2. [The Identity Event Taxonomy](#2-the-identity-event-taxonomy)
3. [Compliance Mandates: What SOC 2, ISO 27001 & HIPAA Demand](#3-compliance-mandates-what-soc-2-iso-27001--hipaa-demand)
4. [Structured JSON Audit Schema](#4-structured-json-audit-schema)
5. [The Sensitive Data Redaction Rule](#5-the-sensitive-data-redaction-rule)
6. [SIEM Detection Rules: Wazuh, Splunk, and Sigma](#6-siem-detection-rules-wazuh-splunk-and-sigma)
7. [Building an Event Pipeline: FastAPI to OpenSearch/Wazuh](#7-building-an-event-pipeline-fastapi-to-opensearchwazuh)
8. [Exercises & Verification](#8-exercises--verification)
9. [Next Step](#9-next-step)

---

## 1. Why Identity Logging is Different

Standard application logs track performance metrics, SQL query execution, and unhandled errors.

**Identity audit logs track sovereignty, trust, and access.** In an incident response investigation, the identity log is the primary source of truth:

- _Who authenticated?_
- _From where (IP, geolocation, device fingerprint)?_
- _Using what method (Password, Passkey, MFA)?_
- _What tokens were minted, and what data were they authorized to touch?_

If your identity logs are incomplete, corrupted, or lacking correlation IDs, your security operations center (SOC) cannot determine the blast radius of a breach.

---

## 2. The Identity Event Taxonomy

A production Identity Provider must emit structured events across four core categories:

```
┌────────────────────────────────────────────────────────┐
│ 1. Authentication Events                               │
│    - auth.login.success      - auth.login.failure      │
│    - auth.mfa.challenge      - auth.mfa.failure        │
├────────────────────────────────────────────────────────┤
│ 2. Token Lifecycle Events                              │
│    - token.issued            - token.refreshed         │
│    - token.revoked           - token.reuse_detected    │
├────────────────────────────────────────────────────────┤
│ 3. Account & Privilege Changes                         │
│    - user.created            - user.suspended          │
│    - role.assigned           - api_key.created         │
├────────────────────────────────────────────────────────┤
│ 4. Anomaly & Threat Events                             │
│    - threat.brute_force      - threat.impossible_travel│
│    - threat.rate_limit       - threat.replay_attempt   │
└────────────────────────────────────────────────────────┘
```

---

## 3. Compliance Mandates: What SOC 2, ISO 27001 & HIPAA Demand

Auditors look for specific guarantees in your identity audit trail:

- **Immutability (SOC 2 CC6.1 - CC6.3):** Logs must be shipped to write-once-read-many (WORM) storage (e.g. AWS S3 with Object Lock or Elasticsearch Cold Tier) so that an attacker gaining root cannot delete or alter logs.
- **Retention (ISO 27001 A.12.4):** Identity audit logs must be retained for at least 1 year (with 90 days immediately searchable).
- **Non-Repudiation:** Every log must record the exact cryptographic actor (`sub`), client ID, timestamp, and source IP.

---

## 4. Structured JSON Audit Schema

Never write free-text log strings like `logger.info("User logged in")`. Always emit structured JSON:

```json
{
  "event_id": "018f2d5e-7320-b452-9b2f-671c504a9911",
  "timestamp": "2026-06-13T10:14:22.184Z",
  "event_type": "auth.login.success",
  "severity": "INFO",
  "actor": {
    "sub": "usr_998822",
    "email": "darshan@company.com",
    "tenant_id": "org_acme_corp"
  },
  "client": {
    "client_id": "cloud-wiki-spa",
    "ip_address": "198.51.100.42",
    "user_agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    "geo": {
      "country": "IN",
      "city": "Bengaluru",
      "latitude": 12.9716,
      "longitude": 77.5946
    }
  },
  "session": {
    "session_id": "sess_018f2d5e",
    "auth_method": "fido2_passkey",
    "acr": "https://refeds.org/profile/mfa"
  },
  "status": "SUCCESS"
}
```

---

## 5. The Sensitive Data Redaction Rule

> [!CAUTION]
> **Zero Plaintext Credentials in Logs:**  
> Never log passwords, client secrets, unhashed refresh tokens, full bearer access tokens, or unredacted credit cards. Logging sensitive credentials violates PCI-DSS, GDPR, and SOC 2.

### Token Truncation Rule:

When logging a token event, log only its unique ID (`jti`) or a cryptographic thumbprint (SHA-256 of the token), never the raw token string itself:

```json
{
  "token_jti": "b0f74136-1e64-4e31-893d-82dcf3519b78",
  "token_fingerprint": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

---

## 6. SIEM Detection Rules: Wazuh, Splunk, and Sigma

### Rule 1: Stolen Refresh Token Reuse Detection (Sigma)

```yaml
title: OAuth Refresh Token Reuse Anomaly
status: production
description: Detects when a rotated refresh token is presented a second time, indicating token theft.
logsource:
  product: identity
  service: oauth
detection:
  selection:
    event_type: "token.reuse_detected"
  condition: selection
level: critical
tags:
  - attack.credential_access
  - attack.t1528
```

### Rule 2: Impossible Travel (Splunk SPL)

Detects logins for the same user from geographic locations separated by distances that cannot be physically traversed in the elapsed time:

```spl
index=auth event_type="auth.login.success"
| sort 0 actor.sub timestamp
| streamstats current=f window=1
    values(client.geo.latitude) as prev_lat
    values(client.geo.longitude) as prev_lon
    values(timestamp) as prev_time
    values(client.ip_address) as prev_ip
    by actor.sub
| eval time_diff = (strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ") - strptime(prev_time, "%Y-%m-%dT%H:%M:%SZ")) / 3600
| eval distance_km = round(6371 * acos(cos(radians(prev_lat)) * cos(radians(client.geo.latitude)) * cos(radians(client.geo.longitude) - radians(prev_lon)) + sin(radians(prev_lat)) * sin(radians(client.geo.latitude))))
| eval velocity_kmh = round(distance_km / time_diff)
| where velocity_kmh > 900 AND time_diff < 4
| table timestamp actor.sub client.ip_address prev_ip distance_km velocity_kmh
```

### Rule 3: High-Frequency Login Failures (Wazuh XML Rule)

```xml
<group name="identity,auth_failures,">
  <rule id="100250" level="10" frequency="5" timeframe="120">
    <if_matched_sid>100201</if_matched_sid>
    <field name="event_type">auth.login.failure</field>
    <same_field>client.ip_address</same_field>
    <description>Potential Credential Stuffing / Brute Force Attack: 5 failed logins within 2 minutes from $(client.ip_address)</description>
    <mitre>
      <id>T1110.001</id>
    </mitre>
  </rule>
</group>
```

---

## 7. Building an Event Pipeline: FastAPI to OpenSearch/Wazuh

```python
import json
import logging
from datetime import datetime, timezone
import uuid
from fastapi import Request

audit_logger = logging.getLogger("identity_audit")

def emit_audit_event(
    event_type: str,
    actor_sub: str,
    tenant_id: str,
    request: Request,
    status: str = "SUCCESS",
    metadata: dict = None
):
    event = {
        "event_id": str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event_type": event_type,
        "actor": {
            "sub": actor_sub,
            "tenant_id": tenant_id
        },
        "client": {
            "ip_address": request.client.host if request.client else "unknown",
            "user_agent": request.headers.get("user-agent", "unknown")
        },
        "status": status,
        "metadata": metadata or {}
    }
    # Writes structured JSON to stdout for Vector / FluentBit / Filebeat ingestion
    audit_logger.info(json.dumps(event))
```

---

## 8. Exercises & Verification

1. **Verify JSON Output:** Trigger a login failure in your test app. Inspect stdout and ensure the emitted log conforms to the JSON schema.
2. **Test Redaction:** Audit code to verify that no log statement prints `request.form_data.password` or the full `refresh_token` string.
3. **Simulate Impossible Travel:** Ingest two artificial events for the same `sub`: one in New York and one in Tokyo 15 minutes later. Verify your detection query flags it.

---

## 9. Next Step

We have now concluded Stage 5 (Security, Attacks, Hardening). Next, we enter the final frontier of production identity engineering: **Stage 6 — Production, Scale, Frontier**, exploring multi-region active-active architectures, edge caching, and zero-trust workload identity (SPIFFE).

→ [[../stage6/01-ha-identity|Stage 6.1 — HA Identity: Multi-Region Active/Active & Disaster Recovery]]
