---
title: Helm CI/CD
tags: [kubernetes, helm, cicd, github-actions, gitlab, jenkins]
date: 2026-05-16
description: CI/CD pipeline integration for Helm charts
---

# Helm CI/CD

Integrating Helm into CI/CD pipelines enables automated testing, versioning, and deployment of Kubernetes applications.

## Pipeline Overview

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  Build  │───▶│  Test   │───▶│ Package │───▶│ Deploy  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
     │              │              │              │
  Source       Lint +         Chart         staging/
  Code         Unit Test     Version       prod
                                │
                                ▼
                          ┌─────────┐
                          │ Registry│
                          └─────────┘
```

## GitHub Actions

### Basic Chart Lint & Test

```yaml
# .github/workflows/chart-test.yml
name: Helm Chart Test

on:
  push:
    branches: [main]
    paths:
      - 'charts/**'
  pull_request:
    paths:
      - 'charts/**'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4
        with:
          version: v3.14

      - name: Add chart repos
        run: |
          helm repo add bitnami https://charts.bitnami.com
          helm repo update

      - name: Lint chart
        run: |
          helm lint --strict charts/myapp

      - name: Run helm unittest
        if: github.event_name == 'pull_request'
        run: |
          helm plugin install https://github.com/helm/helm-unittest
          helm unittest charts/myapp

  template:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4

      - name: Template chart
        run: |
          helm template myapp charts/myapp \
            -f charts/myapp/values.yaml \
            --validate \
            --debug
