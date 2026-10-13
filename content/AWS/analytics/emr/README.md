---
title: "Amazon EMR"
description: "EMR provides managed big-data runtimes including Spark, with EC2, Serverless and EKS deployment options."
tags:
  - aws/analytics
date: 2026-10-12
---

# Amazon EMR

EMR provides managed big-data runtimes including Spark, with EC2, Serverless and EKS deployment options. Select a supported release and runtime before copying configuration: console labels are not always API enum values. Prerequisites: [[AWS/analytics/README|analytics]], [[AWS/storage/s3/README|S3]], [[AWS/security/iam/README|IAM]] and networking.

## Deployment and cluster roles

On EC2, primary nodes coordinate, core nodes can host storage/workers and task nodes add compute. Instance groups and fleets are different provisioning models. Fleet type configurations use WeightedCapacity, not Wer; weight is a configured capacity unit, not necessarily physical vCPU count.

EMR Serverless scales application/job resources but still requires permissions, data paths, runtime configuration and cost controls. EMR on EKS integrates with Kubernetes prerequisites rather than behaving like an EC2 cluster without nodes. Studio access and runtime execution roles should be separated.

## Real step and bootstrap contracts

For an EC2 Spark step, use CUSTOM_JAR with command-runner.jar and spark-submit arguments.

```bash
aws emr add-steps --cluster-id j-EXAMPLE \
  --steps 'Type=CUSTOM_JAR,Name=SandboxSpark,ActionOnFailure=CANCEL_AND_WAIT,Jar=command-runner.jar,Args=[spark-submit,s3://example-unique-bucket/jobs/example.py]'
```

The cluster must exist with Spark installed, and the script must be a real tested application accessible to its role. This command alone is not an end-to-end lab and does not create the script.

Bootstrap scripts run as hadoop by default; privileged changes need deliberate sudo and idempotency. Pin dependencies and inspect logs instead of installing unbounded latest packages. Auto-termination IdleTimeout values are seconds: 3600 means sixty minutes, while 60 means one minute.

## Security, scaling and cost

Restrict client/security-group access, encrypt data/logs, scope job roles and protect sensitive S3 datasets. Kerberos and runtime identity choices require supported setup. Managed scaling/autoscaling targets need workload measurements; low available memory is not a reason to remove capacity. Spot task capacity can reduce cost only if job/checkpoint/retry behavior tolerates interruption.

EC2 EMR charges include applicable per-instance EMR uplift plus EC2, EBS and ancillary resources—not one cluster-wide \$0.12/hour. Serverless bills its compute/memory/storage dimensions. Compare equivalent job completion time, output and availability.

## Bounded job exercise

Provision a budgeted disposable deployment from the owning getting-started guide. Run a small Spark aggregation over private S3 input, compare results to a local expected count and inspect driver/executor logs. Submit one deliberately invalid input path and confirm a visible failed job, not a swallowed exception.

Record runtime, allocated capacity and charges; test least-privilege denial. Terminate EC2 clusters/delete Serverless applications or EKS-created resources as appropriate, plus disposable output/log artifacts according to policy. Verify termination rather than assuming an idle notebook stopped compute.

## EC2 cluster anatomy

```text
Primary node(s): coordination and supported HA services
  ├─ core nodes: compute + HDFS storage where configured
  └─ task nodes: additional compute, no HDFS data storage

Durable input/output: S3
Temporary distributed state: workload/runtime-dependent
```

Do not assume the Spark driver always runs on the primary: client versus cluster deploy mode changes placement. Scaling away core capacity needs HDFS/application safeguards; task nodes are a more natural interruption-tolerant compute pool.

| Provisioning model | What you specify                             | Operational decision                                                               |
| ------------------ | -------------------------------------------- | ---------------------------------------------------------------------------------- |
| Instance groups    | Type/count for each supported group          | Predictable homogeneous groups; supported scaling policies.                        |
| Instance fleets    | Multiple types, weights and capacity targets | Availability/purchasing flexibility; capacity units must be interpreted correctly. |
| Serverless         | Application/runtime/job resource settings    | No EC2 cluster management; jobs still need permissions and observability.          |
| EMR on EKS         | Existing supported Kubernetes environment    | Integration with cluster identity, scheduling and lifecycle.                       |

## Applications, bootstrap and job lifecycle

Select applications from the chosen release's manifest: Spark, Hadoop/Hive and other components vary by release. An old “latest EMR 7.x” version table does not establish current runtime support.

