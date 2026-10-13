---
title: Amazon MQ
description: Amazon MQ — managed ActiveMQ and RabbitMQ brokers. Protocol support (JMS, AMQP, MQTT, OpenWire), deployment modes, encryption, and migration from self-managed brokers.
tags:
  - aws/application-integration
date: 2026-10-12
---

# Amazon MQ

Prerequisites: [[AWS/security/iam/README|scoped IAM roles]] and [[AWS/monitoring/README|delivery/processing observability]].

Amazon MQ manages ActiveMQ or RabbitMQ brokers for applications that need existing broker protocols and compatibility. It is not a drop-in replacement for every self-managed plugin or a reason to use a broker for all new workloads.

## Engine and availability choices

Choose the engine before choosing protocols, deployment topology and client recovery. ActiveMQ supports its documented wire protocols and JMS clients. RabbitMQ has its own AMQP and plugin/version matrix; do not infer compatibility from the upstream engine alone.

RabbitMQ supports dynamic Shovel, with destination-network restrictions, not static Shovel configuration. Current RabbitMQ 4-and-later support includes the JMS Topic Exchange plugin; older universal no-JMS claims are misleading. Pin a supported engine version and verify the owning matrix before migration.

A single broker is appropriate for a cheap disposable experiment, not an HA promise. Active/standby and RabbitMQ cluster topologies have different failover behavior. Use private VPC endpoints, scoped security groups, TLS and secret-managed credentials. Managed maintenance does not eliminate application reconnect/retry responsibility.

## Reversible broker lab

This is a console/client lab, not a mixed Python-and-shell deployment fragment. Broker resources incur charges while provisioned.

1. In a sandbox, select RabbitMQ, a currently supported version and a single-instance deployment. Keep public accessibility disabled. Choose the VPC/subnet/security group and create a dedicated test user; store the password securely, not in shell history or the note.
2. From a client in that VPC, allow only the broker's documented TLS port and use the owning connection tutorial/client example. Create a durable test queue, publish a persistent message with a unique business ID and consume with explicit acknowledgement.
3. Disconnect the consumer before acknowledgement. Reconnect and observe redelivery; verify an idempotent handler does not repeat the side effect.
4. In a separately budgeted HA experiment, use the appropriate HA topology and perform a controlled reboot/maintenance test. Record connection recovery, message continuity and latency rather than claiming instantaneous failover.
5. Delete the broker, disposable client/network rules and any lab-only secrets after collecting evidence. Confirm deletion reaches its terminal state; stopping consumption does not stop broker charges.

## Troubleshooting and pricing

Check DNS/routing/security groups/TLS before changing authentication. Inspect broker health, queue depth, unacknowledged messages and client reconnect metrics. Poison messages need bounded retry/dead-letter design appropriate to the engine.

Budget broker instance-hours, storage, transfer and topology-dependent replica resources. SQS/SNS/EventBridge can reduce broker operations for cloud-native workloads, but protocol conversion and semantics need deliberate design.

## Engine and deployment comparison

| Choice               | ActiveMQ                                              | RabbitMQ                                                             |
| -------------------- | ----------------------------------------------------- | -------------------------------------------------------------------- |
| Compatibility focus  | Existing JMS/OpenWire and documented protocol clients | AMQP/routing model and version-scoped plugins                        |
| HA design            | Supported active/standby broker topology              | Supported multi-AZ cluster/queue replication                         |
| Client recovery      | Use documented failover endpoints and client options  | Connection/channel recovery, acknowledgements and publisher confirms |
| Configuration        | Supported broker XML/configuration revisions          | Supported configuration/plugin parameters; not arbitrary node files  |
| Operational evidence | Engine-specific broker/queue metrics                  | Engine-specific broker/node/queue metrics                            |

JMS is an API abstraction, not a wire protocol by itself. A managed broker is not a guaranteed drop-in migration: compare destinations, plugins, authentication, transactions, expiry, queue types and client reconnect semantics.

```text
application → TLS endpoint → broker/queue → consumer
                  ↓                         ↓
           publisher confirmation    acknowledge after safe effect
                  └──── failure/reconnect/redelivery ────┘
```

## Broker creation and configuration walkthrough

