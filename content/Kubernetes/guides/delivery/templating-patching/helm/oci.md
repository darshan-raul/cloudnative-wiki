---
title: Helm OCI & Registries
tags: [kubernetes, helm, oci, registry, provenance]
date: 2026-05-16
description: OCI registry support, chart provenance, and signing
---

# Helm OCI & Registries

Helm 3+ supports OCI registries for storing and distributing charts, providing a secure, cloud-native approach to chart management.

## OCI Registry Overview

OCI (Open Container Initiative) registries store Helm charts as container images. Supported registries include:

- **AWS**: Amazon ECR, Amazon ECR Public
- **Azure**: Azure Container Registry (ACR)
- **GCP**: Google Artifact Registry (GAR)
- **Docker**: Docker Hub, GHCR (GitHub Container Registry)
- **Enterprise**: Harbor, JFrog Artifactory, Cloudsmith, Zot

## OCI Fundamentals

```
oci://<registry>/<image>:<tag>
oci://ghcr.io/org/charts/myapp:v1.0.0
oci://myregistry.azurecr.io/helm/myapp:sha256-abc123
```

### Key Differences from Chart Repos

| Feature | Chart Repository | OCI Registry |
|---------|------------------|--------------|
| Index | index.yaml | Manifest |
| Storage | HTTP server | Container registry |
| Authentication | Basic auth | Registry auth |
| Helm support | Native | Native (Helm 3+) |
| Artifact types | Charts only | Multiple (charts, images) |

## Pushing Charts to OCI Registry

### Package and Push

```bash
# Enable OCI support
export HELM_EXPERIMENTAL_OCI=1

# Login to registry
helm registry login ghcr.io

# Or with credentials
helm registry login -u username ghcr.io

# Package chart
helm package ./charts/myapp

# Push to registry
helm push myapp-1.0.0.tgz oci://ghcr.io/org/charts/myapp

# Push with provenance (automatic if .prov file exists)
helm push myapp-1.0.0.tgz oci://ghcr.io/org/charts/myapp
# Provenance file will be pushed as separate layer
```

### Push with Automatic Version

```bash
# Version from Chart.yaml
helm push ./charts/myapp oci://ghcr.io/org/charts

# The tag is derived from chart version (SemVer)
# myapp:1.2.3
```

## Pulling Charts from OCI Registry

### Install from OCI

```bash
# Basic install
helm install myapp oci://ghcr.io/org/charts/myapp

# With version
helm install myapp oci://ghcr.io/org/charts/myapp --version 1.2.3

# With digest (most secure, immutable)
helm install myapp oci://ghcr.io/org/charts/myapp@sha256:abc123...

# Pull chart
helm pull oci://ghcr.io/org/charts/myapp --version 1.2.3

# Show chart info
helm show all oci://ghcr.io/org/charts/myapp --version 1.2.3

# Template locally
helm template myapp oci://ghcr.io/org/charts/myapp --version 1.2.3
```

### Pull with Authentication

```bash
# Login first
helm registry login <registry>

# Then pull/install
helm pull oci://myregistry.azurecr.io/charts/myapp --version 1.0.0
```

## Registry Authentication

### AWS ECR

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  helm registry login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com

# Push
helm push myapp-1.0.0.tgz oci://<account>.dkr.ecr.us-east-1.amazonaws.com/charts/myapp
```

### Azure Container Registry

```bash
# Login to ACR
az acr login --name myregistry

# Get admin password if needed
ACR_PASSWORD=$(az acr credential show --name myregistry --query passwords[0].value -o tsv)

# Login to Helm
helm registry login myregistry.azurecr.io -u myuser -p $ACR_PASSWORD
```

### Google Artifact Registry

```bash
# Authenticate
gcloud auth configure-docker us-central1-docker.pkg.dev

# Login
helm registry login us-central1-docker.pkg.dev

# Or use key file
cat key.json | helm registry login -u _json_key us-central1-docker.pkg.dev
```

### GHCR (GitHub Container Registry)

```bash
# Generate token with packages:write permission
GITHUB_TOKEN=ghp_xxx

# Login
echo $GITHUB_TOKEN | helm registry login ghcr.io -u <username> --password-stdin

# Push
helm push myapp-1.0.0.tgz oci://ghcr.io/org/charts/myapp
```

## Chart Signing & Provenance

### Sign Chart with GPG

```bash
# Create GPG key if needed
gpg --gen-key

# List secret keys
gpg --list-secret-keys

# Package and sign
helm package --sign --key 'Your Name' --keyring ~/.gnupg/secring.gpg ./mychart

# This creates:
# - mychart-1.0.0.tgz
# - mychart-1.0.0.tgz.prov (provenance file)
```

### Verify Chart

```bash
# Import public key (if needed)
gpg --import public-key.asc

# Verify
helm verify ./mychart-1.0.0.tgz

# Verify with keyring
helm verify --keyring ~/.gnupg/pubring.gpg ./mychart-1.0.0.tgz

# Install with verification
helm install --verify myapp ./mychart-1.0.0.tgz
```

### Provenance File Structure

```yaml
# mychart-1.0.0.tgz.prov
Hash: SHA512
apiVersion: v2
appVersion: "1.16.0"
description: A Helm chart for Kubernetes
name: mychart
type: application
version: 1.0.0
...

files:
  mychart-1.0.0.tgz: sha256:d31d2f08b885ec696c37c7f7ef106709aaf5e8575b6d3dc5d52112ed29a9cb92

-----BEGIN PGP SIGNATURE-----
...
-----END PGP SIGNATURE-----
```

### Sigstore Integration (Recommended)

```bash
# Install helm-sigstore plugin
helm plugin install https://github.com/sigstore/helm-sigstore

