---
title: Amazon SageMaker
description: Amazon SageMaker — end-to-end ML platform. Jupyter notebooks, training, hyperparameter tuning, inference endpoints, Pipelines, Feature Store, Edge Manager, and JumpStart.
tags:
  - aws
  - machine-learning
  - sagemaker
---

# Amazon SageMaker

SageMaker is AWS's end-to-end ML platform. It provides managed Jupyter notebooks, distributed training clusters, auto-scaling inference endpoints, ML pipelines, feature stores, and model monitoring. Built for data scientists who need full control over their ML workflow.

## Core Components

```
SageMaker Studio (Web IDE)
  │
  ├── Notebook Instances (Jupyter)
  ├── Training Jobs
  ├── Hyperparameter Tuning
  ├── Inference Endpoints
  ├── SageMaker Pipelines (CI/CD for ML)
  ├── Feature Store
  ├── Model Monitor
  └── JumpStart (pre-built models)
```

## SageMaker Studio

```bash
# Create SageMaker domain (first time setup)
aws sagemaker create-domain \
  --domain-name my-domain \
  --auth-mode IAM \
  --default-user-settings '{
    "jupyterServerAppSettings": {
      "defaultResourceSpec": {"InstanceType": "ml.t3.medium"}
    }
  }' \
  --subnet-ids subnet-xxxxx \
  --vpc-id vpc-xxxxx
```

## Training Jobs

### Python (SKLearn)

```python
import sagemaker
import boto3
from sagemaker.sklearn import SKLearn

sagemaker_session = sagemaker.Session()
role = 'arn:aws:iam::123456789012:role/SageMakerExecutionRole'

# Define training script
sklearn = SKLearn(
    entry_point='train.py',
    source_dir='./scripts',
    role=role,
    instance_count=1,
    instance_type='ml.m5.xlarge',
    framework_version='1.2-1'
)

# Train
sklearn.fit({'train': 's3://my-bucket/train/'})
```

### Distributed Training (GPU)

```python
from sagemaker.pytorch import PyTorch

pytorch = PyTorch(
    entry_point='train_distributed.py',
    role=role,
    instance_count=4,
    instance_type='ml.p4d.24xlarge',  # 8x A100 GPUs
    distribution={
        'pytorchxla': {'enabled': True},  # XLA for GPU cluster
        'torchrun': {
            'enabled': True,
            'processes_per_host': 8  # 8 GPUs per node
        }
    }
)
pytorch.fit()
```

## Hyperparameter Tuning

```python
from sagemaker.tuner import IntegerParameter, ContinuousParameter, HyperparameterTuner

tuner = HyperparameterTuner(
    estimator=pytorch,
    objective_metric_name='accuracy',
    metric_definitions=[{'Name': 'accuracy', 'Regex': 'accuracy=(0\\.[0-9]+)'}],
    hyperparameter_ranges={
        'learning_rate': ContinuousParameter(0.001, 0.1),
        'batch_size': IntegerParameter(16, 256),
        'num_layers': IntegerParameter(2, 6)
    },
    max_jobs=20,
    max_parallel_jobs=4,
    strategy='Bayesian'
)
tuner.fit()
```

## Inference Endpoints

### Real-time Endpoint

```python
# Deploy model
predictor = sklearn.deploy(
    initial_instance_count=1,
    instance_type='ml.m5.large'
)

# Predict
response = predictor.predict([[1.5, 2.3, 0.8]])
```

### Auto-scaling

```python
import boto3

autoscaling = boto3.client('application-autoscaling')

# Register endpoint
autoscaling.register_scalable_target(
    ServiceNamespace='sagemaker',
    ResourceId='endpoint/my-endpoint/variant/AllTraffic',
    ScalableDimension='sagemaker:variant:DesiredInstanceCount'
)

# Configure scaling policy
autoscaling.put_scaling_policy(
    PolicyName='my-scaling-policy',
    ServiceNamespace='sagemaker',
    ResourceId='endpoint/my-endpoint/variant/AllTraffic',
    ScalableDimension='sagemaker:variant:DesiredInstanceCount',
    PolicyType='TargetTrackingScaling',
    TargetTrackingScalingPolicyConfiguration={
        'TargetValue': 70,
        'PredefinedMetricSpecification': {'PredefinedMetricType': 'SageMakerVariantCPUUtilization'}
    }
)
```

### Multi-Model Endpoint (Host 100s of Models)

```python
# Create multi-model endpoint
from sagemaker.multidatamodel import MultiDataModel

multi_model = MultiDataModel(
    name='multi-model-endpoint',
    model_data_prefix='s3://my-bucket/models/',
    estimator=sklearn,
    endpoint=endpoint_name
)
multi_model.deploy(instance_type='ml.m5.xlarge', initial_instance_count=1)

# Load specific model
predictor = multi_model.deploy('model-v1.tar.gz')
```

## SageMaker Pipelines

