---
title: Amazon EMR
description: Amazon EMR — managed Hadoop/Spark clusters, instance types, bootstrap actions, step execution, instance fleets, and auto-scaling
tags:
  - aws
  - analytics
  - emr
---

# Amazon EMR

EMR is AWS's managed Hadoop and Spark platform. You launch a cluster, EMR installs and configures the distributed processing framework (Hadoop, Spark, Hive, Presto, etc.), and you run big data jobs against it. EMR handles provisioning, configuration, and cluster management.

## Cluster Architecture

### Core Components

```
EMR Cluster (1 master node + N core/task nodes)
  ├── Master Node: YARN ResourceManager, HDFS NameNode, Spark Driver
  ├── Core Nodes: HDFS DataNode + YARN NodeManager (data storage + compute)
  └── Task Nodes: YARN NodeManager only (compute only, no HDFS storage)
```

**Instance types:**
- **Master node:** Coordinates cluster operations. Typically m5.xlarge or larger depending on workload.
- **Core nodes:** Store data in HDFS and run YARN containers. These are the primary compute workhorses.
- **Task nodes:** Pure compute, no HDFS. Added for burst capacity during job runs, removed after completion.

### Instance Fleets vs Instance Groups

**Instance Groups (older):** All nodes in a group are the same instance type. You manually set the count.

**Instance Fleets (newer):** Define a pool of instance types and sizes, EMR picks based on availability and price. Supports Spot and On-Demand mixing.

```json
{
  "InstanceFleetType": "MASTER",
  "TargetSpotCapacity": 1,
  "InstanceTypeConfigs": [
    {"InstanceType": "m5.xlarge", "WeightedCapacity": 1}
  ],
  "LaunchSpecifications": {
    "SpotSpecification": {"TimeoutDurationMinutes": 10, "AllocationStrategy": "lowest-price"}
  }
}
```

## Applications

EMR installs a set of applications based on the release version:

| Application | Purpose |
|-------------|---------|
| Hadoop | Distributed processing framework |
| Spark | In-memory distributed processing |
| Hive | SQL-like query (HiveQL) |
| Hue | Web UI for cluster management |
| Presto | Interactive SQL queries |
| Zeppelin | Notebooks for Spark/SQL |
| Ganglia | Cluster monitoring |
| Zeppelin | Notebook interface |

**EMR 7.x (latest):** Apache Spark 3.5, Hive 3.1, Presto 0.280+

## Launching a Cluster

### Console

```bash
aws emr create-cluster \
  --name "analytics-cluster" \
  --release-label emr-7.2.0 \
  --applications Name=Spark Name=Hive \
  --ec2-attributes KeyName=my-key,SubnetId=subnet-12345678 \
  --instance-fleets \
    InstanceFleetType=MASTER,TargetSpotCapacity=1,InstanceTypeConfigs=[{InstanceType=m5.xlarge}],LaunchSpecifications=[{InstanceType=ON_DEMAND}] \
    InstanceFleetType=CORE,TargetSpotCapacity=2,InstanceTypeConfigs=[{InstanceType=m5.xlarge,Wer=1},{InstanceType=m5.2xlarge,Wer=2}],LaunchSpecifications=[{InstanceType=SPOT,AllocationStrategy=lowest-price}] \
  --bootstrap-actions Path=s3://my-bucket/bootstrap.sh \
  --steps '[{"Name":"Step 1","ActionOnFailure":"CONTINUE","HadoopJarStep":{"Jar":"command-runner.jar","Args":["spark-submit","--deploy-mode","cluster","s3://my-bucket/job.py"]}}]' \
  --auto-termination-policy IdleTimeout=60
```

### Key Parameters

- `--auto-termination-policy IdleTimeout=60`: Cluster terminates after 60 minutes of inactivity (saves cost)
- `--applications`: Which applications to install
- `--bootstrap-actions`: Script that runs on all nodes at startup
- `--steps`: Jobs to run immediately after cluster creation

## Step Execution

Steps are the unit of work on EMR. A step can be a Spark job, Hive script, or custom JAR.

### Submit a Spark Job

```bash
aws emr add-steps \
  --cluster-id j-1234567890 \
  --steps Type=SPARK,Name="analytics-job",ActionOnFailure=CONTINUE,Args=[spark-submit,--deploy-mode,cluster,--class,com.example.App,s3://my-bucket/app.jar,s3://my-bucket/input/,s3://my-bucket/output/]
```

**ActionOnFailure options:**
- `CONTINUE`: Continue to next step even if this one fails
- `TERMINATE_CLUSTER`: Stop the cluster on failure
- `CANCEL_AND_WAIT`: Cancel remaining steps but keep cluster running

### Cluster States

```
STARTING → BOOTSTRAPPING → RUNNING → WAITING → TERMINATING → TERMINATED
                ↓
           Bootstrap actions run here
```

- `WAITING`: Cluster is idle, no steps running, auto-termination policy not triggered
- `TERMINATED`: Cluster shut down, either manually or via auto-termination

## Bootstrap Actions

Bootstrap actions run as root on all nodes before Hadoop is initialized. Use them to install additional software or configure cluster settings.

```bash
#!/bin/bash
# bootstrap.sh
yum install -y python3-pip
pip3 install pandas boto3
echo "spark.executor.memory=4g" >> /etc/spark/conf/spark-defaults.conf
```

## Auto Scaling

EMR auto scaling adjusts the number of core and task nodes based on YARN metrics.

