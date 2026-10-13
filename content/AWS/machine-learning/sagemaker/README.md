---
title: "Amazon SageMaker AI"
description: "SageMaker AI supports data preparation, training, experiment/model management and inference operations."
tags:
  - aws/machine-learning
date: 2026-10-12
---

# Amazon SageMaker AI

SageMaker AI supports data preparation, training, experiment/model management and inference operations. Prerequisites: [[AWS/machine-learning/README|ML fundamentals]], [[AWS/security/iam/README|IAM]], [[AWS/storage/s3/README|S3]] and networking.

## Workflow and contracts

Separate processing/features, training, held-out evaluation, registry approval and endpoint/batch inference. Pin the SageMaker SDK major and use a maintained end-to-end example; mixing v2 imports into v3 or referring to undefined pipeline steps is not a valid runnable tutorial.

Studio CreateDomain requires AuthMode, networking and case-sensitive DefaultUserSettings.ExecutionRole. Execution roles, operator identities and notebook/application lifecycle are different. Deleting a browser tab does not stop compute.

Feature Store control plane is sagemaker, while records use sagemaker-featurestore-runtime. CreateFeatureGroup requires RecordIdentifierFeatureName and EventTimeFeatureName matching FeatureDefinitions; offline storage additionally requires the role/configuration.

```python
import boto3

control = boto3.client("sagemaker")
runtime = boto3.client("sagemaker-featurestore-runtime")
print(control.list_feature_groups().get("FeatureGroupSummaries", []))
```

This read-only discovery example requires configured credentials/Region/permissions. It does not create a correctly governed feature group or populate records.

## Hosting, scaling and monitoring

Choose real-time, serverless, asynchronous or batch inference from latency, payload and supported-model needs. Supported hosting replaces unhealthy instances after failed health checks; inference-component cases have separately documented behavior. Do not assert universal “no auto-healing” or assume replacement eliminates application errors.

Autoscaling uses documented metrics such as predefined InvocationsPerInstance or a correctly defined custom CPU metric, with min/max bounds and load testing—not a fictional SageMakerVariantCPUUtilization name. Model Monitor needs data capture, a baseline and scheduled monitoring processing jobs. A lone invalid ModelMonitor call is not drift detection.

Edge Manager became inaccessible April 26, 2024; use supported edge alternatives such as Greengrass V2/ONNX where suitable. Ground Truth Plus retired June 30, 2026; this does not retire all SageMaker labeling.

## Reproducible deployment exercise

Use a current AWS-maintained example pinned to its SDK/runtime, non-sensitive labelled data and a budget. Train a small model, record artifact/input versions and held-out metrics, then deploy only if its quality gate passes. Invoke known cases and a denied identity; observe endpoint failure/latency.

Enable supported capture and establish a baseline before monitoring. Load-test scale bounds and compare measured cost/latency. Remove endpoints/configurations/models/apps/monitoring schedules and reviewed S3 artifacts created for the test; endpoints and sessions can cost money while idle.

## End-to-end components and artifact flow

```text
Studio/notebook exploration
  → processing + feature preparation
  → training / hyperparameter tuning
  → held-out evaluation
  → registry approval
  → real-time / async / batch inference
  → captured data + monitoring + controlled replacement
```

| Component             | Input/output                                   | Operational responsibility                          |
| --------------------- | ---------------------------------------------- | --------------------------------------------------- |
| Processing            | Source data → prepared datasets/features       | Runtime/dependencies, schema and reproducibility    |
| Training              | Dataset + algorithm/container → model artifact | Resource requirements, metrics and failure handling |
| Hyperparameter tuning | Search space/objective → candidate jobs        | Valid metric extraction, budget and selection bias  |
| Registry              | Versioned package + evidence → approval state  | Review/ownership and deployable compatibility       |
| Hosting               | Model/container → inference endpoint           | Latency, limits, rollout and availability           |
| Pipelines             | Defined dependent steps → execution state      | Actual step objects, parameters and retry semantics |

Distributed GPU training needs the supported framework/distribution configuration and real entry-point script. XLA and torchrun settings depend on the selected accelerator/runtime rather than forming a universal GPU recipe. Use a maintained release-specific example; account for per-host GPU count and data/communication bottlenecks.

## Training and deployment walkthrough

