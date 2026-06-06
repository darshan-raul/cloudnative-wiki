---
title: SageMaker Canvas
description: SageMaker Canvas — no-code ML for business analysts. Build classification, regression, and time-series forecasting models via drag-and-drop UI. Generate predictions without writing code.
tags:
  - aws
  - machine-learning
  - sagemaker
  - sagemaker-canvas
  - no-code
---

# Amazon SageMaker Canvas

SageMaker Canvas provides a drag-and-drop interface for building ML models. Business analysts can build classification, regression, and time-series forecasting models without writing code or understanding ML algorithms.

## What Canvas Does

```
Business Analyst
  │
  ├── Upload CSV/Connect to S3/Redshift/Snowflake
  ├── Select target column (what to predict)
  ├── Canvas builds model automatically
  │     ├── Automatic data preparation
  │     ├── Algorithm selection
  │     ├── Hyperparameter tuning
  │     └── Model validation
  └── Generate predictions (batch or real-time)
```

## Model Types

| Type | Use Case | Example |
|------|----------|---------|
| Binary Classification | Yes/No prediction | Will customer churn? |
| Multi-class Classification | Category prediction | What product category? |
| Numeric Prediction (Regression) | Number prediction | How much will they spend? |
| Time Series Forecasting | Future values | Forecast demand for next 30 days |
| ML Models (Tabular) | Any tabular data | AutoML on your data |

## Getting Started

### 1. Open Canvas

```bash
# Create SageMaker Canvas app
aws sagemaker create-app \
  --domain-id domain-xxxxx \
  --user-profile-name analyst-01 \
  --app-name canvas \
  --app-type JupyterLab
```

Then open Canvas from SageMaker Studio.

### 2. Connect Data

Canvas supports:
- **Upload**: CSV, XLSX files directly
- **S3**: Browse and select S3 buckets
- **Redshift**: Query warehouse data
- **Snowflake**: Query Snowflake data
- **Databricks**: Query Databricks data

### 3. Build Model

```python
# Or via SageMaker Canvas API
import boto3

canvas = boto3.client('sagemaker-canvas', region_name='us-east-1')

# Create model
canvas.create_model(
    modelId='canvas-auto',
    modelName='customer-churn-predictor',
    dataset='s3://my-bucket/dataset.csv'
)

# Start build
canvas.start_model_training(
    modelName='customer-churn-predictor',
    objective='classification',
    targetAttribute='churned'
)
```

## Canvas Build Options

### Quick Build

- Builds in 20-30 minutes
- Uses smaller dataset sample
- Less accurate but faster
- Good for: exploration, POC

### Standard Build

- Builds in 2-4 hours
- Uses full dataset
- More accurate
- Good for: production models

## Evaluating Models

Canvas provides:
- **Accuracy score**
- **F1 score** (classification)
- **RMSE** (regression)
- **Feature importance** (which columns matter most)
- **Confusion matrix** (classification)
- **Predictions vs actuals** (regression)

```python
# Get model metrics
metrics = canvas.get_model_metrics(modelName='customer-churn-predictor')
print(metrics['binary_classification_metrics'])
# {'accuracy': 0.92, 'f1_score': 0.89, 'precision': 0.91, 'recall': 0.87}
```

## Generating Predictions

### Batch Predictions

```python
# Generate batch predictions
canvas.batch_transform(
    modelName='customer-churn-predictor',
    dataset='s3://my-bucket/new-customers.csv',
    outputUri='s3://my-bucket/predictions/'
)
```

### Real-time Predictions

```python
# Register for real-time
canvas.deploy(
    modelName='customer-churn-predictor',
    inferenceContainers=['default']
)

# Invoke endpoint
runtime = boto3.client('sagemaker-runtime')
response = runtime.invoke_endpoint(
    EndpointName='canvas-customer-churn-predictor',
    ContentType='text/csv',
    Body='age=35,income=75000,tenure=24,...'
)
```

## Time Series Forecasting

Canvas auto-generates forecasts:

```python
# Build time series model
canvas.start_model_training(
    modelName='demand-forecast',
    objective='forecasting',
    targetAttribute='sales',
    timeSeriesConfiguration={
        'timeColumn': 'date',
        'forecastFrequency': 'D',  # Daily
        'forecastHorizon': 30     # Forecast 30 days
    }
)
```

Forecast outputs:
- Point predictions
- Confidence intervals (80%, 95%)
- Trend, seasonality, holiday effects

## Pricing

| Component | Cost |
|-----------|------|
| Canvas app (SageMaker Studio) | Included in SageMaker Studio cost |
| Quick build | $0.40/hour |
| Standard build | $1.20/hour |
| Batch predictions | Free (uses inference) |
| Real-time predictions | Standard SageMaker inference pricing |

## Limits

| Resource | Limit |
|----------|-------|
| Dataset size | 100K rows, 100 columns |
| Training time | 48 hours |
| Forecast horizon | 730 periods |
| Model storage | 100 models |

## References

- **Homepage:** https://aws.amazon.com/sagemaker/canvas/
- **Documentation:** https://docs.aws.amazon.com/sagemaker-canvas/
- **Pricing:** https://aws.amazon.com/sagemaker/canvas/pricing/

## Nuggets & Gotchas

- **Canvas models are NOT exportable — you must use Canvas to predict:** Canvas produces a proprietary model artifact. You can't download the model and deploy elsewhere. For portable models, use SageMaker Autopilot or train with Python.
- **Canvas has a 100K row / 100 column limit — for larger datasets, sample before importing:** If your dataset is larger, sample down before importing into Canvas. Or use Athena to pre-aggregate.
- **Canvas doesn't support all data types — dates must be in a recognized format:** If your date column isn't recognized, format it as ISO 8601 (YYYY-MM-DD) before importing.
- **Canvas time series forecasting requires a UNIQUE time series identifier — if you have multiple products/stores, configure group columns:** A single forecast model handles multiple series (e.g., forecast each product separately in one model). Configure group columns in Canvas UI.
- **Canvas Quick Build is NOT for production — use Standard Build for any decision-making:** Quick build uses a sample of data and faster hyperparameters. The accuracy is significantly lower than Standard Build.