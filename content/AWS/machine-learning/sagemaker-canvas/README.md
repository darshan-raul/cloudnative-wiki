---
title: "Amazon SageMaker Canvas"
description: "Canvas provides supported visual ML/data workflows, with custom/ready-to-use model capabilities that vary by model and task."
tags:
  - aws/machine-learning
date: 2026-10-12
---

# Amazon SageMaker Canvas

Canvas provides supported visual ML/data workflows, with custom/ready-to-use model capabilities that vary by model and task. It does not remove the need for [[AWS/machine-learning/README|evaluation]], secure input data or [[AWS/security/iam/README|execution-role permissions]].

## Workflow and deployment

Provision the supported SageMaker environment/Canvas application, authorize input/output data, import a representative dataset and choose the supported target/task. Data preparation, quick versus standard build, forecasting and prediction options have distinct requirements. A quick-build sample is not an import ceiling.

There is no documented boto3.client("sagemaker-canvas") service with the fabricated create-model/start-build/get-metrics operations. Use the supported Canvas UI/workflows and real [[AWS/machine-learning/sagemaker/README|SageMaker AI]] APIs where documented; do not rebrand UI steps as executable SDK methods.

Eligible Canvas custom/JumpStart model versions can deploy to SageMaker AI real-time hosting endpoints. “No production deployment” is false, while universal export/deployment support for every ready-to-use model is also unsafe. Verify execution-role, feature/model and endpoint requirements before deploying.

## Quality and limits

Tabular support includes up to 1,000 columns; import/build/model-type limits differ. There is no universal hundred-column or hundred-thousand-row ceiling. Consult the owning task/data limit table for the chosen operation.

Accuracy alone can hide rare-class failure or leakage. Use held-out data, precision/recall and business cost of false positives/negatives; forecasting requires chronological splits and suitable horizon/granularity. Compare a simple baseline and review missing-value/category handling before trusting a visual leaderboard.

## Worked visual classification lab: synthetic churn dataset

This lab provides a concrete synthetic dataset and step-by-step Canvas procedure. Canvas UI steps are retained as operating guidance, while nonexistent `sagemaker-canvas` SDK methods remain excluded.

### Synthetic dataset fixture

Save this complete six-row labelled fixture as `canvas-churn-lab.csv`:

```csv
customer_id,monthly_spend,tenure_months,support_tickets,churned
c101,85.50,14,1,0
c102,120.00,3,4,1
c103,45.00,24,0,0
c104,110.00,5,3,1
c105,60.00,18,1,0
c106,95.00,2,5,1
```

Upload to a private bucket prefix:

```bash
aws s3 cp canvas-churn-lab.csv "s3://${CANVAS_LAB_BUCKET:?}/canvas-lab/input/canvas-churn-lab.csv"
```

### Canvas UI walkthrough

1. **Import data**: In SageMaker Studio -> Canvas -> Datasets -> Import Data -> S3 -> select `canvas-churn-lab.csv`. Confirm detected schema: `customer_id` (Text/ID), `monthly_spend` (Numeric), `tenure_months` (Numeric), `support_tickets` (Numeric), `churned` (Binary/Categorical).
2. **Select model & target**: In Models -> New Model, name `wiki-canvas-churn-lab`. Select the imported dataset. Choose target column `churned`. Canvas detects 2-class classification.
3. **Build selection**:
   - **Quick build**: Runs in 2–15 minutes using a sampled subset for fast validation.
   - **Standard build**: Performs full AutoML search across model families (XGBoost, neural networks, linear models) and requires 1–4 hours.
   - Select Quick build for this lab exercise.
4. **Evaluate held-out metrics**:
   - Inspect accuracy, F1 score, confusion matrix, and feature impact.
   - Observe that `support_tickets` (high = churn) and `tenure_months` (low = churn) are top predictive features.
