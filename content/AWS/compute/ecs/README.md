---
title: "Amazon ECS"
description: "Distinguish cluster, task, service and IAM roles, then run a complete Fargate task and diagnose its lifecycle."
tags:
  - cloud/aws/compute/containers
date: 2026-10-12
---

# Amazon ECS

ECS schedules tasks from versioned task definitions and maintains long-running services. EC2 capacity requires host operations; Fargate manages hosts but still requires correct task resources, networking, identities and deployment policy. Start with [[AWS/compute/ecr|image lifecycle]] and [[AWS/networking/vpc/README|VPC]].

## Core distinctions

A cluster groups capacity and workloads. A task definition specifies containers, resource/platform/network constraints and roles. A task is one execution; a service maintains desired tasks and deployment state.

The **task execution role** supports image pull/logging and selected launch-time secrets operations. The **task role** authorizes application AWS calls. An EC2 host role is different again. All containers in one task share its task role; split trust boundaries when needed.

## Complete one-off Fargate exercise

Prerequisites: a sandbox cluster, private subnet with approved internet egress for the public image (or a private ECR mirror with the required endpoints), plus reachable CloudWatch Logs, a task SG, log group `/ecs/wiki-ecs-lab`, and an execution role trusting ecs-tasks.amazonaws.com with the required log/image access. The tiny application makes no AWS API calls and needs no task role. Confirm architecture/Region compatibility and charges before deployment.

Save as `task-definition.json`, replacing execution-role ARN and log Region. Pin a reviewed image digest for production.

```json
{
  "family": "wiki-ecs-lab",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::111122223333:role/REPLACE_WITH_LAB_EXECUTION_ROLE",
  "containerDefinitions": [
    {
      "name": "checkpoint",
      "image": "public.ecr.aws/docker/library/alpine:3",
      "essential": true,
      "command": ["/bin/sh", "-c", "echo ECS-lab-ok; sleep 30"],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/wiki-ecs-lab",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "checkpoint"
        }
      }
    }
  ]
}
```

```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
aws ecs run-task \
  --cluster "$ECS_LAB_CLUSTER" --task-definition wiki-ecs-lab \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$ECS_LAB_SUBNET_ID],securityGroups=[$ECS_LAB_SG_ID],assignPublicIp=DISABLED}"
```

Record the task ARN, inspect failures in the run response and call describe-tasks through RUNNING to STOPPED. Expected: exit code zero and ECS-lab-ok in the log stream. A full task definition goes to --cli-input-json; --container-definitions accepts only the container array.

Failure exercise: in a second disposable revision, exit nonzero. Describe-tasks must show the application exit, rather than treating every STOPPED task as success. Image-pull and resource-initialization failures require checking execution role, DNS, routes and endpoint/SG access.

## Services, scaling and health

For a web service, configure an IP-type target group for awsvpc, container name/port mapping, listener, target SG and health checks; choose desired count and deployment circuit-breaker/rollback policy. Standalone tasks do not auto-register with an arbitrary ALB.

HEALTHY container dependencies require a defined health check on the referenced container. Do not declare a dependency on an unchecked sidecar. CPU service metrics come from ECS; custom application metrics are needed for other workload signals, not basic CPU visibility.

Application Auto Scaling uses --service-namespace ecs and resource ID service/CLUSTER/SERVICE. A scalable service does not automatically create/scale EC2 cluster capacity; design capacity providers separately. Cloud Map DNS services require namespace and supported DNS record definitions; creating a registry does not attach it to an ECS service.

## Storage, cost and cleanup

Supported Linux Fargate platforms provide 20 GiB ephemeral storage by default, configurable to 200 GiB. It is not durable across task replacement. Evaluate EFS and other supported volume integrations by platform/version; do not claim every task can use every storage mode.

Price provisioned vCPU/memory, duration and storage extras by Region/OS/architecture, then add images, logs, network and load balancers. Compare equal workload capacity with EC2 rather than claiming one launch type is always cheaper.

Stop leftover tasks, set dedicated service desired count to zero and delete it if used, deregister dedicated task revisions, remove lab logs and delete the empty lab cluster. Inspect ENIs, load balancers, scaling targets and persistent volumes separately.

## ECS versus EKS and the service path

| Decision     | ECS                                                                 | EKS                                                            |
| ------------ | ------------------------------------------------------------------- | -------------------------------------------------------------- |
| API model    | Task definitions, services and clusters                             | Kubernetes workloads, Services and controllers                 |
| Workload IAM | ECS task role                                                       | Pod Identity or IRSA                                           |
| Host options | EC2 capacity or Fargate                                             | Supported nodes, Fargate or other EKS operating modes          |
| Best fit     | AWS-native container orchestration with fewer Kubernetes components | A workload or team requiring Kubernetes APIs and its ecosystem |

```text
Image registry → task definition revision → task
                                   ├─ execution role: pull image, send logs
                                   ├─ task role: application AWS calls
                                   └─ ENI/SG: reach database or other services
ECS service → desired count → replacement/rolling deployment
            └─ optional target group + listener for inbound traffic
```

For a web deployment, register a new task definition revision, update the service to that revision, and watch deployment and target health. Keep the prior working revision for rollback. Check `describe-services` for rollout state and `describe-tasks` for stopped reasons; CloudWatch logs show application output, while image pull failures can occur before any container log exists. A service's minimum healthy and maximum percent settings control deployment concurrency; set them together with spare capacity and availability requirements.

Service discovery is another independent step. A Cloud Map namespace/service can give tasks a discoverable name, but the ECS service must be configured to register its tasks, and callers need matching DNS/network access. A created Cloud Map service does not automatically wire an existing ECS deployment. For internal request routing, compare Cloud Map DNS with ECS Service Connect and VPC Lattice according to traffic-management and identity requirements.

Use separate checks for roles, networking and application behavior when debugging:

1. Image pull fails: verify the image URI/digest, execution-role permissions, DNS and registry network path.
2. Task starts then exits: inspect container exit code and logs; check command, memory, secrets and health-check configuration.
3. Task stays healthy but receives no requests: inspect service target group attachment, target type, listener rules, target health and SG paths.
4. Desired count is unmet: inspect service events and compatible Fargate resource values or EC2 capacity-provider capacity.

## References

- [Task definition parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html).
- [Execution role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html).
- [Service scaling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html).
- [Fargate storage](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-storage.html).
- [Fargate pricing](https://aws.amazon.com/fargate/pricing/).
- Next: [[AWS/compute/eks/README|EKS comparison]] and [[AWS/developer-tools/README|delivery pipeline]].

## Across the wiki

- [[Azure/compute/container-apps/README|Azure Container Apps (ACA), KEDA, and Dapr Microservices]] — serverless containers (Azure)
- [[GCP/compute/cloud-run|GCP Cloud Run]] — serverless containers (GCP)
- [[Kubernetes/eks/compute/fargate/README|AWS Fargate on EKS]] — serverless containers (Kubernetes)
- [[Azure/compute/app-service/README|Azure App Service Architecture, Deployment Slots, and VNet Integration]] — serverless containers (Azure)
