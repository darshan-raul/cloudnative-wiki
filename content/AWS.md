---
title: AWS
tags: [aws, cloud, amazon-web-services]
date: 2025-05-24
description: Amazon Web Services - compute, storage, databases, networking, security, analytics, machine learning, serverless, and application integration
---

# AWS ☁️

Amazon Web Services — built from scratch with deep notes on every major service. Each section has References (homepage/docs/pricing), 2 pricing scenarios, and 5+ nuggets/gotchas.

## Compute

| Service                                     | Description                                                            |
| ------------------------------------------- | ---------------------------------------------------------------------- |
| [[AWS/compute/ec2/README\|EC2]]             | Virtual machines — instance types, AMIs, security groups, auto scaling |
| [[AWS/compute/lambda/README\|Lambda]]       | Serverless functions — runtimes, layers, versions, VPC, cold starts    |
| [[AWS/compute/ecs/README\|ECS]]             | Docker containers on EC2 — tasks, services, Fargate launch             |
| [[AWS/compute/eks/README\|EKS]]             | Managed Kubernetes — node groups, IRSA, add-ons, upgrades              |
| [[AWS/compute/batch/README\|Batch]]         | Batch computing — compute environments, job definitions, scheduling    |
| [[AWS/compute/lightsail/README\|LightSail]] | Simple VPS — pre-configured instances, DNS, storage                    |

## Storage

| Service                                                 | Description                                                             |
| ------------------------------------------------------- | ----------------------------------------------------------------------- |
| [[AWS/storage/s3/README\|S3]]                           | Object storage — tiers, lifecycle, versioning, policies, presigned URLs |
| [[AWS/storage/ebs/README\|EBS]]                         | Block storage — gp2/gp3/io2, snapshots, encryption, volumes             |
| [[AWS/storage/efs/README\|EFS]]                         | Network file system — throughput modes, access patterns, Mount Targets  |
| [[AWS/storage/fsx/README\|FSx]]                         | Managed file systems — FSx for Windows, Lustre, OpenZFS, NetApp         |
| [[AWS/storage/glacier/README\|Glacier]]                 | Archive storage — vaults, retrieval options, data retrieval policies    |
| [[AWS/storage/storage-gateway/README\|Storage Gateway]] | Hybrid storage — File Gateway, Volume Gateway, Tape Gateway             |

## Databases

| Service                                           | Description                                                             |
| ------------------------------------------------- | ----------------------------------------------------------------------- |
| [[AWS/databases/rds/README\|RDS]]                 | Managed relational — Multi-AZ, read replicas, parameter groups, backups |
| [[AWS/databases/aurora/README\|Aurora]]           | MySQL/PG compatible — 6-way replication, serverless v2, global database |
| [[AWS/databases/dynamodb/README\|DynamoDB]]       | NoSQL key-value — partitions, GSI/LSI, on-demand, DAX, streams          |
| [[AWS/databases/elasticache/README\|ElastiCache]] | In-memory cache — Redis vs Memcached, clusters, strategies              |
| [[AWS/databases/redshift/README\|Redshift]]       | Data warehouse — RA3, distribution styles, spectrum, data sharing       |
| [[AWS/databases/documentdb/README\|DocumentDB]]   | MongoDB compatible — aggregation, change streams, transactions          |
| [[AWS/databases/neptune/README\|Neptune]]         | Graph database — Gremlin, SPARQL, fraud detection                       |
| [[AWS/databases/qldb/README\|QLDB]]               | Immutable ledger — cryptographically verifiable, PartiQL                |
| [[AWS/databases/timestream/README\|Timestream]]   | Time-series DB — hot/warm/cold tiers, scheduled queries                 |

## Networking

