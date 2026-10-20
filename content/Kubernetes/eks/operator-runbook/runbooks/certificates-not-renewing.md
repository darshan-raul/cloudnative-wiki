---
title: "Runbook: TLS Certificates Not Renewing (cert-manager and ACM)"
description: "A certificate is close to expiry or already expired. Follow cert-manager's Certificate, Order and Challenge chain to the failing step, or check ACM managed renewal for load-balancer certificates."
tags:
  [
    kubernetes/eks/operator-runbook,
    eks,
    runbook,
    tls,
    cert-manager,
    acm,
    incident,
  ]
date: 2026-10-20
aliases: [cert-manager not renewing runbook, EKS certificate expiry]
---

# Runbook: TLS Certificates Not Renewing (cert-manager and ACM)

**Applies to:** cert-manager issuing into Kubernetes Secrets (ACME / Let's Encrypt, AWS Private CA, self-signed and CA issuers), and ACM certificates attached to ALBs or NLBs by the AWS Load Balancer Controller.
**Typical severity:** Sev 3 with weeks left; Sev 1 once expired.
**Tested:** not run on a live cluster; commands checked for syntax.

## Symptoms

- Expiry alerts, or browsers and clients failing with `certificate has expired`.
- `kubectl get certificates -A` shows `READY False`.
- cert-manager events such as `Failed to create Order`, `Waiting for HTTP-01 challenge propagation`, or `urn:ietf:params:acme:error:rateLimited`.

## First: which certificate is served?

```bash
export HOST=<hostname>
openssl s_client -connect "$HOST:443" -servername "$HOST" </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -enddate
```

- An **Amazon** issuer → an ACM certificate on the load balancer. Go to [[#ACM certificates on load balancers|ACM]].
- Any other issuer (Let's Encrypt, your private CA) → cert-manager, or whatever controller manages the Secret. Continue below.

## Inputs

Variables follow [[Kubernetes/eks/operator-runbook/reference/command-conventions|command conventions]]; run its safety checks first.

```bash
export REGION=us-east-1 NS=<namespace> CERT=<Certificate name>
```

## Triage (cert-manager)

**1. Certificate status and expiry:**

```bash
kubectl get certificate "$CERT" -n "$NS" -o wide
kubectl describe certificate "$CERT" -n "$NS" | sed -n '/Status:/,$p'
SECRET=$(kubectl get certificate "$CERT" -n "$NS" -o jsonpath='{.spec.secretName}')
kubectl get secret "$SECRET" -n "$NS" -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate
```

cert-manager renews when **two-thirds** of the lifetime has passed, unless `renewBefore` says otherwise. A 90-day certificate renews about 30 days before expiry, so you normally have weeks to fix a failure.

**2. Follow the chain.** Each step creates the next object; the first one that isn't successful is the problem:

```bash
kubectl get certificaterequests,orders,challenges -n "$NS" | grep -E "NAME|$CERT"
kubectl describe challenge -n "$NS" <challenge>      # ACME: why validation fails
kubectl get clusterissuers,issuers -A                # READY True?
kubectl logs -n cert-manager deploy/cert-manager --tail=100 | grep -iE "$CERT|error" | tail
```

If you have `cmctl`, `cmctl status certificate "$CERT" -n "$NS"` prints the whole chain in one go.

## Diagnosis

| Signal                                                                                   | Cause                                                                | Fix   |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ----- |
| Issuer `READY False`                                                                     | A. Issuer misconfigured (ACME account, CA secret, Private CA access) | Fix A |
| HTTP-01 challenge `pending`: `wrong status code '404'`, connection timeout               | B. Challenge URL unreachable from the internet                       | Fix B |
| DNS-01 challenge: Route 53 `AccessDenied`, or record not propagating                     | C. Route 53 permissions or zone                                      | Fix C |
| `rateLimited`                                                                            | D. ACME rate limit                                                   | Fix D |
| Certificate `READY True` and the Secret renewed, but the old certificate is still served | E. Consumer didn't reload                                            | Fix E |

## Fix

### A. Issuer

- **ACME:** the account private key Secret named in `privateKeySecretRef` must exist; the email and server URL must be valid.
- **AWS Private CA issuer:** the issuer's role needs `acm-pca:IssueCertificate`, `GetCertificate` and `DescribeCertificateAuthority` on the CA, and the CA must be `ACTIVE` and itself not expired.
- **CA issuer:** the CA Secret exists and the CA certificate is still valid.

### B. HTTP-01 unreachable

Let's Encrypt must fetch `http://<host>/.well-known/acme-challenge/<token>` from the internet on **port 80**:

```bash
curl -sv "http://$HOST/.well-known/acme-challenge/test" 2>&1 | grep -E '^< HTTP|Connected'
```

Common causes: the solver's `ingressClassName` doesn't match your controller; the ALB only listens on 443, or redirects 80 to 443 before the solver path; WAF or security groups block port 80; or DNS for the host doesn't point at this load balancer yet. Wildcard certificates **require** DNS-01.

### C. DNS-01 with Route 53

The cert-manager controller's role (Pod Identity or IRSA) needs `route53:ChangeResourceRecordSets` and `ListResourceRecordSets` on the hosted zone, plus `route53:GetChange` and `ListHostedZonesByName`. With private and public zones of the same name, point the solver at the **public** zone's `hostedZoneID`. A leftover `_acme-challenge` TXT record from an earlier failed attempt can also confuse validation; cert-manager normally cleans it up.

### D. Rate limit

Let's Encrypt limits certificates per registered domain per week, and duplicate certificates. Stop the retry loop (fix the underlying failure first, or delete the stuck Order so it doesn't keep retrying), and wait for the window. For testing, point the issuer at the **staging** ACME server.

### E. Consumer didn't reload

Ingress controllers watch their TLS Secrets and reload automatically. Applications that terminate TLS themselves often read the certificate at startup only: `kubectl rollout restart deploy/<name> -n "$NS"`. For a long-term fix, use a reloader, or make the app watch the file.

**Force a renewal** after fixing the cause: `cmctl renew "$CERT" -n "$NS"`, or delete the failed `CertificateRequest`.

## ACM certificates on load balancers

ACM renews its certificates automatically **if it can still validate them**:

```bash
aws acm list-certificates --region "$REGION" --query 'CertificateSummaryList[?DomainName==`'"$HOST"'`].CertificateArn'
aws acm describe-certificate --region "$REGION" --certificate-arn <arn> \
  --query 'Certificate.{status:Status,notAfter:NotAfter,renewal:RenewalSummary,eligible:RenewalEligibility,inUse:InUseBy}'
```

- **DNS-validated:** the validation CNAME (in `DomainValidationOptions`) must still exist in DNS. Deleted CNAMEs are the usual reason renewal stalls at `PENDING_AUTO_RENEWAL`. Re-create the record.
- **Email-validated:** someone must approve the renewal email. Switch to DNS validation.
- **Imported certificates:** ACM never renews them. Re-import a new certificate under the same ARN (`aws acm import-certificate --certificate-arn <arn> ...`), and the load balancer picks it up.
- A certificate that the Ingress annotation `alb.ingress.kubernetes.io/certificate-arn` doesn't reference (or that auto-discovery didn't match) isn't on the listener at all. Check `aws elbv2 describe-listener-certificates`.

## Verify recovery

Re-run the `openssl s_client` check from the start: new `notAfter`, expected issuer. For cert-manager, `kubectl get certificate -n "$NS"` shows `READY True` with a future renewal time.

## Escalate

For ACM renewals that don't progress with validation records in place, open an AWS Support case with the certificate ARN. ACME issues go to the CA's community or status page.

## Prevent

- Alert on certificate expiry from the outside (synthetic checks with 21 days' warning), not just on cert-manager status.
- Alert on `certmanager_certificate_ready_status{condition="False"}`, and on `certmanager_certificate_expiration_timestamp_seconds` being close.
- Use DNS-01 validation for anything behind complex ingress paths.
- Never delete ACM validation CNAMEs; manage them in IaC.

## Background

- [[Kubernetes/concepts/L07-security/01-api-access/04-certificates|Certificates in Kubernetes]]
- [[AWS/security/certificate-manager/README|AWS Certificate Manager]]
- [cert-manager troubleshooting](https://cert-manager.io/docs/troubleshooting/)