1. Pin SDK major, framework/runtime/image and compatible dependencies.
2. Implement/test the actual training entry point locally with small synthetic data.
3. Publish authorized input/artifacts and define execution/network/KMS permissions.
4. Submit a supported training job, record its ID and inspect metrics/terminal failure.
5. Evaluate a held-out dataset and approve only artifacts meeting the quality gate.
6. Create supported model/endpoint configuration or batch job with its real payload contract.
7. Verify known predictions, authorization denial and error/timeout behavior.
8. Load-test scaling bounds, canary/rollback and cleanup each created resource.

A tuning regex must match the actual training log, and validation metric optimization can overfit a selection dataset. Track max jobs/parallelism and dollar-equivalent budget before a broad search. A successful notebook is not a completed deployable model pipeline.

## Feature Store creation schema

This illustrative SDK call creates an offline/online feature group with required identifier/event-time features. It needs a real role, private S3 location, KMS/configuration where required and permissions; creation is asynchronous/billable.

```python
import boto3

control = boto3.client("sagemaker")
control.create_feature_group(
    FeatureGroupName="sandbox-user-features",
    RecordIdentifierFeatureName="user_id",
    EventTimeFeatureName="event_time",
    FeatureDefinitions=[
        {"FeatureName": "user_id", "FeatureType": "String"},
        {"FeatureName": "event_time", "FeatureType": "Fractional"},
        {"FeatureName": "score", "FeatureType": "Fractional"},
    ],
    OnlineStoreConfig={"EnableOnlineStore": True},
    OfflineStoreConfig={
        "S3StorageConfig": {
            "S3Uri": "s3://example-unique-bucket/sandbox/features/"
        }
    },
    RoleArn="arn:aws:iam::123456789012:role/SandboxFeatureStoreRole",
)
```

Use sagemaker-featurestore-runtime for records. Record identifier/time schema affects updates and point-in-time feature correctness; prevent training leakage from future values. Verify storage creation/status and actual record retrieval, not just API acceptance.

## Hosting and monitoring operating detail

Real-time, asynchronous, serverless and batch inference have different scaling/payload/cost requirements. Supported unhealthy-instance replacement is not an assurance that a bad model or application failure is repaired. Model Monitor needs capture, baseline and schedule plus permissions/retention; monitor jobs themselves consume resources.

Track invocation/error/latency, capacity utilization, capture success, baseline deviations and downstream business outcomes. Define rollback to a known model/configuration and ensure retained artifacts/roles permit recovery. Delete endpoints, configurations, models, apps and monitoring schedules in dependency order; S3 artifacts and offline feature data may remain after service-resource deletion.

## References

