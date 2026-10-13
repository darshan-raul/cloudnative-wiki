# AWS reference availability check

This is the preserved pre-remediation check (including old failures). The [current verification](aws-remediation-verification.md) records 620 retained AWS URLs returning HTTP 200 after remediation.

Checked 2026-10-12 against URLs outside fenced examples in the current core AWS notes. HEAD requests were retried with GET for 403/404/405. These are observed HTTP results, not proof of claim relevance. A 403 is **unverified**, not confirmed broken. Re-run with `node planning/aws-audit-reference-links.mjs`.

200: 230; 403: 6; 404: 30. Total unique AWS URLs: 266.

## URLs requiring attention

| URL                                                                        | HTTP | Affected notes                                                                                                                                                                                                                                                                                                                |
| -------------------------------------------------------------------------- | ---: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| https://aws.amazon.com/ai-services/pricing/                                |  404 | [AWS/machine-learning/ai-services/README.md](../content/AWS/machine-learning/ai-services/README.md)                                                                                                                                                                                                                           |
| https://aws.amazon.com/apigateway/pricing/                                 |  404 | [AWS/serverless/README.md](../content/AWS/serverless/README.md)                                                                                                                                                                                                                                                               |
| https://aws.amazon.com/cdk/pricing/                                        |  404 | [AWS/management-governance/cdk/README.md](../content/AWS/management-governance/cdk/README.md)                                                                                                                                                                                                                                 |
| https://aws.amazon.com/cost-management/                                    |  404 | [AWS/cost-management/README.md](../content/AWS/cost-management/README.md), [AWS/cost-management/cost-automation.md](../content/AWS/cost-management/cost-automation.md)                                                                                                                                                        |
| https://aws.amazon.com/cost-management/aws-cost-anomaly-detection/         |  404 | [AWS/cost-management/cost-anomaly-detection.md](../content/AWS/cost-management/cost-anomaly-detection.md)                                                                                                                                                                                                                     |
| https://aws.amazon.com/cost-management/aws-cost-anomaly-detection/pricing/ |  404 | [AWS/cost-management/cost-anomaly-detection.md](../content/AWS/cost-management/cost-anomaly-detection.md)                                                                                                                                                                                                                     |
| https://aws.amazon.com/cost-management/aws-cost-budgets/                   |  404 | [AWS/cost-management/cost-budgets.md](../content/AWS/cost-management/cost-budgets.md)                                                                                                                                                                                                                                         |
| https://aws.amazon.com/cost-management/aws-cost-budgets/pricing/           |  404 | [AWS/cost-management/cost-budgets.md](../content/AWS/cost-management/cost-budgets.md)                                                                                                                                                                                                                                         |
| https://aws.amazon.com/cost-management/aws-cost-explorer/                  |  404 | [AWS/cost-management/cost-explorer.md](../content/AWS/cost-management/cost-explorer.md)                                                                                                                                                                                                                                       |
| https://aws.amazon.com/cost-management/aws-cost-explorer/pricing/          |  404 | [AWS/cost-management/cost-explorer.md](../content/AWS/cost-management/cost-explorer.md)                                                                                                                                                                                                                                       |
| https://aws.amazon.com/cost-management/cost-allocation/                    |  404 | [AWS/cost-management/cost-allocation-tags.md](../content/AWS/cost-management/cost-allocation-tags.md)                                                                                                                                                                                                                         |
| https://aws.amazon.com/cost-management/cost-allocation/pricing/            |  404 | [AWS/cost-management/cost-allocation-tags.md](../content/AWS/cost-management/cost-allocation-tags.md)                                                                                                                                                                                                                         |
| https://aws.amazon.com/cost-management/pricing/                            |  404 | [AWS/cost-management/README.md](../content/AWS/cost-management/README.md)                                                                                                                                                                                                                                                     |
| https://aws.amazon.com/database-migration-service/pricing/                 |  404 | [AWS/migration/README.md](../content/AWS/migration/README.md)                                                                                                                                                                                                                                                                 |
| https://aws.amazon.com/ec2/cost-optimization/                              |  404 | [AWS/cost-management/ec2-cost-optimization.md](../content/AWS/cost-management/ec2-cost-optimization.md)                                                                                                                                                                                                                       |
| https://aws.amazon.com/organizations/pricing/                              |  404 | [AWS/cost-management/organizations-cost-strategy.md](../content/AWS/cost-management/organizations-cost-strategy.md), [AWS/management-governance/README.md](../content/AWS/management-governance/README.md), [AWS/management-governance/organizations/README.md](../content/AWS/management-governance/organizations/README.md) |
| https://aws.amazon.com/pricing/compute/                                    |  404 | [AWS/compute/README.md](../content/AWS/compute/README.md)                                                                                                                                                                                                                                                                     |
| https://aws.amazon.com/pricing/storage/                                    |  404 | [AWS/storage/README.md](../content/AWS/storage/README.md)                                                                                                                                                                                                                                                                     |
| https://aws.amazon.com/products-management-tools/                          |  404 | [AWS/management-governance/README.md](../content/AWS/management-governance/README.md)                                                                                                                                                                                                                                         |
| https://aws.amazon.com/products/database-migration/                        |  404 | [AWS/migration/README.md](../content/AWS/migration/README.md)                                                                                                                                                                                                                                                                 |
| https://aws.amazon.com/products/databases/pricing/                         |  404 | [AWS/databases/README.md](../content/AWS/databases/README.md)                                                                                                                                                                                                                                                                 |
| https://aws.amazon.com/security/pricing/                                   |  404 | [AWS/security/README.md](../content/AWS/security/README.md)                                                                                                                                                                                                                                                                   |
| https://aws.amazon.com/storage-gateway/pricing/                            |  404 | [AWS/storage/storage-gateway/README.md](../content/AWS/storage/storage-gateway/README.md)                                                                                                                                                                                                                                     |
| https://docs.aws.amazon.com/amazonglacier/                                 |  403 | [AWS/storage/glacier/README.md](../content/AWS/storage/glacier/README.md)                                                                                                                                                                                                                                                     |
| https://docs.aws.amazon.com/AmazonRDS/                                     |  403 | [AWS/databases/rds/README.md](../content/AWS/databases/rds/README.md)                                                                                                                                                                                                                                                         |
| https://docs.aws.amazon.com/AmazonS3/latest/userguidegsg.html              |  403 | [AWS/cost-management/s3-cost-optimization.md](../content/AWS/cost-management/s3-cost-optimization.md)                                                                                                                                                                                                                         |
| https://docs.aws.amazon.com/AWSSimpleQueueService/                         |  403 | [AWS/application-integration/sqs/README.md](../content/AWS/application-integration/sqs/README.md)                                                                                                                                                                                                                             |
| https://docs.aws.amazon.com/compute/                                       |  404 | [AWS/compute/README.md](../content/AWS/compute/README.md)                                                                                                                                                                                                                                                                     |
| https://docs.aws.amazon.com/cost-management/                               |  403 | [AWS/cost-management/README.md](../content/AWS/cost-management/README.md)                                                                                                                                                                                                                                                     |
| https://docs.aws.amazon.com/databases/                                     |  404 | [AWS/databases/README.md](../content/AWS/databases/README.md)                                                                                                                                                                                                                                                                 |
| https://docs.aws.amazon.com/IAM/                                           |  403 | [AWS/security/iam/README.md](../content/AWS/security/iam/README.md)                                                                                                                                                                                                                                                           |
| https://docs.aws.amazon.com/opensearch/                                    |  404 | [AWS/analytics/opensearch/README.md](../content/AWS/analytics/opensearch/README.md)                                                                                                                                                                                                                                           |
| https://docs.aws.amazon.com/qldb/                                          |  404 | [AWS/databases/qldb/README.md](../content/AWS/databases/qldb/README.md)                                                                                                                                                                                                                                                       |
| https://docs.aws.amazon.com/sagemaker-canvas/                              |  404 | [AWS/machine-learning/sagemaker-canvas/README.md](../content/AWS/machine-learning/sagemaker-canvas/README.md)                                                                                                                                                                                                                 |
| https://docs.aws.amazon.com/storage-gateway/                               |  404 | [AWS/storage/storage-gateway/README.md](../content/AWS/storage/storage-gateway/README.md)                                                                                                                                                                                                                                     |
| https://docs.aws.amazon.com/storage/                                       |  404 | [AWS/storage/README.md](../content/AWS/storage/README.md)                                                                                                                                                                                                                                                                     |

