---
title: OpenTelemetry Semantic Conventions
description: Standardized resource and span attribute naming
tags:
  - opentelemetry
  - semantic-conventions
date: 2025-01-01
draft: false
---

# OpenTelemetry Semantic Conventions

Semantic conventions define **standard names and values** for attributes on resources and spans. They ensure consistent attribute naming across instrumentation libraries, SDKs, and backends.

## Stability Levels

| Level | Meaning |
|-------|---------|
| **Stable** | Frozen; no breaking changes |
| **Experimental** | May change; opt-in via `schema_url` |
| **Deprecated** | Will be removed |

## Resource Attributes

Resources represent the **entity producing telemetry** (service, container, host, cloud, etc.).

### Service

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `service.name` | string | **Required.** Logical name of the service | `"auth-service"` |
| `service.namespace` | string | Namespace grouping services | `"payments"` |
| `service.version` | string | Version of the service | `"1.3.0"` |
| `service.instance.id` | string | Unique instance ID | `"instance-12"` |
| `service.language.name` | string | Language/runtime | `"java"`, `"python"` |

### Container

| Attribute | Type | Description |
|-----------|------|-------------|
| `container.name` | string | Container name |
| `container.id` | string | Container runtime ID |
| `container.image.name` | string | Image name |
| `container.image.tag` | string | Image tag |
| `container.runtime` | string | Runtime (docker, containerd, etc.) |
| `container.command` | string | Command run in container |

### Kubernetes

| Attribute | Type | Description |
|-----------|------|-------------|
| `k8s.namespace.name` | string | Namespace |
| `k8s.pod.name` | string | Pod name |
| `k8s.pod.uid` | string | Pod UID |
| `k8s.deployment.name` | string | Deployment name |
| `k8s.statefulset.name` | string | StatefulSet name |
| `k8s.daemonset.name` | string | DaemonSet name |
| `k8s.job.name` | string | Job name |
| `k8s.cronjob.name` | string | CronJob name |
| `k8s.container.name` | string | Container name |
| `k8s.container.restart_count` | int | Restart count |
| `k8s.node.name` | string | Node name |
| `k8s.node.uid` | string | Node UID |

### Cloud (AWS, GCP, Azure)

**AWS:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `cloud.provider` | string | Always `"aws"` |
| `cloud.account.id` | string | AWS Account ID |
| `cloud.region` | string | Region |
| `cloud.availability_zone` | string | AZ |
| `cloud.platform` | string | `"aws_ec2"`, `"aws_ecs"`, `"aws_eks"` |
| `aws.ec2.instance.id` | string | EC2 instance ID |
| `aws.ecs.cluster.arn` | string | ECS cluster ARN |
| `aws.ecs.service.name` | string | ECS service name |
| `aws.eks.cluster.arn` | string | EKS cluster ARN |

**GCP:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `cloud.provider` | string | Always `"gcp"` |
| `cloud.account.id` | string | Project ID |
| `cloud.region` | string | Region |
| `cloud.platform` | string | `"gcp_gce"`, `"gcp_gke"`, `"gcp_cloud_run"` |
| `gcp.gce.instance.name` | string | GCE instance name |
| `gcp.gke.cluster.name` | string | GKE cluster name |

**Azure:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `cloud.provider` | string | Always `"azure"` |
| `cloud.account.id` | string | Subscription ID |
| `cloud.region` | string | Region |
| `cloud.platform` | string | `"azure_vm"`, `"azure_container_instances"`, `"azure_aks"` |
| `azure.vm.name` | string | VM name |
| `azure.aks.cluster.name` | string | AKS cluster name |

### Host

| Attribute | Type | Description |
|-----------|------|-------------|
| `host.name` | string | Hostname |
| `host.id` | string | Host ID (machine UUID) |
| `host.type` | string | Machine type |
| `host.arch` | string | Architecture |
| `host.image.name` | string | VM image name |
| `host.image.id` | string | VM image ID |

### OS

| Attribute | Type | Description |
|-----------|------|-------------|
| `os.type` | string | `"linux"`, `"windows"`, `"darwin"` |
| `os.name` | string | OS name |
| `os.version` | string | OS version |
| `os.description` | string | Full OS description |

### Telemetry SDK

| Attribute | Type | Description |
|-----------|------|-------------|
| `telemetry.sdk.name` | string | Always `"opentelemetry"` |
| `telemetry.sdk.version` | string | OTel SDK version |
| `telemetry.sdk.language` | string | `"python"`, `"java"`, `"go"` |

## Span Attributes

### General HTTP

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `http.request.method` | string | HTTP method | `"GET"`, `"POST"` |
| `http.response.status_code` | int | HTTP status code | `200`, `404`, `500` |
| `http.url` | string | Full URL | `https://api.example.com/users` |
| `http.scheme` | string | `"http"` or `"https"` |
| `http.host` | string | Host header | `"api.example.com"` |
| `http.target` | string | Path + query | `"/users?id=42"` |
| `http.user_agent` | string | User-Agent header | |
| `http.request_content_length` | int | Request body size |
| `http.response_content_length` | int | Response body size |

### Specific HTTP

| Attribute | Type | Description |
|-----------|------|-------------|
| `http.server_name` | string | Server name (virtual) |
| `http.route` | string | Matched route pattern | `"/users/{id}"` |
| `http.client_ip` | string | Client IP address |

