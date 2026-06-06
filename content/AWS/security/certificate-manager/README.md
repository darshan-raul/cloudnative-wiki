---
title: AWS ACM
description: AWS Certificate Manager — public and private TLS/SSL certificates. Managed certificate issuance, auto-renewal, validation via DNS or email, ACM Private CA integration, and CloudFront/ALB integration.
tags:
  - aws
  - security
  - acm
  - tls
  - ssl
---

# AWS Certificate Manager (ACM)

ACM provisions, manages, and deploys TLS certificates for use with AWS services (CloudFront, ALB, API Gateway, CloudFormation) and internal resources.

## Public vs Private Certificates

| Feature | Public Certificate | Private Certificate |
|---------|-------------------|-------------------|
| Issuer | Public CA (DigiCert) | Your own Private CA (ACM PCA) |
| Domain validation | DNS or Email | DNS only |
| Cost | Free (AWS pays DigiCert) | $0.75/month per certificate |
| Browser trusted | Yes (public CA in browsers) | No (requires private PKI) |
| Use case | Public websites, APIs | Internal services, microservices |

## Requesting a Public Certificate

```bash
# Request certificate
aws acm request-certificate \
  --domain-name "example.com" \
  --validation-method DNS \
  --subject-alternative-names "*.example.com" \
  --domain-validation-options '[
    {
      "DomainName": "example.com",
      "ValidationDomain": "example.com"
    }
  ]'
```

### DNS Validation

```bash
# Get the CNAME records to add
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/xxxxx \
  --query 'Certificate.DomainValidationOptions'

# Example response:
# [
#   {
#     "DomainName": "example.com",
#     "ValidationDomain": "example.com",
#     "ValidationMethod": "DNS",
#     "ResourceRecord": {
#       "Name": "_abc123.example.com",
#       "Type": "CNAME",
#       "Value": "_def456.acm-validations.aws"
#     }
#   }
# ]

# Add the CNAME to Route 53
aws route53 change-resource-record-sets \
  --hosted-zone-id Zxxxxx \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "_abc123.example.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "_def456.acm-validations.aws"}]
      }
    }]
  }'

# Wait for validation
aws acm wait certificate-validated \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/xxxxx
```

### Email Validation

```bash
# Request with email validation
aws acm request-certificate \
  --domain-name "example.com" \
  --validation-method EMAIL \
  --subject-alternative-names "*.example.com"

# Check validation email status
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/xxxxx
```

## Importing an External Certificate

```bash
# Get certificate, private key, and chain
CERT=$(cat server.crt)
KEY=$(cat server.key)
CHAIN=$(cat ca-bundle.crt)

aws acm import-certificate \
  --certificate "$CERT" \
  --private-key "$KEY" \
  --certificate-chain "$CHAIN" \
  --tags '[{"Key": "Environment", "Value": "production"}]'
```

## ACM with CloudFront

```bash
# CloudFront distribution with ACM certificate
aws cloudfront create-distribution \
  --distribution-config '{
    "CallerReference": "my-app",
    "Comment": "My app",
    "Enabled": true,
    "Aliases": {"Quantity": 1, "Items": ["app.example.com"]},
    "DefaultRootObject": "index.html",
    "Origins": {
      "Quantity": 1,
      "Items": [{
        "Id": "my-origin",
        "DomainName": "my-app.s3.amazonaws.com",
        "S3OriginConfig": {}
      }]
    },
    "DefaultCacheBehavior": {
      "TargetOriginId": "my-origin",
      "ViewerProtocolPolicy": "redirect-to-https",
      "TrustedSigners": {"Enabled": false, "Quantity": 0}
    },
    "ViewerCertificate": {
      "ACMCertificateArn": "arn:aws:acm:us-east-1:123456789012:certificate/xxxxx",
      "SSLSupportMethod": "sni-only",
      "MinimumProtocolVersion": "TLSv1.2_2021"
    }
  }'
```

## ACM with ALB

