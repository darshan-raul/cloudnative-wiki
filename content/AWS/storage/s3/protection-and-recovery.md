---
title: "S3 protection and recovery"
description: "Combine ownership, public-access prevention, versioning, retention and authorized restores without confusing them with replication."
tags:
  - cloud/aws/storage/s3
date: 2026-10-12
---

# S3 protection and recovery

Start with [[AWS/storage/s3/README|S3]], [[AWS/security/iam/policy-evaluation|authorization]] and [[AWS/reliability/backup-and-recovery|recovery objectives]]. Strong consistency is automatic for supported S3 object operations; it does not protect against authorized destructive changes.

## Independent controls

Object Ownership and Block Public Access address access configuration. Bucket/resource policies, access points and KMS permissions control approved use. OAC authenticates supported CloudFront origin access; a distribution alone does not make a bucket private.

Versioning retains object versions; a delete marker can hide the current object without erasing prior versions. Lifecycle can still delete retained versions. Object Lock governance/compliance retention and legal holds have distinct removal permissions and consequences—do not experiment with irreversible retention on valuable data.

Replication has source/destination, permission, versioning and operation-specific conditions. It is not an unconditional guarantee of immediate replication or backup of every historic/delete operation.

## Sandbox restore exercise

Prerequisites: a private sandbox bucket with versioning, disposable text/object data, least-privilege object/version permissions and a retention/cost plan. Avoid compliance lock for this basic exercise.

1. Upload version A with a known checksum, then version B.
2. Record version IDs and confirm the current read returns B.
3. Delete the current object, inspect versions/delete marker and confirm the ordinary read is hidden.
4. Restore the intended version using the documented version workflow; verify checksum and identity.
5. Test access from an unauthorized sandbox role; expect denial even though the object exists.
6. Review lifecycle before cleanup. Delete only all disposable lab versions and delete markers, then remove the dedicated bucket if appropriate.

For an OAC extension, remove public-read permissions, authorize only the intended distribution and test both CloudFront success and direct-S3 denial. Confirm that shared/personalized content has a safe cache key.

## Recovery acceptance

Verify data, permissions, encryption keys and client behavior. If using retention or copies, test from the actual recovery identity and destination account. A replication status or successful GetObject is only one checkpoint.

Budget stored versions, minimum storage durations, retrieval/restore requests, replicated bytes and logging. Copies multiply stored data and may change deletion obligations.

## References

- [Object Ownership](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html).
- [Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html).
- [Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html).
- [Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html).
- [CloudFront OAC](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html).
