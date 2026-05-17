---
title: Secrets Management on EKS
tags: [eks, security, secrets]
date: 2026-05-17
description: Managing secrets on EKS - AWS Secrets Manager and Sealed Secrets
---

# Secrets Management on EKS

## Overview

Securely manage sensitive data like passwords, API keys, and certificates in EKS.

## Topics

### [[Kubernetes/eks/security/secrets-management/secrets-manager|AWS Secrets Manager]]
Store and retrieve secrets using AWS Secrets Manager with IRSA

### [[Kubernetes/eks/security/secrets-management/sealed-secrets|Sealed Secrets]]
GitOps-friendly secrets encrypted with public key

## Comparison

| Approach | Encryption | GitOps Friendly | Rotation |
|----------|-----------|-----------------|----------|
| Kubernetes Secrets | Base64 | No (plaintext in YAML) | Manual |
| AWS Secrets Manager | AWS KMS | No | Automatic |
| Sealed Secrets | Asymmetric | Yes | Manual |

## References

- [EKS Workshop - Secrets Management](https://www.eksworkshop.com/docs/security/secrets-management/)