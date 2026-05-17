---
title: AWS CodePipeline for EKS
tags: [eks, automation, ci-cd, codepipeline]
date: 2026-05-17
description: CI/CD pipelines for EKS with AWS CodePipeline
---

# AWS CodePipeline for EKS

## Overview

CodePipeline provides continuous delivery pipelines for deploying to EKS clusters.

## Pipeline Architecture

```
Source (CodeCommit/GitHub) --> Build (CodeBuild) --> Deploy (EKS)
         |                           |
         v                           v
      Artifact                   kubectl apply
```

## Create Build Project

```bash
# Create CodeBuild project
aws codebuild create-project \
  --name eks-deploy-build \
  --service-role arn:aws:iam::123456789:role/CodeBuildRole \
  --artifacts type: no-artifacts \
  --environment type: LINUX_CONTAINER,image: aws/codebuild/amazonlinux2-x86_64-standard:latest,computeType: BUILD_GENERAL1_SMALL
```

## buildspec.yml

```yaml
version: 0.2

env:
  variables:
    EKS_CLUSTER_NAME: my-cluster
    AWS_REGION: us-west-2
  parameter-store:
    KUBE_CONFIG: /kube/config

phases:
  install:
    commands:
      - pip install --upgrade awscli
      - curl -o kubectl https://amazon-eks-connector.s3.us-west-2.amazonaws.com/1.24.7/2023-03-14/bin/linux/amd64/kubectl
      - chmod +x ./kubectl
      - aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION
  build:
    commands:
      - echo "Building Docker image..."
      - docker build -t my-app:$CODEBUILD_BUILD_NUMBER .
      - docker tag my-app:$CODEBUILD_BUILD_NUMBER 123456789.dkr.ecr.us-west-2.amazonaws.com/my-app:$CODEBUILD_BUILD_NUMBER
  post_build:
    commands:
      - echo "Pushing Docker image..."
      - docker push 123456789.dkr.ecr.us-west-2.amazonaws.com/my-app:$CODEBUILD_BUILD_NUMBER
      - echo "Deploying to EKS..."
      - kubectl set image deployment/my-app app=123456789.dkr.ecr.us-west-2.amazonaws.com/my-app:$CODEBUILD_BUILD_NUMBER
      - kubectl rollout status deployment/my-app
```

## Create Pipeline

```bash
aws codepipeline create-pipeline \
  --pipeline name=eks-deploy-pipeline \
  --role-arn arn:aws:iam::123456789:role/CodePipelineRole \
  --artifact-store type:S3,location:my-codepipeline-artifacts \
  --stage name=Source,action name=Source,action-type-id category=Source,owner=AWS,provider=CodeCommit,version=1,output-artifacts=source-output \
  --stage name=Build,action name=Build,action-type-id category=Build,owner=AWS,provider=CodeBuild,version=1,input-artifacts=source-output,output-artifacts=build-output
```

## GitHub Integration

```bash
# Create webhook for GitHub
aws codepipeline create-webhook \
  --pipeline-name eks-deploy-pipeline \
  --webhook-url https://codepipeline.us-west-2.amazonaws.com/webhook \
  --certificate-arn arn:aws:acm:us-west-2:123456789:cert/xxxxx
```

## Rolling Deployments

```yaml
# Update strategy in deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: my-app:latest
```

## References

- [EKS Workshop - CodePipeline](https://www.eksworkshop.com/docs/automation/continuousdelivery/codepipeline/)
- [CI/CD with CodePipeline](https://docs.aws.amazon.com/eks/latest/userguide/cicd.html)