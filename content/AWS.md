---
title: AWS
tags: [aws, cloud, amazon-web-services]
date: 2025-05-24
description: Amazon Web Services - compute, storage, databases, networking, security, analytics, machine learning, serverless, and application integration
---

# AWS ☁️

Amazon Web Services — built from scratch with deep notes on every major service. Each section has References (homepage/docs/pricing), 2 pricing scenarios, and 5+ nuggets/gotchas.

## Compute

| Service | Description |
|---------|-------------|
| [[AWS/compute/ec2|EC2]] | Virtual machines — instance types, AMIs, security groups, auto scaling |
| [[AWS/compute/lambda|Lambda]] | Serverless functions — runtimes, layers, versions, VPC, cold starts |
| [[AWS/compute/ecs|ECS]] | Docker containers on EC2 — tasks, services, Fargate launch |
| [[AWS/compute/eks|EKS]] | Managed Kubernetes — node groups, IRSA, add-ons, upgrades |
| [[AWS/compute/batch|Batch]] | Batch computing — compute environments, job definitions, scheduling |
| [[AWS/compute/lightsail|LightSail]] | Simple VPS — pre-configured instances, DNS, storage |

## Storage

| Service | Description |
|---------|-------------|
| [[AWS/storage/s3|S3]] | Object storage — tiers, lifecycle, versioning, policies, presigned URLs |
| [[AWS/storage/ebs|EBS]] | Block storage — gp2/gp3/io2, snapshots, encryption, volumes |
| [[AWS/storage/efs|EFS]] | Network file system — throughput modes, access patterns, Mount Targets |
| [[AWS/storage/fsx|FSx]] | Managed file systems — FSx for Windows, Lustre, OpenZFS, NetApp |
| [[AWS/storage/glacier|Glacier]] | Archive storage — vaults, retrieval options, data retrieval policies |
| [[AWS/storage/storage-gateway|Storage Gateway]] | Hybrid storage — File Gateway, Volume Gateway, Tape Gateway |

## Databases

| Service | Description |
|---------|-------------|
| [[AWS/databases/rds|RDS]] | Managed relational — Multi-AZ, read replicas, parameter groups, backups |
| [[AWS/databases/aurora|Aurora]] | MySQL/PG compatible — 6-way replication, serverless v2, global database |
| [[AWS/databases/dynamodb|DynamoDB]] | NoSQL key-value — partitions, GSI/LSI, on-demand, DAX, streams |
| [[AWS/databases/elasticache|ElastiCache]] | In-memory cache — Redis vs Memcached, clusters, strategies |
| [[AWS/databases/redshift|Redshift]] | Data warehouse — RA3, distribution styles, spectrum, data sharing |
| [[AWS/databases/documentdb|DocumentDB]] | MongoDB compatible — aggregation, change streams, transactions |
| [[AWS/databases/neptune|Neptune]] | Graph database — Gremlin, SPARQL, fraud detection |
| [[AWS/databases/qldb|QLDB]] | Immutable ledger — cryptographically verifiable, PartiQL |
| [[AWS/databases/timestream|Timestream]] | Time-series DB — hot/warm/cold tiers, scheduled queries |

## Networking

| Service | Description |
|---------|-------------|
| [[AWS/networking/vpc|VPC]] | Virtual network — CIDR, subnets, routing, internet/NAT gateways |
| [[AWS/networking/vpc/security-groups|Security Groups]] | Stateful firewall — rules, referencing, default deny |
| [[AWS/networking/vpc/network-acls|Network ACLs]] | Stateless subnet firewall — rules evaluated in order |
| [[AWS/networking/vpc/vpc-peering|VPC Peering]] | Direct VPC-to-VPC — no transitive routing |
| [[AWS/networking/vpc/transit-gateway|Transit Gateway]] | Hub-and-spoke — regional or global, route tables |
| [[AWS/networking/load-balancing|Load Balancing]] | ALB, NLB, CLB — target groups, health checks, listeners |
| [[AWS/networking/dns|DNS]] | Route 53 — hosted zones, records, routing policies, DNSSEC |
| [[AWS/networking/cdn|CDN]] | CloudFront — distributions, origins, behaviors, functions |
| [[AWS/networking/hybrid|Hybrid]] | Direct Connect, VPN, PrivateLink, Outposts |