## Resolving URLs

- https://aws.amazon.com/ai/services/
- https://aws.amazon.com/amazon-mq/
- https://aws.amazon.com/amazon-mq/pricing/
- https://aws.amazon.com/api-gateway/
- https://aws.amazon.com/api-gateway/pricing/
- https://aws.amazon.com/apprunner/
- https://aws.amazon.com/apprunner/pricing/
- https://aws.amazon.com/appsync/
- https://aws.amazon.com/appsync/pricing/
- https://aws.amazon.com/athena/
- https://aws.amazon.com/athena/pricing/
- https://aws.amazon.com/batch/
- https://aws.amazon.com/batch/pricing/
- https://aws.amazon.com/bedrock/
- https://aws.amazon.com/bedrock/pricing/
- https://aws.amazon.com/blogs/networking-and-content-delivery/
- https://aws.amazon.com/cdk/
- https://aws.amazon.com/certificate-manager/
- https://aws.amazon.com/certificate-manager/pricing/
- https://aws.amazon.com/cli/
- https://aws.amazon.com/cloudformation/
- https://aws.amazon.com/cloudformation/pricing/
- https://aws.amazon.com/cloudfront/
- https://aws.amazon.com/cloudfront/pricing/
- https://aws.amazon.com/cloudtrail/
- https://aws.amazon.com/cloudtrail/pricing/
- https://aws.amazon.com/cloudwatch/
- https://aws.amazon.com/cloudwatch/pricing/
- https://aws.amazon.com/comprehend/
- https://aws.amazon.com/comprehend/pricing/
- https://aws.amazon.com/config/
- https://aws.amazon.com/config/pricing/
- https://aws.amazon.com/controltower/
- https://aws.amazon.com/controltower/pricing/
- https://aws.amazon.com/detective/
- https://aws.amazon.com/detective/pricing/
- https://aws.amazon.com/directconnect/
- https://aws.amazon.com/directconnect/pricing/
- https://aws.amazon.com/documentdb/
- https://aws.amazon.com/documentdb/pricing/
- https://aws.amazon.com/dynamodb/
- https://aws.amazon.com/dynamodb/pricing/
- https://aws.amazon.com/ebs/
- https://aws.amazon.com/ebs/pricing/
- https://aws.amazon.com/ec2/
- https://aws.amazon.com/ec2/pricing/
- https://aws.amazon.com/ec2/pricing/on-demand/
- https://aws.amazon.com/ec2/pricing/reserved-instances/
- https://aws.amazon.com/ec2/pricing/reserved-instances/marketplace/
- https://aws.amazon.com/ec2/pricing/reserved-instances/pricing/
- https://aws.amazon.com/ecs/
- https://aws.amazon.com/ecs/pricing/
- https://aws.amazon.com/efs/
- https://aws.amazon.com/efs/pricing/
- https://aws.amazon.com/eks/
- https://aws.amazon.com/eks/pricing/
- https://aws.amazon.com/elasticache/
- https://aws.amazon.com/elasticache/pricing/
- https://aws.amazon.com/elasticloadbalancing/
- https://aws.amazon.com/elasticloadbalancing/pricing/
- https://aws.amazon.com/emr/
- https://aws.amazon.com/emr/pricing/
- https://aws.amazon.com/eventbridge/
- https://aws.amazon.com/eventbridge/pricing/
- https://aws.amazon.com/fsx/
- https://aws.amazon.com/fsx/pricing/
- https://aws.amazon.com/glacier/
- https://aws.amazon.com/glacier/pricing/
- https://aws.amazon.com/glue/
- https://aws.amazon.com/glue/pricing/
- https://aws.amazon.com/guardduty/
- https://aws.amazon.com/guardduty/pricing/
- https://aws.amazon.com/iam/
- https://aws.amazon.com/iam/pricing/
- https://aws.amazon.com/inspector/
- https://aws.amazon.com/inspector/pricing/
- https://aws.amazon.com/kinesis/data-analytics/
- https://aws.amazon.com/kinesis/data-analytics/pricing/
- https://aws.amazon.com/kinesis/data-firehose/
- https://aws.amazon.com/kinesis/data-firehose/pricing/
- https://aws.amazon.com/kinesis/data-streams/
- https://aws.amazon.com/kinesis/data-streams/pricing/
- https://aws.amazon.com/kms/
- https://aws.amazon.com/kms/pricing/
- https://aws.amazon.com/lambda/
- https://aws.amazon.com/lambda/pricing/
- https://aws.amazon.com/lightsail/
- https://aws.amazon.com/lightsail/pricing/
- https://aws.amazon.com/machine-learning/
- https://aws.amazon.com/machine-learning/pricing/
- https://aws.amazon.com/macie/
- https://aws.amazon.com/macie/pricing/
- https://aws.amazon.com/neptune/
- https://aws.amazon.com/neptune/pricing/
- https://aws.amazon.com/networking/
- https://aws.amazon.com/opensearch-service/
- https://aws.amazon.com/opensearch-service/pricing/
- https://aws.amazon.com/organizations/
- https://aws.amazon.com/pricing/
- https://aws.amazon.com/products/application-integration/
- https://aws.amazon.com/products/compute/
- https://aws.amazon.com/products/databases/
- https://aws.amazon.com/products/storage/
- https://aws.amazon.com/qldb/
- https://aws.amazon.com/qldb/pricing/
- https://aws.amazon.com/rds/
- https://aws.amazon.com/rds/aurora/
- https://aws.amazon.com/rds/aurora/pricing/
- https://aws.amazon.com/rds/pricing/
- https://aws.amazon.com/redshift/
- https://aws.amazon.com/redshift/pricing/
- https://aws.amazon.com/rekognition/
- https://aws.amazon.com/rekognition/pricing/
- https://aws.amazon.com/route53/
- https://aws.amazon.com/route53/pricing/
- https://aws.amazon.com/s3/
- https://aws.amazon.com/s3/pricing/
- https://aws.amazon.com/sagemaker/
- https://aws.amazon.com/sagemaker/canvas/
- https://aws.amazon.com/sagemaker/canvas/pricing/
- https://aws.amazon.com/sagemaker/pricing/
- https://aws.amazon.com/savingsplans/
- https://aws.amazon.com/savingsplans/pricing/
- https://aws.amazon.com/secrets-manager/
- https://aws.amazon.com/secrets-manager/pricing/
- https://aws.amazon.com/security-hub/
- https://aws.amazon.com/security-hub/pricing/
- https://aws.amazon.com/security/
- https://aws.amazon.com/serverless/
- https://aws.amazon.com/sns/
- https://aws.amazon.com/sns/pricing/
- https://aws.amazon.com/sqs/
- https://aws.amazon.com/sqs/pricing/
- https://aws.amazon.com/step-functions/
- https://aws.amazon.com/step-functions/pricing/
- https://aws.amazon.com/storage-gateway/
- https://aws.amazon.com/systems-manager/
- https://aws.amazon.com/systems-manager/pricing/
- https://aws.amazon.com/timestream/
- https://aws.amazon.com/timestream/pricing/
- https://aws.amazon.com/transit-gateway/
- https://aws.amazon.com/transit-gateway/pricing/
- https://aws.amazon.com/vpc/
- https://aws.amazon.com/vpc/pricing/
- https://aws.amazon.com/waf/
- https://aws.amazon.com/waf/pricing/
- https://docs.aws.amazon.com/acm/
- https://docs.aws.amazon.com/amazon-mq/
- https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/
- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/
- https://docs.aws.amazon.com/apigateway/
- https://docs.aws.amazon.com/apprunner/
- https://docs.aws.amazon.com/appsync/
- https://docs.aws.amazon.com/athena/latest/ug/
- https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/allocation-tag-support.html
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AmazonEBS.html
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts.html
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-reserved-instances.html
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ri-market-general.html
- https://docs.aws.amazon.com/batch/
- https://docs.aws.amazon.com/bedrock/
- https://docs.aws.amazon.com/cdk/
- https://docs.aws.amazon.com/cli/
- https://docs.aws.amazon.com/cloudformation/
- https://docs.aws.amazon.com/cloudfront/
- https://docs.aws.amazon.com/cloudtrail/
- https://docs.aws.amazon.com/cloudwatch/
- https://docs.aws.amazon.com/comprehend/
- https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html
- https://docs.aws.amazon.com/config/
- https://docs.aws.amazon.com/controltower/
- https://docs.aws.amazon.com/cost-management/latest/userguide/
- https://docs.aws.amazon.com/cost-management/latest/userguide/budgets.html
- https://docs.aws.amazon.com/cost-management/latest/userguide/configure-cost-tags.html
- https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started_cost_anomaly_detection.html
- https://docs.aws.amazon.com/cost-management/latest/userguide/what-is-cost-explorer.html
- https://docs.aws.amazon.com/detective/
- https://docs.aws.amazon.com/directconnect/
- https://docs.aws.amazon.com/dms/latest/userguide/
- https://docs.aws.amazon.com/documentdb/
- https://docs.aws.amazon.com/dynamodb/
- https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-lifecycle.html
- https://docs.aws.amazon.com/ecs/
- https://docs.aws.amazon.com/efs/
- https://docs.aws.amazon.com/eks/
- https://docs.aws.amazon.com/elasticache/
- https://docs.aws.amazon.com/elasticloadbalancing/
- https://docs.aws.amazon.com/emr/latest/ManagementGuide/
- https://docs.aws.amazon.com/eventbridge/
- https://docs.aws.amazon.com/firehose/latest/dev/
- https://docs.aws.amazon.com/fsx/
- https://docs.aws.amazon.com/glue/latest/dg/
- https://docs.aws.amazon.com/guardduty/
- https://docs.aws.amazon.com/inspector/
- https://docs.aws.amazon.com/kinesisanalytics/latest/dev/
- https://docs.aws.amazon.com/kms/
- https://docs.aws.amazon.com/lambda/
- https://docs.aws.amazon.com/lambda/latest/dg/welcome.html
- https://docs.aws.amazon.com/lightsail/
- https://docs.aws.amazon.com/machine-learning/
- https://docs.aws.amazon.com/macie/
- https://docs.aws.amazon.com/neptune/
- https://docs.aws.amazon.com/organizations/
- https://docs.aws.amazon.com/organizations/latest/userguide/
- https://docs.aws.amazon.com/redshift/
- https://docs.aws.amazon.com/redshift/latest/dg/
- https://docs.aws.amazon.com/rekognition/
- https://docs.aws.amazon.com/route53/
- https://docs.aws.amazon.com/sagemaker/
- https://docs.aws.amazon.com/savingsplans/latest/userguide/
- https://docs.aws.amazon.com/secretsmanager/
- https://docs.aws.amazon.com/security/
- https://docs.aws.amazon.com/securityhub/
- https://docs.aws.amazon.com/sns/
- https://docs.aws.amazon.com/step-functions/
- https://docs.aws.amazon.com/streams/latest/dev/
- https://docs.aws.amazon.com/systems-manager/
- https://docs.aws.amazon.com/timestream/
- https://docs.aws.amazon.com/vpc/
- https://docs.aws.amazon.com/vpc/latest/peering/
- https://docs.aws.amazon.com/vpc/latest/tgw/
- https://docs.aws.amazon.com/vpc/latest/userguide/
- https://docs.aws.amazon.com/vpc/latest/userguide/network-acls.html
- https://docs.aws.amazon.com/vpc/latest/userguide/security-groups.html
- https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- https://docs.aws.amazon.com/waf/