```python
from sagemaker.pipeline import Pipeline
from sagemaker.workflow.function_step import step
from sagemaker.workflow.parameters import ParameterString

# Define pipeline
pipeline = Pipeline(
    name='my-training-pipeline',
    parameters=[
        ParameterString('InputData'),
        ParameterString('ModelName')
    ],
    steps=[train_step, eval_step, register_step, deploy_step]
)

# Trigger pipeline
pipeline.upsert(role_arn=role)
execution = pipeline.start()
```

## Feature Store

```python
from sagemaker.feature_store.feature_group import FeatureGroup

feature_group = FeatureGroup(name='user-features', sagemaker_session=sagemaker_session)

# Define feature definitions
feature_group.load_feature_definitions(
    data_frame=pd.DataFrame({
        'user_id': [1, 2, 3],
        'age': [25, 30, 35],
        'total_purchases': [100, 200, 300]
    })
)

# Create feature group
feature_group.create(
    s3_uri='s3://my-bucket/features/',
    enable_online_store=True,
    online_store_kms_key_id='kms-key-id'
)

# Write features
feature_group.ingest(data_frame=user_features, wait=True)

# Retrieve features (online store)
featurestore = boto3.client('featurestore-runtime')
response = featurestore.get_record(
    FeatureGroupName='user-features',
    RecordIdentifierValueAsString='user-123'
)
```

## Model Monitor

```python
from sagemaker.model_monitor import DataCaptureConfig, ModelMonitor

# Enable data capture
data_capture = DataCaptureConfig(
    enable_capture=True,
    sampling_percentage=100,
    destination_s3_uri='s3://my-bucket/captured/'
)

# Deploy with monitoring
predictor = sklearn.deploy(
    initial_instance_count=1,
    instance_type='ml.m5.large',
    data_capture_config=data_capture
)

# Create monitor schedule
monitor = ModelMonitor(
    role=role,
    sagemaker_session=sagemaker_session
)
monitor.create_monitoring_schedule(
    monitor_schedule_name='my-monitor',
    endpoint_input=predictor.endpoint_name,
    statistics=BaselineStatistics(file_uri='s3://my-bucket/baseline/'),
    constraints=ModelConstraints(file_uri='s3://my-bucket/constraints/')
)
```

## JumpStart (Pre-built Models)

```python
from sagemaker import jumpstart

# List available models
models = jumpstart.list_models(filter='task == "Text Generation"')

# Deploy pre-built LLM
predictor = jumpstart.deploy(
    model_id='meta-textgeneration-llama-3-8b-instruct',
    model_version='*',
    instance_type='ml.m5.xlarge'
)
```

## Edge Manager

```python
# Package model for edge deployment
edge_packager = boto3.client('sagemaker-edge')
edge_packager.create_model(
    ModelName='my-model',
    ModelVersion='1.0',
    ModelArtifact='s3://my-bucket/model.tar.gz',
    DeviceFleetName='my-device-fleet'
)
```

## Pricing

| Component | Cost |
|-----------|------|
| Notebook instances | $0.05-$4.50/hr (per instance type) |
| Training (CPU) | $0.05-$0.25/hr per instance |
| Training (GPU) | $1.01-$37.50/hr per instance |
| Inference (real-time) | $0.10-$4.50/hr per instance |
| Inference (serverless) | $0.00002/inference + $0.0002/GB-model |
| Model Monitor | $0.50/GB monitored data |
| Feature Store (online) | $0.105/1000 writes, $0.05/10000 reads |

## References

- **Homepage:** https://aws.amazon.com/sagemaker/
- **Documentation:** https://docs.aws.amazon.com/sagemaker/
- **Pricing:** https://aws.amazon.com/sagemaker/pricing/

## Nuggets & Gotchas

- **SageMaker training jobs run on managed infrastructure — your data IS processed by AWS:** Unlike EC2 where you control everything, SageMaker training uses AWS-managed compute. For maximum data isolation, use VPC-only training and encryption with your own KMS key.
- **SageMaker inference endpoints are NOT auto-healing — if the instance fails, you must redeploy:** Unlike ECS services, SageMaker endpoints don't automatically restart failed instances. Use Auto Scaling and CloudWatch alarms to trigger endpoint updates.
- **SageMaker Pipelines uses a different execution engine than you might expect — it runs steps as separate Lambda or Step Functions under the hood:** Pipeline steps are executed asynchronously. If a step fails, check the step's CloudWatch logs.
- **SageMaker Feature Store online store is expensive at scale — $0.05/10000 reads adds up:** If you're reading features 100K times/second, that's $0.50/second = $43K/day. Consider caching frequently-read features in ElastiCache or DynamoDB.
- **SageMaker JumpStart models are NOT fine-tuned on your data — they're pre-trained:** JumpStart gives you a head start with pre-trained weights, but you still need to fine-tune or use RAG for domain-specific tasks.