---
title: "AWS App Runner"
description: "Deploy a small source/image web service with distinct build/application roles, private-access choices and active/provisioned cost accounting."
tags:
  - cloud/aws/serverless
date: 2026-10-12
---

# AWS App Runner

App Runner **closed to new customers on March 31, 2026**. Existing customers can continue using it under the owning availability notice. New learners should use the supported ECS workflow and evaluate ECS Express Mode. Existing-customer App Runner deployments support source repositories or container images. A user-supplied Dockerfile is not universally required. Compare [[AWS/compute/ecs/README|ECS/Fargate]] when you need more deployment/network/runtime control.

## Deployment and identity

Source builds require supported runtime/build/start configuration and an approved repository connection. Image deployments use a compatible image/port and access configuration. The ECR image access role trusts build.apprunner.amazonaws.com; the application instance role authorizes application AWS calls. Do not combine these into a blanket administrator role.

Reference supported Secrets Manager/Parameter Store values through the documented environment-secret configuration; do not embed API keys in source or plain environment examples. Review access role, instance role and KMS/resource permissions.

## Inbound versus outbound access

A VPC connector provides outbound access to private dependencies. Private incoming access uses a VPC ingress connection and endpoint separately. A public default endpoint is not an unavoidable product constraint.

HTTP requests have a 120-second timeout. Offload longer work to a queue/worker and return an explicit job identifier/status. Health probes need a reachable supported path/protocol; a healthy instance does not prove a successful database transaction.

## Sandbox deployment exercise

Prerequisites: an account already eligible for App Runner (new-customer access is closed), a sandbox repository/image serving a nonsensitive greeting and /health, scoped roles/connection, a budget and a selected public or private access design.

1. Test the application locally and record the source revision/image digest.
2. Create a service using the owning source or image console workflow. Set build/start command or image port, CPU/memory and dedicated IAM roles.
3. Wait for the operation to succeed; inspect deployment logs and the actual endpoint.
4. Invoke the greeting and health paths from the intended client. For private ingress, test from both allowed and excluded network paths.
5. Deploy a sandbox revision with a failing health path; inspect the failure and restore the known-good revision.
6. Enable supported X-Ray/ADOT tracing and correlate one request; no universal auto-instrumentation claim is implied.

Check CloudWatch logs for the correct revision/error, and verify the application role cannot access an unrelated AWS resource.

## Cost and cleanup

Provisioned idle instances bill memory; active instances bill the applicable CPU/memory model without double-counting provisioned memory. Source build time and automated deployment can add charges. Price actual active/provisioned instance-hours and instance count; two average instances cannot keep a one-instance subtotal.

Remove dedicated VPC ingress connections before deleting the service: DeleteService cannot proceed while those connections remain active. Pause/delete the eligible lab service according to the intended lifecycle, then remove dedicated outbound connectors, logs and temporary image/build artifacts only when no shared service uses them; verify remaining charges/resources. Pausing does not prove all surrounding resources were removed.

## Existing-customer service selection and architecture

| Requirement              | App Runner (eligible existing customers)    | Supported alternative                                                       |
| ------------------------ | ------------------------------------------- | --------------------------------------------------------------------------- |
| Source build/start       | Supported connected source/runtime workflow | Build image then ECS/Express Mode or another supported platform             |
| Container web endpoint   | Supported image/port/health/scaling         | ECS/Fargate with selected ingress/deployment controls                       |
| Long worker job          | HTTP request timeout still applies          | Queue/Batch/ECS worker with durable results                                 |
| Hardware/OS control      | Not a generic VM/device interface           | Supported EC2/container capacity; Fargate does not universally provide GPUs |
| Advanced routing/network | Product-specific ingress/egress boundaries  | Requirements-driven ECS/EKS/VPC design                                      |
| Event handler            | Not Lambda's invocation/event mapping model | Lambda or explicit worker integration                                       |

```text
source connection → supported build → service deployment
private ECR image → access role ─────→ service deployment
                                        ↓
client → public/private ingress → healthy instance → private dependency
                                        │              ↑
                              application role     VPC egress connector
```

ECR access role and application instance role are distinct. A VPC egress connector neither makes incoming traffic private nor gives application credentials. ECS supports service autoscaling; Lambda supports images, so the previous categorical comparison must not be reused.

## Complete image-service request

Only for an already eligible sandbox account. Prerequisites: an immutable reviewed x86-compatible image/tag as currently supported, port 8080 with a nonsensitive /health/greeting, scoped creator and private-ECR access role trusting build.apprunner.amazonaws.com. Replace placeholders in app-runner.json:

```json
{
  "ServiceName": "wiki-app-runner-lab",
  "SourceConfiguration": {
    "AuthenticationConfiguration": { "AccessRoleArn": "ECR_ACCESS_ROLE_ARN" },
    "ImageRepository": {
      "ImageIdentifier": "ACCOUNT.dkr.ecr.REGION.amazonaws.com/wiki-app:lab-v1",
      "ImageRepositoryType": "ECR",
      "ImageConfiguration": {
        "Port": "8080",
        "RuntimeEnvironmentVariables": { "ENV": "lab" }
      }
    },
    "AutoDeploymentsEnabled": false
  },
  "InstanceConfiguration": { "Cpu": "1024", "Memory": "2048" },
  "HealthCheckConfiguration": {
    "Protocol": "HTTP",
    "Path": "/health",
    "Interval": 10,
    "Timeout": 5,
    "HealthyThreshold": 2,
    "UnhealthyThreshold": 3
  }
}
```