- [Feature-group required schema](https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateFeatureGroup.html)
- [Feature Store runtime](https://docs.aws.amazon.com/boto3/latest/reference/services/sagemaker-featurestore-runtime.html)
- [CreateDomain](https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateDomain.html)
- [Model Monitor data capture](https://docs.aws.amazon.com/sagemaker/latest/dg/model-monitor-data-capture.html)
- [Scaling and load tests](https://docs.aws.amazon.com/sagemaker/latest/dg/endpoint-scaling-loadtest.html)
- [Maintained SageMaker examples](https://github.com/aws/amazon-sagemaker-examples)
- [Edge Manager retirement](https://docs.aws.amazon.com/sagemaker/latest/dg/edge-eol.html)
- [SageMaker pricing](https://aws.amazon.com/sagemaker/pricing/)

## Across the wiki

- [[AI/aws/bedrock|Amazon Bedrock Architecture & Implementation]] — generative AI platforms (AI)
- [[AI/rag|Retrieval-Augmented Generation (RAG) Architecture]] — generative AI platforms (AI)
- [[AI/aws/sagemaker/README|Sagemaker]] — generative AI platforms (AI)
- [[AI/aws/services|Services]] — generative AI platforms (AI)

## Complete custom-training and endpoint lab

This is a tiny **custom nearest-centroid classifier**, not a costly distributed-GPU example. Use the [AWS-maintained Scikit-learn script-mode workflow](https://docs.aws.amazon.com/sagemaker/latest/dg/sklearn.html), adapted below with a complete entry point. The driver uses **Boto3 1.43.75**, not mixed v2/v3 SageMaker SDK objects. Select patch-supported Scikit-learn **1.9-0** from the current [support policy](https://docs.aws.amazon.com/sagemaker/latest/dg/pre-built-containers-support-policy.html), obtain the training/inference-capable image URI for your Region from the [owning registry guide](https://docs.aws.amazon.com/sagemaker/latest/dg/pre-built-docker-containers-scikit-learn-spark.html), and record its immutable digest. Do not substitute the older 1.2-1 tutorial image: patch support ended.

Set SM_LAB_BUCKET, SM_LAB_ROLE and SM_LAB_IMAGE_URI to the approved private bucket, execution-role ARN and **verified regional image URI/digest**. The role trusts sagemaker.amazonaws.com and needs S3 input/code/output read/write, required image pull/logging and selected KMS access. The operator needs training/model/endpoint operations plus scoped PassRole. Check ml.m5.large hosting/training support, quotas, VPC/private endpoint policy where required, and a budget. Image selection is an explicit preflight, not a guessed account/Region hostname.

Save train.csv:

```csv
label,x
0,-3
0,-2
0,-1
1,1
1,2
1,3
```

Save the complete train.py, used for both training and serving. It depends only on Python's standard library; the selected framework container supplies the SageMaker script/hosting lifecycle.

```python
import csv
import json
import math
import os
from pathlib import Path

def fit(rows):
    groups = {}
    for row in rows:
        groups.setdefault(str(int(row["label"])), []).append(float(row["x"]))
    if set(groups) != {"0", "1"}:
        raise ValueError("Fixture requires both classes")
    return {"centroids": {
        label: sum(values) / len(values) for label, values in groups.items()
    }}

def model_fn(model_dir):
    with open(Path(model_dir) / "model.json", encoding="utf-8") as source:
        return json.load(source)

def input_fn(body, content_type):
    if content_type != "application/json":
        raise ValueError("Use application/json")
    value = json.loads(body)
    if not isinstance(value, list) or not value:
        raise ValueError("Expected a nonempty list of one-feature rows")
    for row in value:
        if not isinstance(row, list) or len(row) != 1 or not math.isfinite(float(row[0])):
            raise ValueError("Expected [[numeric_x], ...]")
    return value

def predict_fn(rows, model):
    return [
        int(min(model["centroids"], key=lambda label:
                (abs(float(row[0]) - model["centroids"][label]), label)))
        for row in rows
    ]

def output_fn(prediction, accept):
    if accept != "application/json":
        raise ValueError("Use Accept application/json")
    return json.dumps({"predictions": prediction})

if __name__ == "__main__":
    files = sorted(Path(os.environ["SM_CHANNEL_TRAINING"]).glob("*.csv"))
    rows = []
    for path in files:
        with open(path, newline="", encoding="utf-8") as source:
            rows.extend(csv.DictReader(source))
    model = fit(rows)
    target = Path(os.environ["SM_MODEL_DIR"])
    target.mkdir(parents=True, exist_ok=True)
    with open(target / "model.json", "w", encoding="utf-8") as output:
        json.dump(model, output)
    held_out = [[-2.5], [-0.5], [0.5], [2.5]]
    expected = [0, 0, 1, 1]
    actual = predict_fn(held_out, model)
    accuracy = sum(a == b for a, b in zip(actual, expected)) / len(expected)
    print(json.dumps({"held_out_accuracy": accuracy, "predictions": actual}))
    if accuracy != 1.0:
        raise ValueError("Fixture quality gate failed")
```

Expected learned centroids are class0=-2.0 and class1=2.0. Held-out predictions are [0,0,1,1], accuracy1.0 **for this synthetic fixture only**. The x=0 tie is resolved to class0 by this code, not a calibrated real-world confidence policy.

Save/run the Boto3 driver below in an approved environment. It packages the actual code, waits with deadlines, deploys one endpoint and checks the request/response contract. It deliberately stops at a small synthetic quality gate, not automatic production approval.

```python
import json
import os
import tarfile
import time
import uuid
import boto3

region = boto3.Session().region_name
bucket, role = os.environ["SM_LAB_BUCKET"], os.environ["SM_LAB_ROLE"]
image = os.environ["SM_LAB_IMAGE_URI"]
if not region or not image:
    raise ValueError("Select Region and verified supported image first")
name = "dg06-centroid-" + uuid.uuid4().hex[:8]
sm, runtime, s3 = boto3.client("sagemaker"), boto3.client("sagemaker-runtime"), boto3.client("s3")
with tarfile.open("dg06-code.tar.gz", "w:gz") as archive:
    archive.add("train.py", arcname="train.py")
s3.upload_file("dg06-code.tar.gz", bucket, f"dg06/{name}/code.tar.gz")
s3.upload_file("train.csv", bucket, f"dg06/{name}/input/train.csv")
code = f"s3://{bucket}/dg06/{name}/code.tar.gz"
sm.create_training_job(
    TrainingJobName=name, RoleArn=role,
    AlgorithmSpecification={"TrainingImage": image, "TrainingInputMode": "File"},
    HyperParameters={
        "sagemaker_program": json.dumps("train.py"),
        "sagemaker_submit_directory": json.dumps(code),
        "sagemaker_region": json.dumps(region),
        "sagemaker_container_log_level": "20",
    },
    InputDataConfig=[{
        "ChannelName": "training", "ContentType": "text/csv",
        "DataSource": {"S3DataSource": {
            "S3DataType": "S3Prefix",
            "S3Uri": f"s3://{bucket}/dg06/{name}/input/",
            "S3DataDistributionType": "FullyReplicated",
        }},
    }],
    OutputDataConfig={"S3OutputPath": f"s3://{bucket}/dg06/{name}/training-output/"},
    ResourceConfig={"InstanceType": "ml.m5.large", "InstanceCount": 1, "VolumeSizeInGB": 10},
    StoppingCondition={"MaxRuntimeInSeconds": 300},
)
print("Recorded training/model/config/endpoint name:", name)
deadline = time.monotonic() + 1200
while time.monotonic() < deadline:
    job = sm.describe_training_job(TrainingJobName=name)
    if job["TrainingJobStatus"] == "Completed":
        break
    if job["TrainingJobStatus"] in {"Failed", "Stopped"}:
        raise RuntimeError(job.get("FailureReason", job["TrainingJobStatus"]))
    time.sleep(5)
else:
    sm.stop_training_job(TrainingJobName=name)
    raise TimeoutError("Stop requested; inspect training terminal state")
sm.create_model(
    ModelName=name, ExecutionRoleArn=role,
    PrimaryContainer={
        "Image": image, "ModelDataUrl": job["ModelArtifacts"]["S3ModelArtifacts"],
        "Environment": {
            "SAGEMAKER_PROGRAM": "train.py",
            "SAGEMAKER_SUBMIT_DIRECTORY": code,
            "SAGEMAKER_REGION": region,
            "SAGEMAKER_CONTAINER_LOG_LEVEL": "20",
        },
    },
)
sm.create_endpoint_config(EndpointConfigName=name, ProductionVariants=[{
    "VariantName": "AllTraffic", "ModelName": name,
    "InitialInstanceCount": 1, "InstanceType": "ml.m5.large",
}])
sm.create_endpoint(EndpointName=name, EndpointConfigName=name)
deadline = time.monotonic() + 1200
while time.monotonic() < deadline:
    endpoint = sm.describe_endpoint(EndpointName=name)
    if endpoint["EndpointStatus"] == "InService":
        break
    if endpoint["EndpointStatus"] in {"Failed", "OutOfService"}:
        raise RuntimeError(endpoint.get("FailureReason", endpoint["EndpointStatus"]))
    time.sleep(5)
else:
    raise TimeoutError("Inspect/delete the recorded endpoint; it may still incur charges")
result = runtime.invoke_endpoint(
    EndpointName=name, ContentType="application/json", Accept="application/json",
    Body=json.dumps([[-2.5], [-0.5], [0.5], [2.5]]).encode(),
)
predictions = json.loads(result["Body"].read())["predictions"]
assert predictions == [0, 0, 1, 1], predictions
print("Verified fixture response:", predictions)
```

Inspect the training logs for the held-out gate, then test a wrong feature shape to confirm visible validation failure. Do not log sensitive real input. Single-model hosting loads one model artifact per selected model/config; multi-model hosting instead requires a supported multi-model container and TargetModel routing to distinct artifacts. This lab is **single-model**, not a MultiDataModel retrofit.

Cleanup uses the printed exact name: DeleteEndpoint, wait until DescribeEndpoint reports ResourceNotFound, then DeleteEndpointConfig and DeleteModel. If training is still running, request stop and confirm its terminal state. Remove only dg06/name code/data/artifacts and approved log groups after retaining required evaluation evidence. Endpoints bill while idle; delete requests are not disappearance evidence.

Sources: [custom Scikit-learn workflow](https://docs.aws.amazon.com/sagemaker/latest/dg/sklearn.html), [training API](https://docs.aws.amazon.com/boto3/latest/reference/services/sagemaker/client/create_training_job.html), [model API](https://docs.aws.amazon.com/boto3/latest/reference/services/sagemaker/client/create_model.html), [InvokeEndpoint](https://docs.aws.amazon.com/boto3/latest/reference/services/sagemaker-runtime/client/invoke_endpoint.html), [multi-model prerequisites](https://docs.aws.amazon.com/sagemaker/latest/dg/multi-model-endpoints.html).