## Security & Identity

| Service | Description |
|---------|-------------|
| [[AWS/security/iam|IAM]] | Identity — users, groups, roles, policies, SCPs, permission boundaries, SSO |
| [[AWS/security/kms|KMS]] | Encryption — CMK, envelope encryption, grants, rotation |
| [[AWS/security/cloudtrail|CloudTrail]] | API audit — trails, event history, log validation |
| [[AWS/security/config|Config]] | Resource inventory — change tracking, rules, conformance packs |
| [[AWS/security/guardduty|GuardDuty]] | Threat detection — findings, CloudTrail/DNS/VPC analysis |
| [[AWS/security/security-hub|Security Hub]] | Centralized findings — ASFF, compliance standards, cross-account |
| [[AWS/security/inspector|Inspector]] | Vulnerability scanning — EC2, ECR, Lambda, CVE, CIS |
| [[AWS/security/macie|Macie]] | S3 data classification — PII detection, sensitive data findings |
| [[AWS/security/secrets-manager|Secrets Manager]] | Secret rotation — Lambda functions, multi-region, resource policy |
| [[AWS/security/certificate-manager|ACM]] | TLS certificates — public/private, DNS validation, CloudFront/ALB |
| [[AWS/security/detective|Detective]] | Graph-based investigation — behavior profiles, GuardDuty integration |

## Management & Governance

| Service | Description |
|---------|-------------|
| [[AWS/management-governance/organizations|Organizations]] | Multi-account — OUs, SCPs, consolidated billing |
| [[AWS/management-governance/control-tower|Control Tower]] | Landing zone — guardrails, account factory, governance |
| [[AWS/management-governance/cloudformation|CloudFormation]] | IaC — templates, stacks, change sets, drift detection |
| [[AWS/management-governance/cdk|CDK]] | Code-as-IaC — TypeScript/Python, constructs, stacks |
| [[AWS/management-governance/cli|CLI]] | AWS CLI — profiles, named queries, SSM session, dry-run |
| [[AWS/management-governance/systems-manager|Systems Manager]] | Operations — Parameter Store, Session Manager, Run Command, Patch Manager |

## Monitoring

| Service | Description |
|---------|-------------|
| [[AWS/monitoring/cloudwatch-metrics|CloudWatch Metrics]] | Custom metrics — stats, dimensions, resolution, metric math |
| [[AWS/monitoring/cloudwatch-logs|CloudWatch Logs]] | Log ingestion — agents, filters, Insights queries, Live Tail |
| [[AWS/monitoring/cloudwatch-alarms|CloudWatch Alarms]] | Alerting — thresholds, periods, actions, composite |
| [[AWS/monitoring/cloudwatch-dashboards|CloudWatch Dashboards]] | Visualization — widgets, metrics, logs, cross-region |
| [[AWS/monitoring/cloudwatch-events|EventBridge]] | Event bus — default/custom/partner buses, rules, schedules |
| [[AWS/monitoring/cloudwatch-insights|CloudWatch Insights]] | Log analytics — query language, visualizations, dashboards |

## Application Integration

| Service | Description |
|---------|-------------|
| [[AWS/application-integration/sqs|SQS]] | Message queues — standard/FIFO, DLQ, visibility timeout, Lambda |
| [[AWS/application-integration/sns|SNS]] | Pub/sub — topics, subscriptions, fan-out, filtering, SMS |
| [[AWS/application-integration/eventbridge|EventBridge]] | Event bus — rules, schema registry, replay, cross-account |
| [[AWS/application-integration/step-functions|Step Functions]] | Workflows — standard/express, state types, error handling |
| [[AWS/application-integration/amazon-mq|Amazon MQ]] | Managed brokers — ActiveMQ, RabbitMQ, clustering, TLS |
| [[AWS/application-integration/appsync|AppSync]] | GraphQL API — DynamoDB resolvers, VTL, subscriptions |

## Analytics

