---
title: AWS ACM
description: AWS Certificate Manager — public and private TLS/SSL certificates. Managed certificate issuance, auto-renewal, validation via DNS or email, ACM Private CA integration, and CloudFront/ALB integration.
tags:
  - aws/security
date: 2026-10-12
---

# AWS Certificate Manager (ACM)

Prerequisites: [[AWS/security/iam/README|IAM roles and least privilege]] and the [[AWS/security/README|security evidence/response model]].

ACM manages TLS certificates for supported AWS integrations and eligible export workflows. AWS-issued public certificates use Amazon Trust Services; they do not require an invented DigiCert purchase contract.

## Certificate workflows

Distinguish AWS-issued public ACM certificates, public exportable/ACME workflows, ACM private certificates and direct Private CA issuance. Public domain validation and private trust distribution solve different problems. ACM does not require public domain-ownership validation for imported or private-CA-signed certificates.

Imported certificates and certificates issued directly through Private CA IssueCertificate are not eligible for ACM managed renewal. Eligible ACM-issued certificates can renew automatically, but exported certificates must be redeployed to external servers after renewal. Export can include an encrypted private key for eligible private/exportable public certificates; protect the passphrase, private key and access permissions.

Certificates are regional and independently renewed. CloudFront certificate placement has its documented us-east-1 requirement; do not invent a cross-Region copy API.

## TLS lab

Prerequisites: a sandbox DNS name you control, scoped ACM request/read/delete permissions, and DNS-change authority. Public certificate issuance/export can have different charges; do not create a Private CA just for a free lab.

Request an ACM public certificate using DNS validation, add the exact validation CNAME provided by ACM, and wait for ISSUED. Retain the validation record for renewal. Attach the certificate to a disposable supported TLS integration such as an ALB listener, configure its security group and target health, and connect using the correct hostname.

Expected: a trusted chain and matching hostname. Test a deliberately incorrect hostname and expect TLS hostname validation failure; never disable verification as the fix. For private certificates distribute the private trust chain to authorized clients instead of claiming public browser trust.

Cleanup: detach/delete the disposable integration, delete only the lab certificate, and remove lab-only DNS records once renewal is no longer needed. Never delete a certificate still serving production.

## Validity, quotas and cost

Current public ACM validity is 198 days; DNS-managed renewal begins forty-five days before expiry for these certificates. Legacy longer-validity certificates have transition behavior, so monitor actual NotAfter/RenewalEligibility fields rather than hardcoding annual rotation.

Current default ACM quota is 2,500 certificates/account/Region and 5,000 issued/year with documented exclusions; imported/private/ACME limits differ. Verify the owning quota page before bulk issuance.

Non-exportable public certificates used with supported integrations have no additional certificate charge. Exportable public issuance/renewal is paid. Private CA operation is \$400/CA-month in general-purpose mode or \$50 in short-lived mode plus issuance tiers under the owning table; it is not \$0.75 per CA-month.

## Certificate type and deployment comparison

| Certificate                | Issuance/validation                           | Renewal/deployment ownership                             |
| -------------------------- | --------------------------------------------- | -------------------------------------------------------- |
| ACM public non-exportable  | Supported public domain validation            | Eligible managed renewal/integrated service use          |
| ACM exportable public      | Supported paid export workflow                | Protect private key; redeploy renewed export externally  |
| ACM private                | Private CA trust, no public domain validation | Eligible ACM workflow differs from direct PCA issuance   |
| Imported                   | Bring certificate/key/chain                   | Owner replaces/renews; ACM does not renew imported certs |
| Direct Private CA issuance | CA/API signing workflow                       | Direct issuance is not automatically ACM-managed renewal |

```text
domain owner → ACM validation → ISSUED → supported regional TLS integration
                     ↓                        ↓
              retained DNS record      handshake/hostname/chain test
exportable/private key → encrypted export → secure deploy → renewal redeploy
```