```

### Package and Publish Chart

```yaml
# .github/workflows/chart-release.yml
name: Release Helm Chart

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Helm
        uses: azure/setup-helm@v4
        with:
          version: v3.14

      - name: Configure git
        run: |
          git config user.name "$GITHUB_ACTOR"
          git config user.email "$GITHUB_ACTOR@users.noreply.github.com"

      - name: Package chart
        id: package
        run: |
          helm package charts/myapp
          CHART_VERSION=$(helm show chart charts/myapp | grep version: | awk '{print $2}')
          echo "version=$CHART_VERSION" >> $GITHUB_OUTPUT

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: ./*.tgz
          generate_release_notes: true

      - name: Push to OCI Registry
        uses: azure/docker-login@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push chart to GHCR
        run: |
          helm push myapp-*.tgz oci://ghcr.io/${{ github.repository_owner }}/charts

      - name: Update index
        run: |
          export HELM_EXPERIMENTAL_OCI=1
          helm cm-push myapp-*.tgz oci://ghcr.io/${{ github.repository_owner }}/charts || true
```

### Multi-Environment Deploy

```yaml
# .github/workflows/deploy.yml
name: Deploy Helm Chart

on:
  push:
    branches: [main]
    paths:
      - 'charts/**'
      - 'environments/**'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/myapp

jobs:
  deploy-dev:
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4

      - name: Set up kubectl
        uses: azure/setup-kubectl@v4

      - name: Configure kubectl
        run: |
          echo "$KUBECONFIG_DEV" > ~/.kube/config

      - name: Get image tag
        run: |
          GIT_SHORT_SHA=$(echo ${{ github.sha }} | cut -c1-7)
          echo "IMAGE_TAG=${GIT_SHORT_SHA}" >> $GITHUB_OUTPUT

      - name: Deploy to Dev
        run: |
          helm upgrade --install myapp charts/myapp \
            --namespace myapp-dev \
            --create-namespace \
            -f charts/myapp/values.yaml \
            -f environments/dev/values.yaml \
            --set image.tag=${{ env.IMAGE_TAG }} \
            --wait --atomic --timeout 5m

  deploy-staging:
    runs-on: ubuntu-latest
    needs: deploy-dev
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4

      - name: Configure kubectl
        run: |
          echo "$KUBECONFIG_STAGING" > ~/.kube/config

      - name: Deploy to Staging
        run: |
          helm upgrade --install myapp charts/myapp \
            --namespace myapp-staging \
            --create-namespace \
            -f charts/myapp/values.yaml \
            -f environments/staging/values.yaml \
            --set image.tag=latest \
            --wait --atomic --timeout 5m
```

## GitLab CI

### Basic Pipeline

```yaml
# .gitlab-ci.yml
stages:
  - lint
  - test
  - package
  - deploy

variables:
  CHART_NAME: myapp
  CHART_PATH: charts/myapp

helm-lint:
  stage: lint
  image: alpine/helm:latest
  script:
    - helm lint --strict $CHART_PATH

helm-template:
  stage: test
  image: alpine/helm:latest
  script:
    - helm template test $CHART_PATH -f $CHART_PATH/values.yaml --validate

helm-test:
  stage: test
  image: alpine/helm:latest
  needs:
    - helm-template
  script:
    - helm plugin install https://github.com/helm/helm-unittest
    - helm unittest $CHART_PATH

package-chart:
  stage: package
  image: alpine/helm:latest
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - helm package $CHART_PATH
    - helm push $(ls *.tgz) $CI_REGISTRY/charts
    - helm repo update
  artifacts:
    paths:
      - "*.tgz"
  rules:
    - if: $CI_COMMIT_TAG

deploy-dev:
  stage: deploy
  image: bitnami/kubectl:latest
  needs:
    - package-chart
  environment:
    name: dev
  script:
    - kubectl config use-context dev-cluster
    - helm upgrade --install $CHART_NAME charts/$CHART_NAME \
      --namespace myapp \
      --create-namespace \
      -f charts/$CHART_NAME/values.yaml \
      -f environments/dev/values.yaml \
      --wait --atomic
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy-prod:
  stage: deploy
  image: bitnami/kubectl:latest
  needs:
    - deploy-dev
  environment:
    name: production
  script:
    - kubectl config use-context prod-cluster
    - helm upgrade --install $CHART_NAME charts/$CHART_NAME \
      --namespace myapp \
      --create-namespace \
      -f charts/$CHART_NAME/values.yaml \
      -f environments/prod/values.yaml \
      --wait --atomic
  when: manual
  rules:
    - if: $CI_COMMIT_TAG =~ /^v[0-9]+/
```

### Advanced GitLab CI with OCI

```yaml
# .gitlab-ci.yml
variables:
  HELM_EXPERIMENTAL_OCI: "1"
  CHART_REGISTRY: $CI_REGISTRY_IMAGE/charts

stages:
  - verify
  - package
  - deploy

lint:
  stage: verify
  image: alpine/helm:latest
  script:
    - helm lint --strict charts/myapp

unittest:
  stage: verify
  image: alpine/helm:latest
  script:
    - helm plugin install https://github.com/helm/helm-unittest
    - helm unittest charts/myapp

package:
  stage: package
  image: docker:latest
  services:
    - docker:dind
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build -t $CHART_REGISTRY:$CI_COMMIT_SHA charts/myapp
    - docker push $CHART_REGISTRY:$CI_COMMIT_SHA
    - docker tag $CHART_REGISTRY:$CI_COMMIT_SHA $CHART_REGISTRY:$CI_COMMIT_REF_NAME
    - docker push $CHART_REGISTRY:$CI_COMMIT_REF_NAME
  only:
    - main
    - tags

deploy-staging:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - kubectl config use-context staging
    - helm upgrade --install myapp oci://$CI_REGISTRY/charts/myapp \
      --version $CI_COMMIT_SHA \
      --namespace staging \
      --create-namespace \
      -f environments/staging/values.yaml \
      --wait --atomic
  environment:
    name: staging
    url: https://staging.myapp.example.com
  only:
    - main

deploy-prod:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - kubectl config use-context prod
    - helm upgrade --install myapp oci://$CI_REGISTRY/charts/myapp \
      --version $CI_COMMIT_TAG \
      --namespace production \
      --create-namespace \
      -f environments/prod/values.yaml \
      --wait --atomic
  environment:
    name: production
  only:
    - tags
  when: manual
```

## Jenkins

### Jenkinsfile (Declarative)

```groovy
// Jenkinsfile
pipeline {
    agent any

    environment {
        CHART_NAME = 'myapp'
        CHART_PATH = "charts/${CHART_NAME}"
        REGISTRY = 'ghcr.io'
        IMAGE_NAME = "${REGISTRY}/${env.GITHUB_ORG}/${CHART_NAME}"
    }

    stages {
        stage('Lint') {
            steps {
                sh 'helm lint --strict ${CHART_PATH}'
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    helm plugin install https://github.com/helm/helm-unittest || true
                    helm unittest ${CHART_PATH}
                '''
            }
        }

        stage('Template Test') {
            steps {
                sh '''
                    helm template test ${CHART_PATH} \
                        -f ${CHART_PATH}/values.yaml \
                        --validate \
                        --debug > /dev/null
                '''
            }
        }

        stage('Package') {
            steps {
                sh '''
                    helm package ${CHART_PATH}
                    CHART_VERSION=$(helm show chart ${CHART_PATH} | grep version: | awk '{print $2}')
                    echo "CHART_VERSION=${CHART_VERSION}" > chart_version.properties
                '''
                archiveArtifacts artifacts: '*.tgz'
            }
        }

        stage('Push to Registry') {
            when {
                buildingTag()
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'ghcr', usernameVariable: 'USERNAME', passwordVariable: 'TOKEN')]) {
                    sh '''
                        echo $TOKEN | docker login ${REGISTRY} -u $USERNAME --password-stdin
                        helm push ${CHART_NAME}-*.tgz oci://${REGISTRY}/${env.GITHUB_ORG}/charts
                    '''
                }
            }
        }

        stage('Deploy to Dev') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([file(variable: 'KUBECONFIG_DEV', credentialsId: 'kubeconfig-dev')]) {
                    sh '''
                        kubectl config use-context dev
                        helm upgrade --install ${CHART_NAME} ${CHART_PATH} \
                            --namespace ${CHART_NAME}-dev \
                            --create-namespace \
                            -f ${CHART_PATH}/values.yaml \
                            -f environments/dev/values.yaml \
                            --set image.tag=${GIT_COMMIT[0:7]} \
                            --wait --atomic --timeout 5m
                    '''
                }
            }
        }

        stage('Deploy to Staging') {
            when {
                branch 'main'
            }
            steps {
                input message: 'Deploy to Staging?', ok: 'Deploy'
                withCredentials([file(variable: 'KUBECONFIG_STAGING', credentialsId: 'kubeconfig-staging')]) {
                    sh '''
                        kubectl config use-context staging
                        helm upgrade --install ${CHART_NAME} ${CHART_PATH} \
                            --namespace ${CHART_NAME}-staging \
                            --create-namespace \
                            -f ${CHART_PATH}/values.yaml \
                            -f environments/staging/values.yaml \
                            --wait --atomic --timeout 5m
                    '''
                }
            }
        }

        stage('Deploy to Production') {
            when {
                buildingTag()
            }
            steps {
                input message: 'Deploy to Production?', ok: 'Deploy'
                withCredentials([file(variable: 'KUBECONFIG_PROD', credentialsId: 'kubeconfig-prod')]) {
                    sh '''
                        kubectl config use-context prod
                        helm upgrade --install ${CHART_NAME} ${CHART_PATH} \
                            --namespace ${CHART_NAME}-prod \
                            --create-namespace \
                            -f ${CHART_PATH}/values.yaml \
                            -f environments/prod/values.yaml \
                            --wait --atomic --timeout 10m
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed!'
        }
    }
}
```

## Chart Versioning

### Semantic Versioning

```bash
# Extract version from Chart.yaml
CHART_VERSION=$(grep '^version:' Chart.yaml | cut -d' ' -f2)

# Use SemVer format: MAJOR.MINOR.PATCH
# Example: v1.2.3-rc.1+build.123

# Git tag for release
git tag -a v${CHART_VERSION} -m "Release ${CHART_VERSION}"
git push origin v${CHART_VERSION}
```

### Automated Versioning with chart-releaser

```yaml
# .github/workflows/release.yml
name: Release Charts
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Configure git
        run: |
          git config user.name "github-actions"
          git config user.email "github-actions@github.com"

      - name: Run chart-releaser
        uses: helm/chart-releaser-action@v1
        with:
          charts_dir: charts
        env:
          CR_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### chart-releaser config (cr.yaml)

```yaml
# cr.yaml
charts-dir: charts
owner: myorg
repo: myrepo
excludes:
  - name: common
    keep: true
```

## Pre-commit Hooks

### pre-commit Configuration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: helm-lint
        name: Helm lint
        entry: helm lint --strict
        language: system
        files: ^charts/
        pass_filenames: false

      - id: helm-template-check
        name: Helm template check
        entry: bash -c 'helm template test "$0" -f "$0/values.yaml" --validate > /dev/null 2>&1'
        language: system
        files: ^charts/
        pass_filenames: true
        args:
          - charts/myapp

      - id: helm-unittest
        name: Helm unit tests
        entry: helm unittest
        language: system
        files: ^charts/
        pass_filenames: false

      - id: helm-docs
        name: Helm docs
        entry: helm-docs
        language: golang
        files: ^charts/
        pass_filenames: false

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
```

## Chart Testing in CI

### ct (chart-testing) Tool

```yaml
# .github/workflows/ct.yml
name: Chart Testing
on:
  push:
    branches: [main]
    paths:
      - 'charts/**'
  pull_request:

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Helm
        uses: azure/setup-helm@v4

      - name: Set up chart-testing
        uses: helm/chart-testing-action@v2

      - name: Add chart repos
        run: |
          helm repo add bitnami https://charts.bitnami.com
          helm repo update

      - name: Lint
        run: ct lint --config .ct.yaml --charts charts/myapp

      - name: Kind
        uses: helm/kind-action@v1
        with:
          cluster_name: chart-testing

      - name: Test
        run: ct lint-and-test --config .ct.yaml --charts charts/myapp
```

### ct.yaml Configuration

```yaml
# .ct.yaml
remote: origin
target-branch: main
chart-repos:
  - name=bitnami https://charts.bitnami.com
lint-conf: .chart-lintconf.yaml
validate-maintainers: false
check-version-increment: true
```

## Security Scanning

### Trivy in CI

```yaml
# .github/workflows/security.yml
name: Security Scan
on: [push, pull_request]

jobs:
  trivy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Trivy
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: 'charts/myapp'
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: Upload to GitHub Security
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'
```

### Helm Security Best Practices

```yaml
# In values.yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

podSecurityContext:
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
```

## Image Management in CI

### Build and Push Image

```yaml
# .github/workflows/build.yml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/myapp
          tags: |
            type=sha,prefix=
            type=semver,pattern={{version}}
            type=raw,value=latest

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Output image digest
        run: |
          DIGEST=$(openssl dgst -sha256 -hex <<< "${{ steps.meta.outputs.tags }}" | awk '{print $2}')
          echo "digest=sha256:$DIGEST" >> $GITHUB_OUTPUT
```

### Update Chart with New Image

```yaml
# .github/workflows/update-chart.yml
jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Update image tag
        run: |
          SHA=${{ github.sha }}
          SHORT_SHA=${SHA:0:7}
          
          # Update values.yaml
          yq e '.image.tag = env(short_sha)' -i charts/myapp/values.yaml
          
          # Or using sed
          sed -i "s/image:.*/image: myapp:${SHORT_SHA}/" charts/myapp/values.yaml

      - name: Create PR
        uses: peter-evans/create-pull-request@v5
        with:
          title: "chore: update image to ${SHORT_SHA}"
          commit-message: "chore: update image tag"