```json
{
  "AutoScalingRole": "EMR_AutoScaling_DefaultRole",
  "Rules": [
    {
      "Name": "ScaleUp",
      "Trigger": {
        "CloudWatchAlarmDefinition": {
          "ComparisonOperator": "GREATER_THAN",
          "MetricName": "YARNMemoryAvailablePercentage",
          "Period": 300,
          "Threshold": 15,
          "Statistic": "AVERAGE"
        }
      },
      "Action": {
        "SimpleScalingPolicyConfiguration": {
          "ScalingAdjustment": 1,
          "AdjustmentType": "CHANGE_IN_CAPACITY"
        }
      }
    },
    {
      "Name": "ScaleDown",
      "Trigger": {
        "CloudWatchAlarmDefinition": {
          "ComparisonOperator": "LESS_THAN",
          "MetricName": "YARNMemoryAvailablePercentage",
          "Period": 600,
          "Threshold": 75,
          "Statistic": "AVERAGE"
        }
      },
      "Action": {
        "SimpleScalingPolicyConfiguration": {
          "ScalingAdjustment": -1,
          "AdjustmentType": "CHANGE_IN_CAPACITY"
        }
      }
    }
  ]
}
```

**Core nodes vs task nodes in scaling:**
- Core nodes can be added AND removed by scaling
- Task nodes are pure scaling nodes — added during scale-up, removed during scale-down, never hold HDFS data

## Instance Types for EMR

| Workload | Instance Type | Notes |
|----------|---------------|-------|
| General Spark | r5, r6 (memory optimized) | Large executors need memory |
| HDFS storage | d3 (dense storage) | High local disk for HDFS |
| Presto interactive | c5, c6 (compute optimized) | Fast CPU for ad-hoc queries |
| Kafka | i3 (high I/O) | NVMe for high-throughput streaming |
| Machine Learning | p4, g5 (GPU) | Spark ML training |

## EMR Studio

EMR Studio provides managed Jupyter notebooks connected to EMR clusters. You create a workspace, associate it with an EMR cluster, and get a Jupyter environment with Spark pre-configured.

**Use case:** Data scientists run exploratory analysis against live Spark clusters without managing cluster infrastructure.

## Security

### IAM Roles

EMR needs an IAM role (`EMR_DefaultRole`) for cluster operations. Additional roles for:
- `EMR_EC2_DefaultInstanceProfile`: EC2 instances in the cluster
- `EMR_AutoScaling_DefaultRole`: Auto scaling operations

### Kerberos Authentication

For enterprise security, configure Kerberos:
- Create a Kerberos realm (AWS Directory Service or your own)
- Enable Kerberos on cluster creation
- All users authenticate before running jobs

### Encryption

- **At rest:** HDFS encryption (AES-256), KMS integration
- **In transit:** TLS between cluster nodes
- **Local disk:** LUKS encryption on core/task nodes

## Cost Optimization

**Use Spot for task nodes:** Task nodes are ephemeral — they're added for job bursts and removed when not needed. Spot can cut task node cost by 60-90%.

**Core nodes as Spot (with caution):** Core nodes hold HDFS data. If a Spot core node is terminated, HDFS replication rebuilds. Use `core_instance_fleet` with a mix of On-Demand (for stability) and Spot (for cost).

**Auto-termination:** Set `IdleTimeout` to terminate clusters that sit idle. Most analytics workloads run nightly or on-demand — clusters left running waste money.

**EMR Serverless:** For Spark workloads that are bursty and stateless, EMR Serverless runs Spark without managing clusters. You submit jobs, AWS provisions workers, job completes, workers are released. Pay per second of vCPU time.

- Long-running vs ephemeral: If you're running jobs every few hours, keep a long-running cluster with auto-termination. If you're running jobs once a day or less, ephemeral clusters (launch, run, terminate) are more cost-effective.

## References

- **Homepage:** https://aws.amazon.com/emr/
- **Documentation:** https://docs.aws.amazon.com/emr/latest/ManagementGuide/
- **Pricing:** https://aws.amazon.com/emr/pricing/

## Pricing Examples

**Scenario 1:** A nightly Spark ETL job: 10 r5.xlarge nodes (4 hours/day, 20 days/month). On-Demand: 10 × $0.252/hr × 4hr × 20 = $201.60/month. With Spot (60% discount): 10 × $0.101/hr × 4hr × 20 = $80.80/month. Plus EBS (100GB per node): 10 × 100GB × $0.10 = $100/month. Total: ~$180/month with Spot.

**Scenario 2:** An EMR Serverless job running Spark: 100 vCPU-hours per day × 20 days = 2,000 vCPU-hours/month. At $0.15/vCPU-hour (us-east-1): $300/month. vs a persistent EMR cluster (5 m6g.xlarge, 24/7): 5 × $0.408 × 720hr = $1,468/month. EMR Serverless is 5x cheaper for bursty workloads.

## Nuggets & Gotchas

- **EMR cluster cost is dominated by EC2 instances:** The EMR markup (~$0.12/hr per cluster) is negligible compared to EC2 costs. Use Spot instances aggressively for task nodes (60-90% savings) and for core nodes with caution (data recovery cost).
- **Instance fleets vs instance groups:** Instance fleets let you specify multiple instance types and Spot/bid strategies. Instance groups fix you to one type. Fleets are more resilient to Spot interruptions but more complex to configure.
- **S3 is the primary storage, not HDFS:** EMRFS (S3 connector) is the default for data storage. HDFS is local to the cluster and lost on cluster termination. Use S3 for persistent data, HDFS only for intermediate shuffle data.
- **EMR Studio (Jupyter-based) creates workspaces in S3:** Each workspace saves kernel state and notebooks to S3. If the workspace S3 bucket is deleted, notebooks are gone. Enable versioning on the workspace bucket.
- **EMR on EKS separates compute from cluster management:** If you already run EKS, EMR on EKS lets you run Spark jobs on your existing EKS clusters instead of provisioning separate EMR clusters. Useful for orgs with existing Kubernetes infrastructure.