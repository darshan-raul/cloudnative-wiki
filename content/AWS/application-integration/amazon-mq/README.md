---
title: Amazon MQ
description: Amazon MQ — managed ActiveMQ and RabbitMQ brokers. Protocol support (JMS, AMQP, MQTT, OpenWire), deployment modes, encryption, and migration from self-managed brokers.
tags:
  - aws
  - application-integration
  - amazon-mq
  - rabbitmq
  - activemq
  - messaging
---

# Amazon MQ

Amazon MQ is a managed broker service for ActiveMQ (Java, JMS) and RabbitMQ (Erlang, AMQP). If you're migrating from self-hosted RabbitMQ or ActiveMQ, MQ provides drop-in replacement hosting without re-engineering your application.

## ActiveMQ vs RabbitMQ

| Feature | ActiveMQ | RabbitMQ |
|---------|----------|----------|
| Language | Java | Erlang |
| Protocols | JMS, AMQP, MQTT, OpenWire, STOMP | AMQP, MQTT, STOMP, HTTP |
| Management | Web console, JMX | Management UI, CLI |
| Queue features | Message groups, virtual topics | Dead-letter exchanges, per-message TTL |
| Clustering | Master/slave | Quorum queues |
| Use case | Java/JMS apps | Flexible routing, microservices |

## Creating a Broker

```bash
# ActiveMQ broker
aws mq create-broker \
  --broker-name my-activemq \
  --broker-instance-class mq.t3.micro \
  --engine-type ActiveMQ \
  --engine-version 5.18.0 \
  --security-groups sg-xxxxx \
  --subnet-ids subnet-xxxxx \
  --user '{"Username": "admin", "Password": "MySecretPassword123!"}'

# RabbitMQ broker
aws mq create-broker \
  --broker-name my-rabbitmq \
  --broker-instance-class mq.t3.micro \
  --engine-type RabbitMQ \
  --engine-version 3.12.0 \
  --host-instance-type mq.t3.micro \
  --security-groups sg-xxxxx \
  --subnet-ids subnet-xxxxx subnet-yyyyy \
  --user '{"Username": "admin", "Password": "MySecretPassword123!"}'
```

## Deployment Modes

```
Single-Instance (no replication)
  └── One broker in one AZ
      └── For dev/test only

Active/Standby (multi-AZ)
  └── Master in AZ-1, Standby in AZ-2
      └── Automatic failover
      └── For production

Cluster (RabbitMQ only)
  └── Multiple broker nodes across AZs
      └── Quorum queues for HA
      └── For high throughput
```

## Connecting to Amazon MQ

### ActiveMQ (JMS)

```java
import org.apache.activemq.ActiveMQConnectionFactory;

ConnectionFactory factory = new ActiveMQConnectionFactory("ssl://b-xxxxx-1.activemq.us-east-1.amazonaws.com:61617");
Connection connection = factory.createConnection("admin", "password");
Session session = connection.createSession(false, Session.AUTO_ACKNOWLEDGE);
Queue queue = session.createQueue("my-queue");
MessageProducer producer = session.createProducer(queue);
producer.send(session.createTextMessage("Hello MQ!"));
```

### RabbitMQ (AMQP)

```python
import pika

credentials = pika.PlainCredentials('admin', 'password')
parameters = pika.ConnectionParameters(
    host='b-xxxxx.rmq.us-east-1.amazonaws.com',
    port=5671,
    virtual_host='/',
    credentials=credentials,
    ssl=True,
    ssl_options={'ca_certs': '/path/to/ca-bundle.pem'}
)

connection = pika.BlockingConnection(parameters)
channel = connection.channel()
channel.queue_declare(queue='my-queue', durable=True)
channel.basic_publish(
    exchange='',
    routing_key='my-queue',
    body='Hello MQ!'
)
connection.close()
```

### TLS Connection

