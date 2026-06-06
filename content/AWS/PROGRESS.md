---
title: AWS Vault Progress Tracker
description: Tracks progress of AWS section restructuring — categories, notes written, stubs remaining
tags:
  - aws
  - tracking
---

# AWS Vault Progress

## Categories

- [x] **compute** — References + Pricing + Nuggets on all files (ec2, lambda, ecs, eks, batch, lightsail)
- [x] **storage** — References + Pricing + Nuggets on all files (s3, ebs, efs, fsx, glacier, storage-gateway)
- [x] **databases** — References + Pricing + Nuggets on all files (rds, aurora, dynamodb, elasticache, redshift, documentdb, neptune, qldb, timestream)
- [x] **networking** — References + Pricing + Nuggets on all files
- [x] **security** — References + Pricing + Nuggets on all files (iam, kms, cloudtrail, guardduty, security-hub, inspector, macie, secrets-manager, certificate-manager, detective, config)
- [x] **management-governance** — References + Pricing + Nuggets on all files (orgs, control-tower, cloudformation, cdk, cli, systems-manager)
- [x] **monitoring** — References + Pricing + Nuggets on all files (metrics, logs, alarms, dashboards, events, insights)
- [x] **application-integration** — References + Pricing + Nuggets on all files (sqs, sns, eventbridge, step-functions, amazon-mq, appsync)
- [x] **serverless** — References + Pricing + Nuggets on all files (lambda, api-gateway, app-runner)
- [ ] containers (ecs, eks, app-mesh)
- [x] **migration** — References + Pricing Examples + Nuggets added to migration/README.md
- [ ] developer-tools (codecommit, codebuild, codedeploy, codepipeline, xray)
- [x] **machine-learning** — References + Pricing + Nuggets on all files (ai-services, bedrock, sagemaker, rekognition, comprehend, sagemaker-canvas)
- [ ] solutions-architect-professional

## Stub files remaining (to delete)

- [ ] blogs.md
- [ ] concepts.md
- [ ] guides.md
- [ ] concepts/api-gateway/README.md
- [ ] concepts/ebs/README.md
- [ ] concepts/iam/README.md
- [ ] concepts/messaging-streaming-services/README.md
- [ ] concepts/migration/README.md
- [ ] concepts/organizations/README.md
- [ ] concepts/systems-manager/README.md
- [ ] guides/ec2/README.md
- [ ] guides/rds/README.md
- [ ] concepts/iam-1.md
- [ ] concepts/s3.md
- [ ] concepts/service-discovery.md
- [ ] concepts/vpc-lattice.md
- [ ] concepts/ebs/amazon-data-lifecycle-manager.md
- [ ] concepts/messaging-streaming-services/kinesis.md
- [ ] concepts/migration/migration-evaluator.md
- [ ] guides/lambda.md
- [ ] guides/chatops.md
- [ ] guides/cost-saving.md
- [ ] guides/ec2/spot-pool.md
- [ ] guides/ecs-to-eks.md
- [ ] guides/rds/ssl-connectivity.md

## Completed

- [x] **cost-management** — 14 files created (README + 13 deep-dives)
- [x] solutions-architect-professional (all domain files real, keep as-is)
- [x] concepts/cost-management.md (288 lines, exam-oriented, solid)
- [x] concepts/systems-manager/patch-manager.md (321 lines, very detailed)
- [x] concepts/iam/external-id-and-confused-deputy-problem.md (71 lines)
- [x] concepts/iam/various-types-of-roles.md (71 lines)
- [x] concepts/api-gateway/usage-plan.md (71 lines)
- [x] concepts/organizations/delegated-admin.md (58 lines)
- [x] concepts/magic-ips-169.254.md (43 lines)
- [x] concepts/app-mesh-vs-vpc-lattice.md (39 lines)
- [x] concepts/ecs.md (17 lines)

## cost-management/ notes written

- [x] README.md (hub)
- [x] pricing-models.md — On-Demand, RI, SP, Spot, free tier, data transfer
- [x] savings-plans.md — Compute SP vs EC2 Instance SP, commitment, flexibility
- [x] reserved-instances.md — Standard/Convertible, regional/zonal, size flexibility
- [x] ri-management.md — coverage, utilization, marketplace, expiration
- [x] cost-explorer.md — views, RI/SP reports, forecasting, limitations
- [x] cost-usage-report.md — (placeholder for CUR deep-dive)
- [x] cost-budgets.md — types, alerts, ChatOps, budget actions
- [x] cost-allocation-tags.md — user-defined, AWS-generated, SCP enforcement
- [x] cost-anomaly-detection.md — ML detection, alert subscriptions, investigation
- [x] organizations-cost-strategy.md — consolidated billing, volume discounts, SCPs
- [x] ec2-cost-optimization.md — right-sizing, Spot, ASG, Graviton, zombie resources
- [x] s3-cost-optimization.md — storage classes, lifecycle, Intelligent-Tiering, replication
- [x] ebs-cost-optimization.md — gp3 vs gp2, unattached volumes, DLM, snapshots
- [x] dynamodb-cost-optimization.md — On-Demand vs Provisioned, Auto Scaling, DAX
- [x] lambda-cost-optimization.md — memory/duration, VPC ENI costs, provisioned concurrency
- [x] network-cost-optimization.md — AZ transfer, NAT Gateway, VPC Endpoints, CloudFront
- [x] cost-automation.md — Lambda cleanup, Instance Scheduler, automated remediation

## analytics/ notes written

- [x] README.md (service map, data flow patterns, Lambda/Kappa architecture)
- [x] kinesis/README.md (services at a glance, Streams vs Firehose vs Analytics)
- [x] kinesis/data-streams.md (shards, KPL/KCL, enhanced fan-out, capacity planning)
- [x] kinesis/data-firehose.md (buffering, destinations, transformation, Lambda)
- [x] kinesis/data-analytics.md (SQL windows, reference data, stream joins, Flink)
- [x] athena/README.md (schema-on-read, partitions, columnar formats, workgroups, performance)
- [x] redshift/README.md (RA3 nodes, Spectrum, DISTKEY, SORTKEY, WLM, data sharing)
- [x] glue/README.md (crawlers, Glue Data Catalog, Spark jobs, job bookmarks, ILM)
- [x] opensearch/README.md (index architecture, ILM, UltraWarm/Cold tiers, dashboards)
- [x] emr/README.md (cluster architecture, instance fleets, Spark, auto-scaling, serverless)
- [x] lake-formation/README.md (LF-tags, column/row security, cross-account sharing, blueprints)

## migration/ notes written

- [x] README.md (service map, 6 Rs, Migration Hub, full lifecycle overview)
- [x] dms/README.md (full load, CDC, heterogeneous, SCT, endpoint config, monitoring)
- [x] datasync/README.md (NFS/SMB/S3/EFS/FSx, agent deployment, task scheduling, bandwidth throttling)
- [x] application-migration-service/README.md (MGN lift-and-shift, agent install, waves, cutover)
- [x] server-migration-service/README.md (SMS deprecated, SMS vs MGN comparison, migration path)
- [x] migration-evaluator/README.md (TCO reports, right-sizing, assessment creation, collector deployment)
- [x] application-discovery-service/README.md (agentless/agent-based discovery, dependency mapping, ADS)