### Database

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `db.system` | string | Database type | `"postgresql"`, `"redis"` |
| `db.name` | string | Database name | `"orders_db"` |
| `db.statement` | string | Query statement | `"SELECT * FROM orders"` |
| `db.operation` | string | Operation name | `"SELECT"`, `"INSERT"` |
| `db.sql.table` | string | Table name | `"orders"` |
| `db.user` | string | Username | `"app_user"` |
| `db.connection_string` | string | Connection string |
| `db.cursor.name` | string | Cursor name |
| `db.lock_timeout` | int | Lock timeout (ms) |
| `db.transaction_id` | string | Transaction ID |

### RPC (gRPC)

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `rpc.system` | string | `"grpc"`, `"jsonrpc"`, `"connect"` |
| `rpc.service` | string | Full service name | `"grpc.health.v1.Health"` |
| `rpc.method` | string | Method name | `"Check"` |
| `rpc.request.rpc_name` | string | RPC name (alias for service+method) |
| `rpc.request.status_code` | int | gRPC status code |
| `rpc.grpc.status_code` | int | Numeric gRPC status |

### Messaging

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `messaging.system` | string | System | `"kafka"`, `"rabbitmq"`, `"sqs"` |
| `messaging.destination` | string | Queue/topic name | `"orders"` |
| `messaging.operation` | string | `"publish"`, `"receive"`, `"process"` |
| `messaging.message_id` | string | Message ID |
| `messaging.conversation_id` | string | Conversation/session ID |
| `messaging.message.payload_size_bytes` | int | Payload size |
| `messaging.destination_kind` | string | `"queue"` or `"topic"` |

### FaaS (Serverless)

| Attribute | Type | Description |
|-----------|------|-------------|
| `faas.name` | string | Function name |
| `faas.version` | string | Function version |
| `faas.instance` | string | Function instance ID |
| `faas.invocation_id` | string | Invocation/request ID |
| `faas.trigger` | string | Trigger type |

### Events

| Attribute | Type | Description |
|-----------|------|-------------|
| `event.name` | string | Event name |
| `event.id` | string | Event ID |
| `event.domain` | string | `"domain"` (e.g., `"browser"`) |

### Exceptions

| Attribute | Type | Description |
|-----------|------|-------------|
| `exception.type` | string | Exception type | `RuntimeError` |
| `exception.message` | string | Exception message |
| `exception.stacktrace` | string | Full stack trace |
| `exception.escaped` | bool | Whether exception escaped the span |

## Network Attributes

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| `network.transport` | string | `"tcp"`, `"udp"`, `"pipe"` |
| `network.protocol` | string | Protocol name | `"http"`, `"amqp"` |
| `network.protocol_version` | string | Protocol version | `"1.2"` |
| `network.type` | string | `"ipv4"`, `"ipv6"` |
| `network.local.address` | string | Local address | `"10.0.0.1"` |
| `network.local.port` | int | Local port | `8080` |
| `network.remote.address` | string | Remote address | `"54.23.0.1"` |
| `network.remote.port` | int | Remote port | `443` |

## User-Agent

Parsed from `http.user_agent`:

| Attribute | Type | Description |
|-----------|------|-------------|
| `user_agent.original` | string | Full User-Agent string |
| `user_agent.name` | string | Browser name |
| `user_agent.version` | string | Browser version |
| `user_agent.os.name` | string | OS name |
| `user_agent.os.version` | string | OS version |
| `user_agent.device.arch` | string | Device architecture |

## URL Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `url.scheme` | string | Scheme (http, https) |
| `url.domain` | string | Domain name |
| `url.port` | int | Port |
| `url.path` | string | Path |
| `url.query` | string | Query string |
| `url.fragment` | string | Fragment |

## Example: Setting Resource Attributes

### Go

```go
import "go.opentelemetry.io/otel/sdk/resource"

res, err := resource.New(ctx,
    resource.WithAttributes(
        attribute.String("service.name", "auth-service"),
        attribute.String("service.version", "1.2.3"),
        attribute.String("deployment.environment", "production"),
        attribute.String("cloud.region", "us-east-1"),
        attribute.String("cloud.provider", "aws"),
    ),
    resource.WithHost(),
    resource.WithOS(),
    resource.WithContainer(),
)

tp := trace.NewTracerProvider(trace.WithResource(res))
```

### Python

```python
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION

resource = Resource.create({
    SERVICE_NAME: "auth-service",
    SERVICE_VERSION: "1.2.3",
    "deployment.environment": "production",
    "cloud.region": "us-east-1",
    "cloud.provider": "aws",
})

provider = TracerProvider(resource=resource)
```

### Kubernetes (via Collector k8sattributes processor)

```yaml
processors:
  k8sattributes:
    extract:
      metadata:
        - k8s.namespace.name
        - k8s.deployment.name
        - k8s.pod.name
        - k8s.container.name
```

## Convention Compatibility

OTel spec versions map to schema URLs:

| Spec Version | Schema URL |
|-------------|-----------|
| v1.23.0+ | `https://opentelemetry.io/schemas/1.23.0` |
| v1.22.0+ | `https://opentelemetry.io/schemas/1.22.0` |
| Older | No schema URL or `v1.21.0` |

SDKs and instrumentation libraries include the schema URL in exports so backends can parse correctly.
