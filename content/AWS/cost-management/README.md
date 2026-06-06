---
title: AWS Cost Management
description: AWS cost management — pricing models, Cost Explorer, budgets, tags, billing, cost optimization strategies across compute, storage, database, networking
tags:
  - aws
  - cost-management
---

# AWS Cost Management

Cost on AWS is a first-class architectural concern. Every service has a pricing model, and understanding how usage translates to spend — across on-demand, reserved, and savings plan models — is fundamental to operating at scale.

This section covers the full cost management stack: pricing models, visibility tools, allocation strategies, and optimization techniques for every major service.

## Pricing Fundamentals

**[[pricing-models|Pricing Models]]** — On-Demand, Reserved Instances, Savings Plans, Spot Instances. The three ways AWS charges for compute, storage, and data transfer. Understanding when each applies and how they interact.

**[[savings-plans|Savings Plans]]** — Compute Savings Plans vs EC2 Instance Savings Plans vs SageMaker Savings Plans. How SP commitment works, instance size flexibility, and when SP beats RI.

**[[reserved-instances|Reserved Instances]]** — Standard vs Convertible RIs. Regional vs zonal. Payment options (All/Partial/No Upfront). Instance size flexibility within families. Coverage vs utilization reporting.

## Visibility and Reporting

**[[cost-explorer|Cost Explorer]]** — Built-in AWS cost analysis. Visualizing spend by service, account, tag. RI and Savings Plan coverage reports. Forecasting. Limitations of the forecasting model.

**[[cost-usage-report|Cost and Usage Report (CUR)]]** — The most detailed billing data. Hourly vs daily granularity. S3 Athena + Glue analysis. Multi-account aggregation. Setting up chargeback and showback models.

**[[cost-budgets|Cost Budgets]]** — Creating cost, usage, and RI/SP budgets. Alert thresholds and notification destinations (SNS, ChatOps). Budget actions for automated responses. Reserving RI/SP capacity.

## Cost Allocation

**[[cost-allocation-tags|Cost Allocation Tags]]** — User-defined tags vs AWS-generated tags. Tag activation requirements. Tag inheritance pitfalls (accounts, resources). Enforcement via SCPs and AWS Config rules.

**[[cost-anomaly-detection|Cost Anomaly Detection]]** — Machine learning-based detection of unexpected cost spikes. Alert subscriptions. Root cause investigation workflow.

**[[instance-scheduler|Instance Scheduler]]** — AWS Solutions construct for stopping/starting EC2 and RDS instances on a schedule. CloudWatch Events + Lambda implementation. Cost impact of running 24/7 vs scheduled.

## Compute Cost Optimization

**[[ec2-cost-optimization|EC2 Cost Optimization]]** — Right-sizing via Compute Optimizer and CloudWatch metrics. Spot + On-Demand + RI mixed policies. Zombie resource detection. Graviton ARM cost trade-offs. Auto Scaling lifecycle.

## Storage Cost Optimization

**[[s3-cost-optimization|S3 Cost Optimization]]** — Storage class selection (Standard, IA, One Zone-IA, Glacier, Intelligent-Tiering, Deep Archive). Lifecycle policy design. Data retrieval costs. Cross-region replication costs. S3 Analytics for transition planning.

**[[ebs-cost-optimization|EBS Cost Optimization]]** — gp2 vs gp3 trade-offs. io1/io2 vs gp3 sizing. Unattached volume detection. Snapshot lifecycle management. Amazon Data Lifecycle Manager.

**[[efs-cost-optimization|EFS Cost Optimization]]** — EFS Standard vs EFS One Zone. Throughput vs bursting mode. Lifecycle management for IA access tiers. EFS Access Points for POSIX permissions.

## Database Cost Optimization

**[[rds-cost-optimization|RDS Cost Optimization]]** — Instance sizing and right-sizing. Multi-AZ cost impact. Read replicas vs scaling up. Storage auto-scaling costs. Reserved instance coverage. Aurora Serverless v1 vs v2.