Discover supported engine versions and instance options before selecting a broker. These are read-only:

```bash
aws mq describe-broker-engine-types
aws mq describe-broker-instance-options
aws mq list-brokers
aws mq describe-broker --broker-id BROKER_ID
```

CreateBroker uses HostInstanceType, DeploymentMode, EngineType/EngineVersion, SubnetIds, SecurityGroups, Users and its documented encryption/options structure. The CLI flag is --users, not --user, and describe/reboot require broker-id, not broker-name. Generate the request shape offline with `aws mq create-broker --generate-cli-skeleton input`, select the supported topology in the console and keep credentials in a protected input/workflow rather than command history.

Configuration revisions are explicitly associated with the broker; upload only supported engine settings. Do not upload arbitrary host vm_args or assume node certificate file paths are configurable on the managed host.

## RabbitMQ TLS publisher and manual acknowledgement

This complete Python example needs a current compatible pika installation, an authorized client network and private credential injection. It publishes only a synthetic fixture and acknowledges after validating the received bytes; it is not a production idempotency implementation.

```python
import os
import ssl
import pika

host = os.environ["MQ_LAB_HOST"]
context = ssl.create_default_context()
credentials = pika.PlainCredentials(
    os.environ["MQ_LAB_USER"], os.environ["MQ_LAB_PASSWORD"]
)
parameters = pika.ConnectionParameters(
    host=host,
    port=5671,
    virtual_host="/",
    credentials=credentials,
    ssl_options=pika.SSLOptions(context, host),
    heartbeat=60,
    blocked_connection_timeout=30,
)
connection = pika.BlockingConnection(parameters)
try:
    channel = connection.channel()
    channel.queue_declare(queue="wiki-lab", durable=True)
    channel.confirm_delivery()
    channel.basic_publish(
        exchange="",
        routing_key="wiki-lab",
        body=b"synthetic-fixture-1",
        properties=pika.BasicProperties(delivery_mode=2),
        mandatory=True,
    )
    method, properties, body = channel.basic_get(queue="wiki-lab", auto_ack=False)
    if method is None:
        raise RuntimeError("fixture not available; inspect delivery")
    if body != b"synthetic-fixture-1":
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
        raise RuntimeError("unexpected fixture; not acknowledged")
    channel.basic_ack(delivery_tag=method.delivery_tag)
finally:
    connection.close()
```

Do not disable TLS verification to fix a hostname/chain failure. Use the returned broker endpoint and current trusted CA store. Persistent messages/durable queues, publisher confirmation and acknowledgement address different failure points; none alone proves business exactly-once processing.

For an ActiveMQ JMS example, use the owning maintained client tutorial with required imports, secure credential retrieval and try/finally resource closure. Select transacted/manual acknowledgement behavior deliberately; AUTO_ACKNOWLEDGE is not a universal transactional-processing guarantee.

## Monitoring and fault isolation

First verify broker state and maintenance events, then DNS/routes/SGs/TLS, user/vhost permissions and queue bindings. Inspect published-versus-acknowledged rate, queue backlog, unacknowledged messages, memory/disk pressure and reconnect/error rate. Metric names differ by engine/version; do not copy one mixed metric table across both.

Reboot only a disposable broker using `aws mq reboot-broker --broker-id BROKER_ID` and record client recovery/redelivery. Reboot is not a read-only diagnostic. Preserve messages/failure evidence, delete lab queue/user, then delete the dedicated broker and verify terminal deletion. Remove client secrets and dedicated network rules separately.

References: [CreateBroker](https://docs.aws.amazon.com/cli/latest/reference/mq/create-broker.html), [RabbitMQ connection](https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/amazon-mq-rabbitmq-getting-started.html), [broker monitoring](https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/security-logging-monitoring.html), [Pika TLS examples](https://pika.readthedocs.io/en/stable/examples/tls_server_authentication.html).

## References

- [Amazon MQ concepts](https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/welcome.html)
- [RabbitMQ plugins and restrictions](https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/rabbitmq-basic-elements-plugins.html)
- [RabbitMQ connection tutorial](https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/amazon-mq-rabbitmq-getting-started.html)
- [Pricing](https://aws.amazon.com/amazon-mq/pricing/)