```bash
# Create HTTPS listener with ACM certificate
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/xxxxx \
  --protocol HTTPS \
  --port 443 \
  --certificates '[{"CertificateArn": "arn:aws:acm:us-east-1:123456789012:certificate/xxxxx"}]' \
  --default-actions '[{"Type": "forward", "TargetGroupArn": "arn:aws:elasticloadbalancing:..."}]'
```

## Private CA (ACM PCA)

```bash
# Create a Private CA
aws acm-pca create-certificate-authority \
  --certificate-authority-type ROOT \
  --subject '{
    "Country": "US",
    "State": "California",
    "Locality": "San Francisco",
    "Organization": "My Company",
    "CommonName": "My Internal CA"
  }' \
  --key-algorithm RSA_2048 \
  --signing-algorithm SHA256WITHRSA \
  --validity '{
    "Value": 3650,
    "Type": "DAYS"
  }'

# Issue a private certificate
aws acm request-certificate \
  --domain-name "internal.example.com" \
  --certificate-authority-arn arn:aws:acm-pca:us-east-1:123456789012:certificate-authority/xxxxx \
  --idempotency-token my-token
```

## Monitoring Expiration

```bash
# List certificates expiring within 30 days
aws acm list-certificates \
  --certificate-statuses ACTIVE \
  --query 'CertificateSummaryList[?length(ExpiryDate)>`date`]'

# CloudWatch alarm for certificate expiration
aws cloudwatch put-metric-alarm \
  --alarm-name acm-certificate-expiry \
  --alarm-description "Certificate expires within 30 days" \
  --metric-name DaysToExpiry \
  --namespace AWS/CertificateManager \
  --statistic Minimum \
  --period 86400 \
  --threshold 30 \
  --comparison-operator LessThanThreshold \
  --dimensions '[{"Name": "CertificateId", "Value": "xxxxx"}]' \
  --evaluation-periods 1
```

## Pricing

| Component | Cost |
|-----------|------|
| Public certificates | Free (AWS pays DigiCert) |
| Private certificates (ACM PCA) | $0.75/month per CA + $0.05/issuance |
| Certificate issuance (private CA) | $0.05 per certificate |
| Cross-region certificate copies | Free |

## Limits

| Resource | Limit |
|----------|-------|
| Public certificates per account | 25,000 |
| Private CAs per account | 10 |
| Subject Alternative Names per certificate | 100 |
| Private certificates per CA | Unlimited |

## References

- **Homepage:** https://aws.amazon.com/certificate-manager/
- **Documentation:** https://docs.aws.amazon.com/acm/
- **Pricing:** https://aws.amazon.com/certificate-manager/pricing/

## Pricing Examples

**Scenario 1:** A public website with 1 certificate covering main domain + wildcard (e.g., example.com + *.example.com). Public certificates are free = $0/month. Compare to buying from DigiCert ($200-500/year).

**Scenario 2:** An internal microservices platform with 50 services needing TLS. 50 private certificates × $0.75/month = $37.50/month. Plus $0.05 × 50/month issuance = $2.50/month. Total: $40/month. Compare to self-managed PKI: $0 software but significant operational overhead.

## Nuggets & Gotchas

- **ACM doesn't support certificates < 1024 bits or > 4096 bits — use 2048 or 4096 RSA:** Modern browsers require 2048-bit minimum. 1024-bit certificates are rejected by most browsers and are considered insecure.
- **ACM auto-renewal only works if DNS validation is reachable — email validation requires manual action:** If your DNS provider doesn't support automated CNAME updates, you'll need to manually renew every 13 months. Use DNS validation with Route 53 for fully automated renewal.
- **ACM certificates for CloudFront must be in us-east-1 (N. Virginia) — even if your CloudFront is in another region:** This is a CloudFront limitation. All ACM certificates used with CloudFront must be in us-east-1.
- **ACM Private CA certificates can't be exported — they're managed by AWS:** If you need the private key (for non-AWS services), use ACM PCA with a template that allows export, or import a certificate with its private key.
- **ACM certificate CNAME records must remain in DNS even after validation — AWS checks periodically:** If you remove the validation CNAME after the certificate is issued, AWS may re-validate and fail. Keep the CNAME record in place as long as the certificate is active.