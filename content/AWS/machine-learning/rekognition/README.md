---
title: "Amazon Rekognition"
description: "Rekognition offers supported image/video analysis and Custom Labels."
tags:
  - aws/machine-learning
date: 2026-10-12
---

# Amazon Rekognition

Rekognition offers supported image/video analysis and Custom Labels. Use only authorized imagery and evaluate error rates, consent and downstream decisions; a confidence score is not a guarantee. Prerequisites: [[AWS/machine-learning/README|evaluation/privacy]], [[AWS/security/iam/README|IAM]] and [[AWS/storage/s3/README|S3]].

## Image, video and asynchronous contracts

Image operations accept supported bytes/S3 inputs with operation-specific limits. Video workflows use start/get operations and required role/notification configuration where applicable. Poll using JobStatus and StatusMessage, not nonexistent VideoMetadata.Status/FailureReason. Handle terminal FAILED status, a deadline/backoff and NextToken pagination.

Segment types are TECHNICAL_CUE and SHOT, not TECHNICAL_CUE_SHOT or SCENE_CHANGE. Do not extrapolate one operation's input/features to every video API. Person Pathing retired October 31, 2025; that does not retire the whole Rekognition service.

## Custom Labels lifecycle

CreateDataset requires ProjectArn and DatasetType TRAIN/TEST; manifest configuration nests GroundTruthManifest.S3Object. CreateProjectVersion requires a unique VersionName and OutputConfig with S3Bucket/S3KeyPrefix, not a invented S3Uri/model-version shape.

Follow asynchronous dataset/training status and evaluate held-out quality before inference. Starting inference and stopping inference are separate lifecycle steps; a completed training job does not automatically mean an always-running free endpoint. Pin a maintained owning example rather than showing placeholders as tested API code.

## Bounded evaluation exercise

Use synthetic/consented non-sensitive images or a short test video, an isolated bucket/role and a budget. Compare output labels/segments against hand-labelled expected answers. Measure false positives/negatives at the chosen threshold; do not apply automated sensitive decisions without the required review.

Demonstrate unauthorized access denial and unsupported-input failure. For asynchronous results, verify all pages and fail cleanly on job failure or timeout. For Custom Labels, follow the owning workflow to create a tiny eligible dataset, train/evaluate only if budgeted, then start/stop inference deliberately.

Remove sandbox inference capacity, projects/versions/datasets and reviewed S3/log artifacts according to documented dependencies and retention. Stopping inference does not itself delete training artifacts. Record created identifiers before cleanup; no account-wide deletion recipe is implied.

## Cost and operational boundaries

Pricing depends on operation: image groups/features, video analysis duration, Custom Labels training/inference and supporting storage/requests can differ. Use actual elapsed usage and current Region rates; don't apply one per-image rate to all products. CloudTrail/S3/IAM audit and privacy retention should be designed before processing real customer imagery.

## Image labels and a scoped request

This SDK example analyzes an authorized synthetic image already in private S3. It invokes a billable supported image operation, not Custom Labels training or a guaranteed object detector for every domain.

```python
import boto3

client = boto3.client("rekognition")
response = client.detect_labels(
    Image={"S3Object": {
        "Bucket": "example-unique-bucket",
        "Name": "sandbox/image.jpg",
    }},
    MaxLabels=10,
    MinConfidence=80,
)
for label in response.get("Labels", []):
    print(label["Name"], label["Confidence"])
```

Verify accepted file/size/Region access and manually compare labels to expected content. MinConfidence is a chosen threshold, not a universal safe operating point.

## Asynchronous video result lifecycle

```text
supported Start operation
  → JobId
  → IN_PROGRESS
  → SUCCEEDED or FAILED
  → paginated Get results
  → evaluated/retained output
```

Use the correct operation-specific get call and JobStatus/StatusMessage. On success, follow NextToken until exhausted; one page can omit most results. Use a monotonic deadline/backoff and handle service/auth errors separately from job failure. TECHNICAL_CUE and SHOT are supported segment types; do not invent a SCENE_CHANGE enum.

```python
import os
import time
import boto3

rekognition = boto3.client("rekognition")
bucket = os.environ.get("REKOGNITION_LAB_BUCKET", "example-rekognition-bucket")
video_key = "sandbox/sample-clip.mp4"

# 1. Start asynchronous label detection
start_res = rekognition.start_label_detection(
    Video={"S3Object": {"Bucket": bucket, "Name": video_key}},
    MinConfidence=80.0,
)
job_id = start_res["JobId"]
print("Started video label detection JobId:", job_id)

# 2. Bounded polling loop with monotonic deadline
deadline = time.monotonic() + 300
job_status = "IN_PROGRESS"

while time.monotonic() < deadline:
    res = rekognition.get_label_detection(JobId=job_id, MaxResults=1)
    job_status = res["JobStatus"]
    if job_status in {"SUCCEEDED", "FAILED"}:
        break
    time.sleep(5)

if job_status != "SUCCEEDED":
    raise RuntimeError(f"Video job failed or timed out with status: {job_status}")

# 3. Paginated retrieval using NextToken
all_labels = []
next_token = None

while True:
    kwargs = {"JobId": job_id, "MaxResults": 100}
    if next_token:
        kwargs["NextToken"] = next_token
    page = rekognition.get_label_detection(**kwargs)
    for detection in page.get("Labels", []):
        all_labels.append({
            "timestamp": detection["Timestamp"],
            "name": detection["Label"]["Name"],
            "confidence": detection["Label"]["Confidence"],
        })
    next_token = page.get("NextToken")
    if not next_token:
        break

print(f"Retrieved {len(all_labels)} label detections across video pages.")
```

Video analysis, image requests and Custom Labels training/inference are different billing/workflow models. Person Pathing is retired; preserve its historical context only, not active start/get recommendations.

## Custom Labels dataset/training sequence

1. Create the project and prepare a supported labelled manifest.
2. Create TRAIN/TEST datasets using ProjectArn, DatasetType and nested GroundTruthManifest.S3Object.
3. Validate dataset status/labels and split test data without train/test leakage.
4. Create a uniquely named project version with correct S3 OutputConfig.
5. Observe terminal training state and review held-out metrics.
6. Start only approved, budgeted inference capacity and wait for actual readiness.
7. Invoke held-out cases, evaluate false positives/negatives and test authorization denial.
8. Stop inference when finished; remove versions/datasets/project only after dependency/retention review.

Do not paste a fabricated S3Uri/version shape into a runnable tutorial. Labels and training quality depend on representative data; model availability does not assure consent or acceptable sensitive decisions. Retained images/results require the same privacy/access discipline as the original data.

## Monitoring and cost

Track operation failures/throttling, end-to-end async completion and active custom inference usage. Compare image/video/Custom Labels units separately and include input/output S3/log costs. A confidence-threshold adjustment changes precision/recall, not the underlying authorization or privacy requirements. Keep human-review/fallback behavior explicit for consequential decisions.

## References

- [Video label result/status contract](https://docs.aws.amazon.com/boto3/latest/reference/services/rekognition/client/get_label_detection.html)
- [Video segments](https://docs.aws.amazon.com/rekognition/latest/dg/segments.html)
- [CreateDataset contract](https://docs.aws.amazon.com/boto3/latest/reference/services/rekognition/client/create_dataset.html)
- [CreateProjectVersion contract](https://docs.aws.amazon.com/boto3/latest/reference/services/rekognition/client/create_project_version.html)
- [Retired feature lifecycle](https://docs.aws.amazon.com/general/latest/gr/full_shutdown_services.html)
- [Rekognition pricing](https://aws.amazon.com/rekognition/pricing/)