```bash
# Download Amazon MQ CA bundle for TLS
curl -o /tmp/AmazonRootCA1.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

# For RabbitMQ with TLS
channel = connection.channel()
channel.queue_declare(queue='my-queue', durable=True)
```

## RabbitMQ Clustering

```bash
# Create RabbitMQ cluster (3 nodes across AZs)
aws mq create-broker \
  --broker-name my-rabbitmq-cluster \
  --engine-type RabbitMQ \
  --engine-version 3.12.0 \
  --host-instance-type mq.m5.large \
  --security-groups sg-xxxxx \
  --subnet-ids subnet-az1 subnet-az2 subnet-az3 \
  --configuration '{
    "Revision": 1,
    "ConfigurationId": "config-xxxxx"
  }' \
  --deployment-mode CLUSTER_MULTI_AZ
```

## Configuration (RabbitMQ)

```ini
# RabbitMQ config (uploaded as config file)
listeners.ssl.default = 5671
ssl_options.cacertfile = /opt/amqp/ssl/amqp-ca_bundle.pem
ssl_options.certfile   = /opt/amqp/ssl/certificate.pem
ssl_options.keyfile     = /opt/amqp/ssl/key.pem
ssl_options.verify      = verify_peer
vm_args = +WBW招生 1024
```

## Monitoring

```bash
# Get broker info
aws mq describe-broker --broker-name my-activemq

# List brokers
aws mq list-brokers

# Reboot broker
aws mq reboot-broker --broker-name my-activemq
```

### CloudWatch Metrics

| Metric | Description |
|--------|-------------|
| ActiveConsumerCount | Active consumers |
| ConnectionCount | Open connections |
| EnqueueCount | Messages enqueued |
| DequeueCount | Messages dequeued |
| MessageCount | Messages in queue |

## Encryption

```bash
# Create with customer-managed KMS key
aws mq create-broker \
  --broker-name my-encrypted-mq \
  --kms-key-id arn:aws:kms:us-east-1:123456789012:key/xxxxx \
  ...
```

## Pricing

| Instance | Cost |
|----------|------|
| mq.t3.micro | $0.065/hr |
| mq.m5.large | $0.50/hr |
| mq.m5.xlarge | $1.00/hr |
| mq.m5.2xlarge | $2.00/hr |

Plus storage at $0.25/GB/month.

## Limits

| Resource | Limit |
|----------|-------|
| Brokers per region | 25 |
| Connections per broker | 1000 (ActiveMQ), 5000 (RabbitMQ) |
| Queues per broker | 1000 |
| Message size | 64KB (ActiveMQ), 128KB (RabbitMQ) |

## References

- **Homepage:** https://aws.amazon.com/amazon-mq/
- **Documentation:** https://docs.aws.amazon.com/amazon-mq/
- **Pricing:** https://aws.amazon.com/amazon-mq/pricing/

## Nuggets & Gotchas

- **Amazon MQ is NOT serverless — you pay for the broker instance 24/7 regardless of usage:** At mq.t3.micro ($0.065/hr = $47/month), you're paying even if the broker is idle. For serverless pay-per-use messaging, use SQS or SNS.
- **Amazon MQ requires security groups that allow inbound traffic on the broker ports (61617 for ActiveMQ, 5671 for RabbitMQ SSL):** If you can't connect, check your security group inbound rules allow the correct port from your application's subnet.
- **RabbitMQ on Amazon MQ does NOT support all plugins — only pre-approved plugins are available:** If you need the shovel plugin or custom Erlang modules, they're not available. Check the supported plugins list before migrating.
- **Amazon MQ's ActiveMQ supports JMS 1.1 — if you need JMS 2.0 features (shared subscriptions), use RabbitMQ instead:** JMS 2.0 features like shared subscriptions are only available on RabbitMQ in Amazon MQ.
- **Amazon MQ broker logs go to CloudWatch Logs — you need to enable logging explicitly:** Without enabling logging, you won't see broker logs. Enable both general and audit logs when creating the broker.