**[[dynamodb-cost-optimization|DynamoDB Cost Optimization]]** — On-Demand vs Provisioned capacity. Auto scaling configuration. Reserved capacity. DAX cost justification. GSI vs LSI cost implications.

## Network Cost Optimization

**[[network-cost-optimization|Network Cost Optimization]]** — AZ-to-AZ data transfer costs. Inter-region egress. Internet egress pricing. NAT Gateway per-hour + per-GB costs. VPC Endpoints for private S3/DynamoDB access. PrivateLink vs Direct Connect trade-offs. ALB vs NLB LCU pricing model. CloudFront caching for origin cost reduction.

## Serverless Cost Optimization

**[[lambda-cost-optimization|Lambda Cost Optimization]]** — Memory vs duration relationship. Provisioned concurrency cost. Cold start cost implications. VPC Lambda ENI attachment costs. API Gateway REST vs HTTP API pricing differences.

## Automation

**[[cost-automation|Cost Automation]]** — Lambda functions for automated cleanup: stopping idle EC2, deleting unattached EBS volumes, expiring old snapshots. CloudWatch Rules + EventBridge schedules. SSM Automation documents for cost remediation.

## Reserved Instance Management

**[[ri-management|Reserved Instance Management]]** — Buying RIs vs Savings Plans. Coverage reports (which instances are covered by RI/SP). Utilization reports (are you fully utilizing what you bought). Instance size flexibility. RI marketplace for selling unused.

## Multi-Account Cost Strategy

**[[organizations-cost-strategy|Organizations Cost Strategy]]** — Consolidated billing advantages. Volume discounts. RI/SP sharing across accounts. SCPs for cost governance. Multi-payer billing for enterprise. Cost allocation by OU.

## References

- **Homepage:** https://aws.amazon.com/cost-management/
- **Documentation:** https://docs.aws.amazon.com/cost-management/
- **Pricing:** https://aws.amazon.com/cost-management/pricing/

## Pricing Examples

**Scenario 1:** A mid-size company running 50 EC2 instances (mixed m5.large and c5.xlarge), 20TB S3, RDS Multi-AZ (db.r6g.large), and Elasticache (cache.r6g.large). Monthly bill: ~$4,200/month. Breakdown: EC2 instances (50 × m5.large = $1,380 + 10 × c5.xlarge = $700) = $2,080, RDS Multi-AZ = $450, ElastiCache = $280, S3 = $400, NAT Gateway + Data Transfer = $400, EBS = $300, ALB = $200.

**Scenario 2:** A startup with 8 EC2 instances (t3.medium), 2TB S3, DynamoDB (10 RCU/100 WCU), Lambda (500K req/day), no RDS. Monthly bill: ~$380/month. Breakdown: EC2 (8 × t3.medium On-Demand = $120), S3 (2TB = $46), DynamoDB (On-Demand = $40), Lambda (500K × 30 = 15M req × $0.20/million = $3), Data Transfer = $50, CloudWatch = $20, ALB = $20.

## Nuggets & Gotchas

- **Free tier expires after 12 months:** The EC2 t2.micro free tier ends after 12 months — set a calendar reminder to right-size or switch to a smaller instance before you're charged.
- **S3 data transfer IN is free, OUT is not:** Ingress to S3 is free; every GB that leaves S3 (to internet, to other AZs, cross-region) is charged. Design for this.
- **NAT Gateway has two cost components:** You pay per hour ($0.045/hr in us-east-1) PLUS per GB processed ($0.045/GB). A busy Lambda workload in a VPC can generate surprising NAT Gateway bills.
- **EBS volumes charge even when stopped:** An EC2 instance that is stopped still has its EBS volumes attached and accruing storage charges. Detach volumes or delete the instance to stop the charges.
- **Cost Explorer has a data delay:** Cost Explorer shows data with a 24-48 hour delay. Real-time spend monitoring requires CloudWatch billing alerts or third-party tools.