```bash
aws apprunner create-service --cli-input-json file://app-runner.json
aws apprunner list-operations --service-arn SERVICE_ARN
aws apprunner describe-service --service-arn SERVICE_ARN
```

Record the service/operation ARNs and poll with timeout through success/failure. Test actual endpoint/health/deployed marker. A TCP check ignores an HTTP path; choose the intended protocol. Environment variables are maps, not the old Key/Value array, and role authentication is required for the private image.

## Source-code and secret configuration

Existing source deployments need approved ConnectionArn, RepositoryUrl/SourceCodeVersion and supported CodeConfiguration runtime/build/start/port. Verify connection availability and current runtime versions; select the actual supported runtime rather than an obsolete enum.

RuntimeEnvironmentSecrets is a supported key→secret/parameter ARN map in the appropriate source code/image configuration. The instance role needs scoped secret/parameter/KMS access. Setting EncryptionConfiguration alone does not inject a runtime secret, and service encryption settings cannot universally be modified after creation.

Do not place DATABASE_URL passwords/API keys in examples or build logs. Validate rotation/update behavior and application caching; changing a secret value does not automatically prove the running application consumed the new version.

## Scaling, domain and network operations

Create a named supported scaling configuration with min/max size and concurrency, not desired-size:

```bash
aws apprunner create-auto-scaling-configuration \
  --auto-scaling-configuration-name wiki-lab-scale \
  --min-size 1 --max-size 2 --max-concurrency 20
aws apprunner associate-custom-domain --service-arn SERVICE_ARN \
  --domain-name LAB_DOMAIN
```

Attach the returned scaling-configuration ARN through update-service and inspect rollout. MaxConcurrency is a service scaling signal, not a global transactional limit. Restore prior configuration after the test.

Follow every returned domain-validation/target DNS record and verify TLS/hostname/renewal. A custom-domain association is not a finished DNS deployment.

VPC network configuration nests EgressType/VpcConnectorArn under EgressConfiguration. Private ingress requires its separate endpoint/ingress association and IsPubliclyAccessible setting. Confirm DNS/routes/SGs, non-VPC service dependencies and NAT/endpoints where needed; egress through a private subnet has its own reachability and cost.

## Monitoring, billing and migration handoff

Inspect application versus service/deployment log groups and their actual service ID/paths; /aws/apprunner/my-app alone is not a universal group name. Correlate ListOperations/DescribeService state, deployed revision, health and request/error/latency/active capacity. ADOT/X-Ray instrumentation is configured and tested, not a blanket automatic trace promise.

Price memory-hours for retained provisioned/active capacity and the actual active CPU model without double-counting shared dimensions. If two instances each retain M GB for H hours, memory quantity is 2×M×H; active CPU adds its own instance-hours. Source builds/deployments, networking/logs and dependencies add cost. There is no universal fifteen-dollar app.

For new customers follow ECS/Express Mode; for existing migration inventory secrets/roles/domains/network/health/scaling and build images if source-based. DNS traffic shifting has cached-client/rollback effects. Remove dedicated ingress connections before deleting App Runner, then unused connectors/scaling config/domain/log/image/role artifacts according to dependencies. Preserve the new target and rollback during acceptance.

References: [CreateService contract](https://docs.aws.amazon.com/cli/latest/reference/apprunner/create-service.html), [source configuration](https://docs.aws.amazon.com/apprunner/latest/dg/manage-configure.html), [scaling](https://docs.aws.amazon.com/apprunner/latest/dg/manage-autoscaling.html), [custom domains](https://docs.aws.amazon.com/apprunner/latest/dg/manage-custom-domains.html), [environment secrets](https://docs.aws.amazon.com/apprunner/latest/dg/env-variable.html), [networking](https://docs.aws.amazon.com/apprunner/latest/dg/network.html).

## Across the wiki

- [[Azure/compute/container-apps/README|Azure Container Apps (ACA), KEDA, and Dapr Microservices]] — serverless containers (Azure)
- [[GCP/compute/cloud-run|GCP Cloud Run]] — serverless containers (GCP)
- [[Kubernetes/eks/compute/fargate/README|AWS Fargate on EKS]] — serverless containers (Kubernetes)
- [[Azure/compute/app-service/README|Azure App Service Architecture, Deployment Slots, and VNet Integration]] — serverless containers (Azure)

## References

- [Source deployment](https://docs.aws.amazon.com/apprunner/latest/dg/service-source-code.html).
- [Role distinctions](https://docs.aws.amazon.com/apprunner/latest/dg/security_iam_service-with-iam.html).
- [Private incoming access](https://docs.aws.amazon.com/apprunner/latest/dg/network-pl.html).
- [Request processing](https://docs.aws.amazon.com/apprunner/latest/dg/develop.html).
- [Tracing](https://docs.aws.amazon.com/apprunner/latest/dg/monitor-xray.html).
- [Current pricing](https://aws.amazon.com/apprunner/pricing/).

## Availability and lifecycle sources

- [Owning availability notice and ECS Express Mode guidance](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html).
- [CreateService eligibility notice](https://docs.aws.amazon.com/apprunner/latest/api/API_CreateService.html).
- [DeleteService and ingress prerequisites](https://docs.aws.amazon.com/apprunner/latest/api/API_DeleteService.html).