| Service | Description |
|---------|-------------|
| [[AWS/analytics/kinesis|Kinesis Data Streams]] | Streaming — shards, KPL/KCL, enhanced fan-out |
| [[AWS/analytics/kinesis/data-firehose|Kinesis Data Firehose]] | Streaming delivery — destinations, buffering, transforms |
| [[AWS/analytics/kinesis/data-analytics|Kinesis Data Analytics]] | Streaming SQL — windows, reference data, Flink |
| [[AWS/analytics/athena|Athena]] | Serverless SQL — schema-on-read, partitions, compressed formats |
| [[AWS/analytics/redshift|Redshift]] | Data warehouse — RA3, distribution, spectrum, data sharing |
| [[AWS/analytics/glue|Glue]] | ETL — crawlers, Data Catalog, Spark jobs, job bookmarks |
| [[AWS/analytics/opensearch|OpenSearch]] | Search/analytics — index architecture, UltraWarm, dashboards |
| [[AWS/analytics/emr|EMR]] | Big data — Spark, Hadoop, serverless, instance fleets |
| [[AWS/analytics/lake-formation|Lake Formation]] | Data lake — LF-tags, column/row security, cross-account |

## Machine Learning

| Service | Description |
|---------|-------------|
| [[AWS/machine-learning/ai-services|AI Services]] | Pre-trained APIs — Rekognition, Comprehend, Polly, Translate, Textract |
| [[AWS/machine-learning/bedrock|Bedrock]] | Foundation models — Claude, Llama, RAG, agents, fine-tuning |
| [[AWS/machine-learning/sagemaker|SageMaker]] | ML platform — Jupyter, training, inference, pipelines, Feature Store |
| [[AWS/machine-learning/rekognition|Rekognition]] | Vision AI — object detection, face comparison, video analysis |
| [[AWS/machine-learning/comprehend|Comprehend]] | NLP — sentiment, entities, PII, topic modeling, Comprehend Medical |
| [[AWS/machine-learning/sagemaker-canvas|SageMaker Canvas]] | No-code ML — classification, regression, time-series forecasting |

## Serverless

| Service | Description |
|---------|-------------|
| [[AWS/serverless/lambda|Lambda]] | Functions — runtimes, layers, versions, VPC, cold starts |
| [[AWS/serverless/api-gateway|API Gateway]] | APIs — REST, HTTP, WebSocket, authorizers, rate limiting |
| [[AWS/serverless/app-runner|App Runner]] | Container web apps — from image or code, auto-scaling |

## Cost Management

| Service | Description |
|---------|-------------|
| [[AWS/cost-management/pricing-models|Pricing Models]] | On-Demand, Reserved, Savings Plans, Spot, free tier |
| [[AWS/cost-management/savings-plans|Savings Plans]] | Compute SP vs EC2 Instance SP, commitment, flexibility |
| [[AWS/cost-management/reserved-instances|Reserved Instances]] | Standard/Convertible, regional/zonal, size flexibility |
| [[AWS/cost-management/ec2-cost-optimization|EC2 Optimization]] | Right-sizing, Spot, ASG, Graviton, zombie resources |
| [[AWS/cost-management/s3-cost-optimization|S3 Optimization]] | Storage classes, Intelligent-Tiering, lifecycle, replication |
| [[AWS/cost-management/network-cost-optimization|Network Optimization]] | AZ transfer, NAT Gateway, VPC Endpoints, CloudFront |

## Migration

| Service | Description |
|---------|-------------|
| [[AWS/migration/dms|DMS]] | Database migration — full load, CDC, heterogeneous, SCT |
| [[AWS/migration/datasync|DataSync]] | Data transfer — NFS, SMB, S3, EFS, FSx, agent, scheduling |
| [[AWS/migration/application-migration-service|MGN]] | Lift-and-shift — agentless, waves, cutover, continuous replication |
| [[AWS/migration/migration-evaluator|Migration Evaluator]] | TCO analysis — right-sizing, assessment, collector |

## AWS Certification

- [[AWS/solutions-architect-professional|Solutions Architect Professional]]

## Related

- [[Kubernetes]] — EKS runs on AWS; see also [[AWS/networking/vpc|VPC networking]] for cluster networking
- [[AI/aws|Bedrock and SageMaker]] for ML workloads
- [[Linux]] — EC2 Linux instances, SSM Session Manager