| Service                                                  | Description                                                     |
| -------------------------------------------------------- | --------------------------------------------------------------- |
| [[AWS/networking/vpc/README\|VPC]]                       | Virtual network — CIDR, subnets, routing, internet/NAT gateways |
| [[AWS/networking/vpc/security-groups\|Security Groups]]  | Stateful firewall — rules, referencing, default deny            |
| [[AWS/networking/vpc/network-acls\|Network ACLs]]        | Stateless subnet firewall — rules evaluated in order            |
| [[AWS/networking/vpc/vpc-peering\|VPC Peering]]          | Direct VPC-to-VPC — no transitive routing                       |
| [[AWS/networking/vpc/transit-gateway\|Transit Gateway]]  | Hub-and-spoke — regional or global, route tables                |
| [[AWS/networking/load-balancing/README\|Load Balancing]] | ALB, NLB, CLB — target groups, health checks, listeners         |
| [[AWS/networking/dns/README\|DNS]]                       | Route 53 — hosted zones, records, routing policies, DNSSEC      |
| [[AWS/networking/cdn/README\|CDN]]                       | CloudFront — distributions, origins, behaviors, functions       |
| [[AWS/networking/hybrid/README\|Hybrid]]                 | Direct Connect, VPN, PrivateLink, Outposts                      |

## Security & Identity

| Service                                                  | Description                                                                 |
| -------------------------------------------------------- | --------------------------------------------------------------------------- |
| [[AWS/security/iam/README\|IAM]]                         | Identity — users, groups, roles, policies, SCPs, permission boundaries, SSO |
| [[AWS/security/kms/README\|KMS]]                         | Encryption — CMK, envelope encryption, grants, rotation                     |
| [[AWS/security/cloudtrail/README\|CloudTrail]]           | API audit — trails, event history, log validation                           |
| [[AWS/security/config/README\|Config]]                   | Resource inventory — change tracking, rules, conformance packs              |
| [[AWS/security/guardduty/README\|GuardDuty]]             | Threat detection — findings, CloudTrail/DNS/VPC analysis                    |
| [[AWS/security/security-hub/README\|Security Hub]]       | Centralized findings — ASFF, compliance standards, cross-account            |
| [[AWS/security/inspector/README\|Inspector]]             | Vulnerability scanning — EC2, ECR, Lambda, CVE, CIS                         |
| [[AWS/security/macie/README\|Macie]]                     | S3 data classification — PII detection, sensitive data findings             |
| [[AWS/security/secrets-manager/README\|Secrets Manager]] | Secret rotation — Lambda functions, multi-region, resource policy           |
| [[AWS/security/certificate-manager/README\|ACM]]         | TLS certificates — public/private, DNS validation, CloudFront/ALB           |
| [[AWS/security/detective/README\|Detective]]             | Graph-based investigation — behavior profiles, GuardDuty integration        |

## Management & Governance

| Service                                                               | Description                                                               |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| [[AWS/management-governance/organizations/README\|Organizations]]     | Multi-account — OUs, SCPs, consolidated billing                           |
| [[AWS/management-governance/control-tower/README\|Control Tower]]     | Landing zone — guardrails, account factory, governance                    |
| [[AWS/management-governance/cloudformation/README\|CloudFormation]]   | IaC — templates, stacks, change sets, drift detection                     |
| [[AWS/management-governance/cdk/README\|CDK]]                         | Code-as-IaC — TypeScript/Python, constructs, stacks                       |
| [[AWS/management-governance/cli/README\|CLI]]                         | AWS CLI — profiles, named queries, SSM session, dry-run                   |
| [[AWS/management-governance/systems-manager/README\|Systems Manager]] | Operations — Parameter Store, Session Manager, Run Command, Patch Manager |

## Monitoring

| Service                                                                | Description                                                  |
| ---------------------------------------------------------------------- | ------------------------------------------------------------ |
| [[AWS/monitoring/cloudwatch-metrics/README\|CloudWatch Metrics]]       | Custom metrics — stats, dimensions, resolution, metric math  |
| [[AWS/monitoring/cloudwatch-logs/README\|CloudWatch Logs]]             | Log ingestion — agents, filters, Insights queries, Live Tail |
| [[AWS/monitoring/cloudwatch-alarms/README\|CloudWatch Alarms]]         | Alerting — thresholds, periods, actions, composite           |
| [[AWS/monitoring/cloudwatch-dashboards/README\|CloudWatch Dashboards]] | Visualization — widgets, metrics, logs, cross-region         |
| [[AWS/monitoring/cloudwatch-events/README\|EventBridge]]               | Event bus — default/custom/partner buses, rules, schedules   |
| [[AWS/monitoring/cloudwatch-insights/README\|CloudWatch Insights]]     | Log analytics — query language, visualizations, dashboards   |