```

## Environment Promotion

### Promotion Pipeline

```yaml
# .github/workflows/promote.yml
name: Promote Chart

on:
  workflow_dispatch:
    inputs:
      from_env:
        description: 'From environment'
        required: true
        type: choice
        options:
          - dev
          - staging
      to_env:
        description: 'To environment'
        required: true
        type: choice
        options:
          - staging
          - prod

jobs:
  promote:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4

      - name: Get current version
        run: |
          # Get version from source env
          helm get values myapp -n myapp-${{ inputs.from_env }} -o yaml > values.yaml
          
      - name: Update values
        run: |
          # Modify for target environment
          yq e '.replicaCount = 5' -i values.yaml
          
      - name: Deploy to target
        run: |
          helm upgrade --install myapp charts/myapp \
            --namespace myapp-${{ inputs.to_env }} \
            --create-namespace \
            -f values.yaml \
            --wait --atomic --timeout 5m
```

## Vault Integration

### Inject Secrets from Vault

```bash
# Get secret from Vault
vault kv get -field=password secret/myapp/db > password.txt

# Use in helm
helm upgrade --install myapp ./charts/myapp \
  --set-file db.password=password.txt
```

```yaml
# In deployment template
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ include "myapp.fullname" . }}-db
        key: password
```

### Vault Agent Injector

```yaml
# annotations for vault injection
template: |
  spec:
    containers:
      - name: myapp
        env:
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: db-credentials
                key: password