5. **Generate predictions**:
   - In the **Predict** tab, test Single prediction:
     - Input: `customer_id=c901, monthly_spend=115.00, tenure_months=2, support_tickets=4` -> expected prediction `churned = 1` (probability > 80%).
     - Input: `customer_id=c902, monthly_spend=40.00, tenure_months=24, support_tickets=0` -> expected prediction `churned = 0` (probability > 85%).
   - Batch prediction: upload a test CSV without the target column; export scored predictions to S3.
6. **Deployment & API boundary**:
   - Canvas does **not** expose a programmatic `boto3.client('sagemaker-canvas')` client.
   - To serve predictions programmatically, deploy an eligible model build to a SageMaker real-time endpoint via the Canvas UI ("Deploy model"). That creates a standard SageMaker endpoint, which is invoked via `boto3.client('sagemaker-runtime').invoke_endpoint(...)`.
7. **Cleanup and cost management**:
   - Canvas charges an hourly session rate while the workspace app is running, plus training/build charges and hosted endpoint hourly rates.
   - Deleting the model inside Canvas does **not** terminate the Studio Canvas workspace app.
   - In SageMaker Console -> Domains -> Applications -> delete the running Canvas user application to stop ongoing session billing.
   - If an endpoint was deployed, delete it via `aws sagemaker delete-endpoint --endpoint-name ...` and remove the endpoint configuration and model.
   - Delete the test CSV and exported prediction artifacts from S3.

## Visual workflow from dataset to predictions

```text
Authorized sources
  → import + schema/type review
  → preparation/target selection
  → quick or standard build
  → validation/feature review
  → batch predictions or eligible endpoint deployment
```

| Task family                 | What to verify                                                    |
| --------------------------- | ----------------------------------------------------------------- |
| Tabular classification      | Label definitions, minority classes, leakage and missing values   |
| Regression                  | Target units, error distribution and useful baseline              |
| Time-series forecasting     | Timestamp/entity keys, frequency, horizon and chronological split |
| Ready-to-use models         | Supported input/task and operation-specific permissions/limits    |
| JumpStart/custom deployment | Eligible model/version, hosting permissions and endpoint charges  |

A quick build is useful for iteration, not proof that all input rows were used or production quality was achieved. A standard build can require more time/compute; document the exact version and task rather than assume every model shares one fixed duration.

## Build/evaluation walkthrough

1. Authorize/import only the required non-sensitive dataset.
2. Inspect row/column types and reject target leakage; define missing/category handling.
3. Choose the supported task and prediction target, then create the selected build.
4. Inspect build status and errors with a bounded wait; no fictional Canvas Boto3 loop is implied.
5. Review held-out metrics and feature influence cautiously—correlation is not causation.
6. Test known cases, outliers and missing/unseen categories.
7. Generate supported batch results or deploy an eligible model/version.
8. Compare actual prediction/output schema, latency and current cost before promotion.

For classification, compare precision/recall at the relevant threshold. For forecasting, avoid random splits that use future information; score at the actual horizon and aggregate business level. For regression, inspect residuals and segments rather than only one overall error.

## Deployment and cleanup boundaries

Eligible custom/JumpStart versions can deploy to real-time endpoints through the supported workflow; ready-to-use model capabilities differ. Endpoint instances, role/data/KMS access and monitoring are genuine production responsibilities even when the model was built visually.

Preserve approved model/version/evaluation evidence before deleting disposable builds. Stop/delete app/session resources and deployed endpoints intentionally, inspect retained S3 data/artifacts and do not confuse closed browser state with stopped billing. Canvas UI steps are retained as operating guidance, while nonexistent sagemaker-canvas SDK methods remain excluded.

## References

- [Canvas documentation and supported workflows](https://docs.aws.amazon.com/sagemaker/latest/dg/canvas.html)
- [Data requirements](https://docs.aws.amazon.com/sagemaker/latest/dg/canvas-data.html)
- [Canvas endpoint deployment](https://docs.aws.amazon.com/sagemaker/latest/dg/canvas-deploy-model.html)
- [Boto3 service catalog](https://docs.aws.amazon.com/boto3/latest/reference/services/)
- [Canvas pricing](https://aws.amazon.com/sagemaker/canvas/pricing/)