1. Select supported release/applications and an isolated subnet.
2. Create scoped service/instance/runtime roles as required by the deployment.
3. Configure encryption, log destination and security-group paths before launch.
4. Use an idempotent bootstrap action for node-level dependencies; use explicit privilege elevation only for required changes.
5. Submit a bounded step/job, inspect failure action and capture its ID.
6. Inspect driver/executor logs and output correctness before declaring success.
7. Verify completion/termination and retain only approved logs/data.

Spot interruption is a purchasing risk, not an application retry guarantee. Make processing restartable, store durable outputs in S3 and verify checkpoint/retry behavior. Managed scaling and auto-termination are separate controls: scaling manages resources, while auto-termination determines when eligible idle compute is removed.

## Monitoring and tuning workflow

Inspect skewed Spark stages, shuffle spill, executor loss, HDFS pressure where used and S3 access errors. Compare task duration distribution before adding capacity. High CPU with short queues and high latency with idle CPU imply different bottlenecks.

Budget includes running instances/application compute, memory/storage, EBS, logs and output. Guard against long-lived notebooks, failed steps that leave clusters running and output overwrite of shared datasets. Pin input/output prefixes so a retry cannot erase unrelated data.

## References

- [Instance-fleet type contract](https://docs.aws.amazon.com/emr/latest/APIReference/API_InstanceTypeConfig.html)
- [command-runner examples](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-commandrunner.html)
- [Auto-termination](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-auto-termination-policy.html)
- [Bootstrap actions](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-plan-bootstrap.html)
- [EMR pricing](https://aws.amazon.com/emr/pricing/)

## Complete EC2 Spark step lab

Select **emr-7.12.0** (Spark 3.5.6), which has published lifecycle dates; verify availability in your chosen Region. Use a dedicated authorized subnet/security configuration with approved S3/service access, EMR service role and EC2 instance profile. The roles need the selected S3 script/input read, output/log write and optional KMS permissions. Service-role-v2 networking resources may require its documented tags. The operator needs EMR operations and scoped PassRole. No SSH/public inbound rule is needed.

Set EMR_LAB_BUCKET, EMR_LAB_SUBNET, EMR_LAB_SERVICE_ROLE and EMR_LAB_INSTANCE_PROFILE. Confirm that the selected m5.xlarge capacity/quotas/architecture is available. This lab creates three paid instances; obtain a budget and terminate the dedicated cluster after both tests.

Save ledger.csv:

```csv
id,department,amount
f1,finance,10.00
h1,hr,99.00
f2,finance,20.00
```

Save aggregate.py:

```python
import sys
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import DecimalType, StringType, StructField, StructType

if len(sys.argv) != 3:
    raise SystemExit("Usage: aggregate.py input_uri output_uri")
spark = SparkSession.builder.appName("DG07Ledger").getOrCreate()
schema = StructType([
    StructField("id", StringType(), False),
    StructField("department", StringType(), False),
    StructField("amount", DecimalType(12, 2), False),
])
rows = spark.read.option("header", True).schema(schema).csv(sys.argv[1])
if rows.filter(F.col("amount").isNull() | F.col("department").isNull()).count():
    raise ValueError("Invalid fixture")
result = rows.groupBy("department").agg(
    F.sum("amount").alias("total"), F.count("*").alias("transactions")
)
result.orderBy("department").coalesce(1).write.mode("overwrite").json(sys.argv[2])
spark.stop()
```

The target is an isolated lab prefix. Overwrite makes replay of the same full input duplicate-safe here; it is not permission to overwrite a shared data lake.

The complete Boto3 driver uploads both files, creates the cluster, waits, submits the real Spark application, verifies output and deliberately submits a missing path. Save it as emr_lab.py:

```python
import json
import os
import time
from decimal import Decimal
import boto3

bucket = os.environ["EMR_LAB_BUCKET"]
emr, s3 = boto3.client("emr"), boto3.client("s3")
s3.upload_file("aggregate.py", bucket, "dg07/scripts/aggregate.py")
s3.upload_file("ledger.csv", bucket, "dg07/input/ledger.csv")
cluster = emr.run_job_flow(
    Name="dg07-ledger-lab", ReleaseLabel="emr-7.12.0",
    Applications=[{"Name": "Spark"}],
    LogUri=f"s3://{bucket}/dg07/logs/",
    ServiceRole=os.environ["EMR_LAB_SERVICE_ROLE"],
    JobFlowRole=os.environ["EMR_LAB_INSTANCE_PROFILE"],
    Instances={
        "Ec2SubnetId": os.environ["EMR_LAB_SUBNET"],
        "KeepJobFlowAliveWhenNoSteps": True,
        "InstanceGroups": [
            {"Name": "Primary", "InstanceRole": "MASTER",
             "InstanceType": "m5.xlarge", "InstanceCount": 1, "Market": "ON_DEMAND"},
            {"Name": "Core", "InstanceRole": "CORE",
             "InstanceType": "m5.xlarge", "InstanceCount": 2, "Market": "ON_DEMAND"},
        ],
    },
    VisibleToAllUsers=True,
)["JobFlowId"]
print("Dedicated ClusterId:", cluster)
emr.put_auto_termination_policy(
    ClusterId=cluster, AutoTerminationPolicy={"IdleTimeout": 900}
)
deadline = time.monotonic() + 1500
while time.monotonic() < deadline:
    status = emr.describe_cluster(ClusterId=cluster)["Cluster"]["Status"]
    if status["State"] in {"WAITING", "RUNNING"}:
        break
    if status["State"] in {"TERMINATED", "TERMINATED_WITH_ERRORS"}:
        raise RuntimeError(status)
    time.sleep(10)
else:
    emr.terminate_job_flows(JobFlowIds=[cluster])
    raise TimeoutError("Cluster deadline; verify termination")

def submit(input_uri, output_uri):
    step = emr.add_job_flow_steps(JobFlowId=cluster, Steps=[{
        "Name": "DG07Spark",
        "ActionOnFailure": "CANCEL_AND_WAIT",
        "HadoopJarStep": {
            "Jar": "command-runner.jar",
            "Args": ["spark-submit", "--deploy-mode", "cluster",
                     f"s3://{bucket}/dg07/scripts/aggregate.py", input_uri, output_uri],
        },
    }])["StepIds"][0]
    print("StepId:", step)
    end = time.monotonic() + 600
    while time.monotonic() < end:
        result = emr.describe_step(ClusterId=cluster, StepId=step)["Step"]["Status"]
        if result["State"] in {"COMPLETED", "FAILED", "CANCELLED", "INTERRUPTED"}:
            return result
        time.sleep(5)
    emr.cancel_steps(ClusterId=cluster, StepIds=[step])
    raise TimeoutError("Step cancellation requested; inspect final status")

good = submit(f"s3://{bucket}/dg07/input/", f"s3://{bucket}/dg07/output/")
assert good["State"] == "COMPLETED", good
actual = {}
for page in s3.get_paginator("list_objects_v2").paginate(
    Bucket=bucket, Prefix="dg07/output/"
):
    for obj in page.get("Contents", []):
        if "/part-" in obj["Key"] and obj["Key"].endswith(".json"):
            body = s3.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read()
            for line in body.decode().splitlines():
                row = json.loads(line, parse_float=Decimal)
                actual[row["department"]] = (Decimal(str(row["total"])), row["transactions"])
assert actual == {"finance": (Decimal("30.00"), 2), "hr": (Decimal("99.00"), 1)}, actual
bad = submit(f"s3://{bucket}/dg07/does-not-exist/", f"s3://{bucket}/dg07/bad-output/")
assert bad["State"] == "FAILED", bad
print("Expected failure:", bad)
emr.terminate_job_flows(JobFlowIds=[cluster])
```

Expected: first step COMPLETED with finance 30.00/2 and HR 99.00/1; missing-input step FAILED with an inspectable failure reason/log, not an empty successful result. These assertions must pass in your authorized environment before calling the cloud lab successful.

Failure cleanup: the printed cluster ID is the exact target. If an assertion/driver error occurs, request termination of that dedicated cluster, poll DescribeCluster to TERMINATED/TERMINATED_WITH_ERRORS within a deadline, and escalate if it remains running. Auto-termination is a guard, not teardown evidence. Review/delete only dg07 script/input/output/log objects and dedicated network resources; preserve shared roles/subnet/bucket and approved diagnostic logs.

Sources: [7.12.0 lifecycle/runtime](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-7120-release.html), [getting started](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-gs.html), [RunJobFlow](https://docs.aws.amazon.com/boto3/latest/reference/services/emr/client/run_job_flow.html), [AddJobFlowSteps](https://docs.aws.amazon.com/boto3/latest/reference/services/emr/client/add_job_flow_steps.html).