## Application Integration

| Service                                                               | Description                                                     |
| --------------------------------------------------------------------- | --------------------------------------------------------------- |
| [[AWS/application-integration/sqs/README\|SQS]]                       | Message queues — standard/FIFO, DLQ, visibility timeout, Lambda |
| [[AWS/application-integration/sns/README\|SNS]]                       | Pub/sub — topics, subscriptions, fan-out, filtering, SMS        |
| [[AWS/application-integration/eventbridge/README\|EventBridge]]       | Event bus — rules, schema registry, replay, cross-account       |
| [[AWS/application-integration/step-functions/README\|Step Functions]] | Workflows — standard/express, state types, error handling       |
| [[AWS/application-integration/amazon-mq/README\|Amazon MQ]]           | Managed brokers — ActiveMQ, RabbitMQ, clustering, TLS           |
| [[AWS/application-integration/appsync/README\|AppSync]]               | GraphQL API — DynamoDB resolvers, VTL, subscriptions            |

## Analytics

| Service                                                          | Description                                                     |
| ---------------------------------------------------------------- | --------------------------------------------------------------- |
| [[AWS/analytics/kinesis/README\|Kinesis Data Streams]]           | Streaming — shards, KPL/KCL, enhanced fan-out                   |
| [[AWS/analytics/kinesis/data-firehose\|Kinesis Data Firehose]]   | Streaming delivery — destinations, buffering, transforms        |
| [[AWS/analytics/kinesis/data-analytics\|Kinesis Data Analytics]] | Streaming SQL — windows, reference data, Flink                  |
| [[AWS/analytics/athena/README\|Athena]]                          | Serverless SQL — schema-on-read, partitions, compressed formats |
| [[AWS/analytics/redshift/README\|Redshift]]                      | Data warehouse — RA3, distribution, spectrum, data sharing      |
| [[AWS/analytics/glue/README\|Glue]]                              | ETL — crawlers, Data Catalog, Spark jobs, job bookmarks         |
| [[AWS/analytics/opensearch/README\|OpenSearch]]                  | Search/analytics — index architecture, UltraWarm, dashboards    |
| [[AWS/analytics/emr/README\|EMR]]                                | Big data — Spark, Hadoop, serverless, instance fleets           |
| [[AWS/analytics/lake-formation/README\|Lake Formation]]          | Data lake — LF-tags, column/row security, cross-account         |

## Machine Learning

| Service                                                            | Description                                                            |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| [[AWS/machine-learning/ai-services/README\|AI Services]]           | Pre-trained APIs — Rekognition, Comprehend, Polly, Translate, Textract |
| [[AWS/machine-learning/bedrock/README\|Bedrock]]                   | Foundation models — Claude, Llama, RAG, agents, fine-tuning            |
| [[AWS/machine-learning/sagemaker/README\|SageMaker]]               | ML platform — Jupyter, training, inference, pipelines, Feature Store   |
| [[AWS/machine-learning/rekognition/README\|Rekognition]]           | Vision AI — object detection, face comparison, video analysis          |
| [[AWS/machine-learning/comprehend/README\|Comprehend]]             | NLP — sentiment, entities, PII, topic modeling, Comprehend Medical     |
| [[AWS/machine-learning/sagemaker-canvas/README\|SageMaker Canvas]] | No-code ML — classification, regression, time-series forecasting       |

## Serverless

| Service                                            | Description                                              |
| -------------------------------------------------- | -------------------------------------------------------- |
| [[AWS/serverless/lambda/README\|Lambda]]           | Functions — runtimes, layers, versions, VPC, cold starts |
| [[AWS/serverless/api-gateway/README\|API Gateway]] | APIs — REST, HTTP, WebSocket, authorizers, rate limiting |
| [[AWS/serverless/app-runner/README\|App Runner]]   | Container web apps — from image or code, auto-scaling    |

## Cost Management