# Sign with sigstore (uses transparency log)
helm sigstore sign --namespace default mychart-1.0.0.tgz

# Upload to transparency log
helm sigstore upload mychart-1.0.0.tgz.prov

# Verify from transparency log
helm sigstore verify mychart-1.0.0.tgz
```

## OCI with Helmfile

```yaml
# helmfile.yaml
repositories:
  - name: oci-registry
    url: oci://ghcr.io/org/charts

releases:
  - name: myapp
    chart: oci://ghcr.io/org/charts/myapp
    version: "1.2.3"
    values:
      - environments/prod/values.yaml
```

## Helmfile with OCI Dependencies

```yaml
# Chart.yaml with OCI dependency
dependencies:
  - name: common-lib
    version: "1.0.0"
    repository: "oci://ghcr.io/org/charts/common-lib"
```

```bash
# Update dependencies (supports OCI)
helm dependency update ./mychart
```

## Multi-Architecture Charts

### Build for Multiple Platforms

```bash
# Create multi-arch manifest
helm manifest generate ./mychart > manifests.yaml

# Push with multiple architectures
helm push myapp-1.0.0.tgz \
  --platform linux/amd64 \
  --platform linux/arm64 \
  oci://ghcr.io/org/charts/myapp
```

## Repository Structure Best Practices

### OCI Repository Naming

```
# Organization level
oci://ghcr.io/org/charts/myapp
oci://myregistry.azurecr.io/helm/myapp

# Product level
oci://gar.googleapis.com/my-project/myapp
```

### Repository per Environment

```bash
# Dev environment
oci://ghcr.io/org/dev/myapp:v1.0.0

# Staging environment
oci://ghcr.io/org/staging/myapp:v1.0.0

# Production environment
oci://ghcr.io/org/prod/myapp:v1.0.0
```

## Security Considerations

### Image Digest (Immutable Reference)

```bash
# Always use digest for production
helm install myapp oci://ghcr.io/org/charts/myapp@sha256:abc123...

# Get digest
helm show all oci://ghcr.io/org/charts/myapp --version 1.0.0 | grep digest

# Verify digest matches expected
helm pull oci://ghcr.io/org/charts/myapp@sha256:abc123...
```

### RBAC for Registries

```yaml
# ECR IAM policy for Helm operations
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages"
      ],
      "Resource": "arn:aws:ecr:*:*:repository/*"
    }
  ]
}
```

### Harbor OCI Support

```bash
# Login to Harbor
helm registry login harbor.example.com -u admin -p Harbor123

# Push chart
helm push myapp-1.0.0.tgz oci://harbor.example.com/library/charts/myapp

# Install from Harbor
helm install myapp oci://harbor.example.com/library/charts/myapp --version 1.0.0
```

## Migrating from Chart Repositories

### Export from Chart Repo

```bash
# Pull from old repo
helm pull old-repo/myapp --version 1.0.0

# Push to OCI
helm push myapp-1.0.0.tgz oci://ghcr.io/org/charts/myapp
```

### Batch Migration Script

```bash
#!/bin/bash
# migrate.sh

OLD_REPO="https://charts.example.com"
NEW_REGISTRY="oci://ghcr.io/org/charts"

# Get all chart versions
helm search repo $OLD_REPO/myapp --versions | tail -n +2 | while read line; do
  VERSION=$(echo $line | awk '{print $2}')
  
  # Pull chart
  helm pull $OLD_REPO/myapp --version $VERSION
  
  # Push to OCI
  helm push myapp-$VERSION.tgz $NEW_REGISTRY/myapp
  
  # Cleanup
  rm -f myapp-$VERSION.tgz
done
```

## Troubleshooting OCI Operations

### Common Issues

| Error | Solution |
|-------|----------|
| `unsupported protocol scheme "oci"` | Set `HELM_EXPERIMENTAL_OCI=1` |
| `authentication required` | Run `helm registry login` |
| `manifest unknown` | Check tag/version exists |
| `name invalid` | Use lowercase, no special chars |
| `application/octet-stream` | Registry may not support OCI |

### Debug OCI Operations

```bash
# Enable debug output
export HELM_EXPERIMENTAL_OCI=1
helm install --debug myapp oci://ghcr.io/org/charts/myapp

# Check registry connectivity
curl -u user:pass https://ghcr.io/v2/

# Verify image exists
helm show all oci://ghcr.io/org/charts/myapp --version 1.0.0
```

## CI/CD with OCI Registries

### GitHub Actions OCI Push

```yaml
# .github/workflows/oci-publish.yml
name: Publish to OCI

on:
  push:
    tags:
      - 'v*'

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4
        with:
          version: v3.14

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Package and push
        run: |
          export HELM_EXPERIMENTAL_OCI=1
          helm package charts/myapp
          
          VERSION=$(helm show chart charts/myapp | grep version: | awk '{print $2}')
          helm push myapp-${VERSION}.tgz oci://ghcr.io/${{ github.repository_owner }}/charts
```

## References

- [OCI Registry Support](https://helm.sh/docs/topics/registries/)
- [Helm Provenance](https://helm.sh/docs/topics/provenance/)
- [Sigstore for Helm](https://github.com/sigstore/helm-sigstore)
- [AWS ECR Helm](https://docs.aws.amazon.com/AmazonECR/latest/userguide/push-oci-artifact.html)
- [Azure ACR Helm](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-helm-repos)
- [GCP Artifact Registry](https://cloud.google.com/artifact-registry/docs/helm/manage-charts)