## DNS request and inspection walkthrough

Use a domain you own and an approved regional profile:

```bash
aws acm request-certificate --domain-name LAB_DOMAIN \
  --validation-method DNS --idempotency-token WikiLab1
aws acm describe-certificate --certificate-arn CERTIFICATE_ARN \
  --query 'Certificate.{Status:Status,Validation:DomainValidationOptions,NotAfter:NotAfter,Renewal:RenewalEligibility}'
aws acm wait certificate-validated --certificate-arn CERTIFICATE_ARN
```

Record the returned ARN and install the exact ResourceRecord CNAME in the authoritative DNS zone before waiting. Repeated requests, wildcard/base domain names and multiple SANs have their documented validation behavior. A local DNS query against a stale resolver is not proof the authoritative validation record is correct.

Email validation is a separate supported public workflow with recipient/renewal constraints. Private/imported certificates do not follow this public validation step.

## Import, ALB and CloudFront integration

For imported certificates, use protected local PEM artifacts and the documented import-certificate Certificate/PrivateKey/CertificateChain input. Never paste key material into a note, command history or console screenshot. Verify chain ordering, algorithm, hostname/SAN and integration compatibility.

With an existing disposable ALB/target group and issued regional certificate:

```bash
aws elbv2 create-listener --load-balancer-arn ALB_ARN \
  --protocol HTTPS --port 443 --certificates CertificateArn=CERTIFICATE_ARN \
  --default-actions Type=forward,TargetGroupArn=TARGET_GROUP_ARN
```

Configure allowed clients, target/health paths and supported TLS policy; certificate creation alone does not open a working endpoint. CloudFront uses its documented us-east-1 certificate placement and distribution/domain configuration. A Region-local ALB certificate ARN is not automatically usable everywhere.

## Expiry and Private CA operating runbook

Inspect actual NotAfter/RenewalEligibility/RenewalSummary and the documented DaysToExpiry metric/renewal events. Import failures, missing validation DNS, detached/ineligible certificates and external-export redeployment are distinct failure modes. Alarm early enough for operator action and test the notification.

A private CA requires CA creation, CSR signing/install, activation, issuance permissions, revocation/trust distribution and ongoing fees. Creating a CA resource alone does not activate a trust chain. Use a dedicated approved PKI lab, not an accidental \$400/month resource. Delete CA/certificate artifacts only under the documented CA lifecycle and after all issued-client dependencies are understood.

References: [request contract](https://docs.aws.amazon.com/cli/latest/reference/acm/request-certificate.html), [DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html), [import](https://docs.aws.amazon.com/acm/latest/userguide/import-certificate.html), [monitoring](https://docs.aws.amazon.com/acm/latest/userguide/cloudwatch-metrics.html).

## References

- [Certificate options](https://docs.aws.amazon.com/acm/latest/userguide/service-options.html)
- [Validation scope](https://docs.aws.amazon.com/acm/latest/userguide/domain-ownership-validation.html)
- [Certificate characteristics](https://docs.aws.amazon.com/acm/latest/userguide/acm-certificate-characteristics.html)
- [Renewal eligibility](https://docs.aws.amazon.com/acm/latest/userguide/managed-renewal.html)
- [Private export](https://docs.aws.amazon.com/acm/latest/userguide/export-private.html)
- [ACM quotas](https://docs.aws.amazon.com/acm/latest/userguide/acm-limits.html)
- [Private CA pricing](https://aws.amazon.com/private-ca/pricing/)

## Across the wiki

- [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls|TLS and mTLS in Kubernetes]]
- [[Architecture/solution-architecture-concepts/authentication/stage0/03-http-tls-foundations|0.3 — HTTP & TLS Foundations Every Auth Engineer Must Know]]
- [[Kubernetes/concepts/L07-security/01-api-access/04-certificates|Certificates]]
- [[Architecture/solution-architecture-concepts/cryptography/keystore|Keystore]]