| Service                                                                 | Description                                                  |
| ----------------------------------------------------------------------- | ------------------------------------------------------------ |
| [[AWS/cost-management/pricing-models\|Pricing Models]]                  | On-Demand, Reserved, Savings Plans, Spot, free tier          |
| [[AWS/cost-management/savings-plans\|Savings Plans]]                    | Compute SP vs EC2 Instance SP, commitment, flexibility       |
| [[AWS/cost-management/reserved-instances\|Reserved Instances]]          | Standard/Convertible, regional/zonal, size flexibility       |
| [[AWS/cost-management/ec2-cost-optimization\|EC2 Optimization]]         | Right-sizing, Spot, ASG, Graviton, zombie resources          |
| [[AWS/cost-management/s3-cost-optimization\|S3 Optimization]]           | Storage classes, Intelligent-Tiering, lifecycle, replication |
| [[AWS/cost-management/network-cost-optimization\|Network Optimization]] | AZ transfer, NAT Gateway, VPC Endpoints, CloudFront          |

## Migration

| Service                                                           | Description                                                        |
| ----------------------------------------------------------------- | ------------------------------------------------------------------ |
| [[AWS/migration/dms/README\|DMS]]                                 | Database migration — full load, CDC, heterogeneous, SCT            |
| [[AWS/migration/datasync/README\|DataSync]]                       | Data transfer — NFS, SMB, S3, EFS, FSx, agent, scheduling          |
| [[AWS/migration/application-migration-service/README\|MGN]]       | Lift-and-shift — agentless, waves, cutover, continuous replication |
| [[AWS/migration/migration-evaluator/README\|Migration Evaluator]] | TCO analysis — right-sizing, assessment, collector                 |

## AWS Certification

- [[AWS/solutions-architect-professional/index|Solutions Architect Professional]]

## Sections

- [[AWS/analytics/README|AWS Analytics]] — AWS analytics services — Kinesis for streaming data, Athena for SQL queries, Redshift for data warehousing, Glue for ETL,…
- [[AWS/compute/README|AWS Compute]] — AWS compute services — EC2 for virtual servers, Lambda for serverless functions, ECS/EKS for containers, Batch for batch jobs,…
- [[AWS/cost-management/README|AWS Cost Management]] — AWS cost management — pricing models, Cost Explorer, budgets, tags, billing, cost optimization strategies across compute,…
- [[AWS/databases/README|AWS Databases]] — AWS database services — RDS (relational), Aurora (MySQL/PostgreSQL compatible), DynamoDB (NoSQL), ElastiCache (in-memory),…
- [[AWS/machine-learning/README|AWS Machine Learning]] — AWS machine learning services — AI services (pre-trained APIs), SageMaker (build your own), Bedrock (LLMs), Rekognition (vision),…
- [[AWS/management-governance/README|AWS Management & Governance]] — AWS management and governance services — Organizations for multi-account management, Control Tower for landing zones,…
- [[AWS/migration/README|AWS Migration]] — AWS migration services — DMS for database migration, DataSync for file transfer, Application Migration Service (MGN) for…
- [[AWS/security/README|AWS Security]] — AWS security services — IAM for identity, KMS for encryption, CloudTrail for audit, GuardDuty for threat detection, Security Hub…
- [[AWS/serverless/README|AWS Serverless]] — AWS serverless services — Lambda (compute), API Gateway (HTTP/REST/WebSocket APIs), App Runner (containers), and Bedrock…
- [[AWS/storage/README|AWS Storage]] — AWS storage services — S3 for object storage, EBS for block storage, EFS for network file system, FSx for Windows/Lustre file…

## More in this section

- [[AWS/cloud-architect-areas|Cloud Architect Areas]] — As a cloud architect, dividing cloud infrastructure management and architecting into categories is essential for clarity,…
- [[AWS/concepts/cost-management|Cost Management]] — An exam-oriented breakdown of AWS cost control and cost management topics.
- [[AWS/concepts/magic-ips-169.254|Magic ips/ 169.254]] — The link-local 169.254.0.0/16 addresses AWS uses inside a VPC: instance metadata, the DNS resolver, time sync and ECS/EKS…

## Related

- [[Kubernetes]] — EKS runs on AWS; see also [[AWS/networking/vpc/README|VPC networking]] for cluster networking
- [[AI/aws/README|Bedrock and SageMaker]] for ML workloads
- [[Linux]] — EC2 Linux instances, SSM Session Manager