```

## Troubleshooting CI/CD

### Debug Helm Installation

```bash
# Verbose output
helm upgrade --install myapp ./charts/myapp --debug --dry-run

# Check release status
helm status myapp
helm history myapp

# Get values
helm get values myapp --all

# Get manifest
helm get manifest myapp

# View hooks
helm get hooks myapp
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Chart not found | `helm repo update` and check repository |
| Template syntax error | Use `--dry-run --debug` to debug |
| Hooks failing | Check hook annotations and Job specs |
| Image pull error | Verify image pull secrets exist |
| Resource conflict | Use `--atomic` or `--force` |

### Debug CI Jobs

```yaml
# Add debugging step
- name: Debug
  run: |
    echo "Chart path: ${{ env.CHART_PATH }}"
    echo "Image tag: ${{ env.IMAGE_TAG }}"
    helm upgrade --install myapp ${{ env.CHART_PATH }} --debug --dry-run
  shell: bash
```

## References

- [Helm Documentation](https://helm.sh/docs/)
- [Azure Setup Helm Action](https://github.com/azure/setup-helm)
- [Helm Chart Testing Action](https://github.com/helm/chart-testing-action)
- [Helm Kind Action](https://github.com/helm/kind-action)
- [Chart Releaser Action](https://github.com/helm/chart-releaser-action)
- [Trivy Security Scanner](https://aquasecurity.github.io/trivy/)
- [helm-secrets Plugin](https://github.com/jkroepke/helm-secrets)