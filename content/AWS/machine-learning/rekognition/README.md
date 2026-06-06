---
title: Amazon Rekognition
description: Amazon Rekognition — image and video analysis. Object detection, face comparison, celebrity recognition, text extraction, unsafe content detection, and video segment detection.
tags:
  - aws
  - machine-learning
  - rekognition
  - computer-vision
  - ai-services
---

# Amazon Rekognition

Rekognition provides pre-trained computer vision models for image and video analysis. It detects objects, scenes, faces, text, celebrities, and inappropriate content. No ML expertise needed — just call an API.

## Image vs Video

| Feature | Image API | Video API |
|---------|----------|----------|
| DetectLabels | Yes | Yes |
| DetectFaces | Yes | Yes |
| CompareFaces | Yes | No |
| DetectText | Yes | Yes |
| DetectModerationLabels | Yes | Yes |
| RecognizeCelebrities | Yes | Yes |
| StartSegmentDetection | No | Yes |

## Image Analysis

### Detect Objects and Scenes

```python
import boto3

rekognition = boto3.client('rekognition')

response = rekognition.detect_labels(
    Image={'S3Object': {'Bucket': 'my-bucket', 'Name': 'photo.jpg'}},
    MaxLabels=10,
    MinConfidence=80
)

for label in response['Labels']:
    print(f"{label['Name']} ({label['Confidence']:.1f}%)")
    for parent in label.get('Parents', []):
        print(f"  Parent: {parent['Name']}")
```

### Detect Faces

```python
response = rekognition.detect_faces(
    Image={'S3Object': {'Bucket': 'my-bucket', 'Name': 'person.jpg'}},
    Attributes=['DEFAULT', 'AGE_RANGE', 'EMOTIONS', 'QUALITY']
)

for face in response['FaceDetails']:
    print(f"Age: {face['AgeRange']['Low']}-{face['AgeRange']['High']}")
    print(f"Emotion: {face['Emotions'][0]['Type']}")
    print(f"Gender: {face['Gender']['Value']}")
```

### Compare Faces

```python
response = rekognition.compare_faces(
    SourceImage={'S3Object': {'Bucket': 'my-bucket', 'Name': 'id-card.jpg'}},
    TargetImage={'S3Object': {'Bucket': 'my-bucket', 'Name': 'selfie.jpg'}},
    SimilarityThreshold=80
)

for match in response['FaceMatches']:
    print(f"Similarity: {match['Similarity']:.1f}%")
    print(f"Face: {match['Face']['BoundingBox']}")

for unmatched in response['UnmatchedFaces']:
    print(f"No match for: {unmatched['Face']['BoundingBox']}")
```

### Detect Text

```python
response = rekognition.detect_text(
    Image={'S3Object': {'Bucket': 'my-bucket', 'Name': 'document.jpg'}}
)

for text in response['TextDetections']:
    print(f"{text['DetectedText']} (Confidence: {text['Confidence']:.1f}%)")
    print(f"  Type: {text['Type']}")  # LINE or WORD
```

### Unsafe Content Detection

```python
response = rekognition.detect_moderation_labels(
    Image={'S3Object': {'Bucket': 'my-bucket', 'Name': 'image.jpg'}}
)

for label in response['ModerationLabels']:
    print(f"{label['Name']}: {label['Confidence']:.1f}%")
    print(f"  Parent: {label['Parent']['Name']}")
```

### Recognize Celebrities

```python
response = rekognition.recognize_celebrities(
    Image={'S3Object': {'Bucket': 'my-bucket', 'Name': 'event-photo.jpg'}}
)

for celeb in response['CelebrityFaces']:
    print(f"{celeb['Name']} ({celeb['MatchConfidence']:.1f}%)")
    print(f"  URLs: {celeb.get('Urls', [])}")
```

## Video Analysis

### Start Video Detection

```python
# Start label detection
response = rekognition.start_label_detection(
    Video={'S3Object': {'Bucket': 'my-bucket', 'Name': 'video.mp4'}},
    MinConfidence=80,
    NotificationChannel={
        'SNSTopicArn': 'arn:aws:sns:us-east-1:123456789012:rekognition',
        'RoleArn': 'arn:aws:iam::123456789012:role/rekognition-role'
    }
)
job_id = response['JobId']
```

### Get Video Results

```python
import time

# Poll for completion
while True:
    result = rekognition.get_label_detection(JobId=job_id)
    status = result['VideoMetadata']['Status']
    
    if status == 'SUCCEEDED':
        for label in result['Labels']:
            print(f"{label['Label']['Name']} ({label['Label']['Confidence']:.1f}%)")
            print(f"  Timestamp: {label['Timestamp']}ms")
        break
    elif status == 'FAILED':
        print(f"Job failed: {result['VideoMetadata']['FailureReason']}")
        break
    
    time.sleep(5)
```

### Segment Detection (Shots, Scenes, Technical)

```python
response = rekognition.start_segment_detection(
    Video={'S3Object': {'Bucket': 'my-bucket', 'Name': 'video.mp4'}},
    SegmentTypes=['TECHNICAL_CUE_SHOT', 'SHOT', 'SCENE_CHANGE']
)

job_id = response['JobId']
```

## Custom Labels (Rekognition Custom)

Train a model for your specific use case:

```python
# Create project
project = rekognition.create_project(ProjectName='my-custom-labels')

# Create dataset (import from S3)
rekognition.create_dataset(
    DatasetSource={'S3Location': {'Bucket': 'my-bucket', 'ManifestSummary': 's3://my-bucket/manifest.json'}},
    DatasetType='TRAIN'
)

# Train model
response = rekognition.create_project_version(
    ProjectArn=project['ProjectArn'],
    OutputConfig={'S3Location': {'Bucket': 'my-bucket', 'Prefix': 'model/'}},
    TrainingData={'Assets': [{'S3Location': {'Bucket': 'my-bucket', 'Name': 'train.manifest'}}]},
    TestingData={'Assets': [{'S3Location': {'Bucket': 'my-bucket', 'Name': 'test.manifest'}}]}
)

# Deploy
rekognition.start_project_version(
    ProjectVersionArn=version_arn,
    MinInferenceUnits=1
)
```

## Pricing

| Operation | Cost |
|-----------|------|
| Image (DetectLabels, DetectFaces, etc.) | $0.0012/image |
| Video (StartLabelDetection) | $0.10/minute |
| Video (StartPersonTracking) | $0.10/minute |
| Video (StartFaceDetection) | $0.10/minute |
| Video (StartCelebrityRecognition) | $0.12/minute |
| Video (StartContentModeration) | $0.10/minute |
| Video (StartSegmentDetection) | $0.035/minute |
| CompareFaces | $0.0012/comparison |
| Custom Labels | $4.00/hr training, $0.40/hr inference |

## References

- **Homepage:** https://aws.amazon.com/rekognition/
- **Documentation:** https://docs.aws.amazon.com/rekognition/
- **Pricing:** https://aws.amazon.com/rekognition/pricing/

## Nuggets & Gotchas

- **Rekognition's face comparison is similarity scoring, NOT identity verification:** Rekognition tells you two faces are 95% similar. It doesn't tell you who the person IS. For identity verification, you need Amazon Verify or your own 1:1 enrollment system.
- **Rekognition video processing is ASYNC — you must use SNS/SQS or poll for results:** Start the job, then either subscribe to SNS or poll `get_*_detection` every few seconds. Video jobs can take minutes for long videos.
- **Rekognition's confidence scores vary by use case — a 90% confidence label might still be wrong 10% of the time:** For safety-critical applications (autonomous vehicles, medical), use confidence thresholds > 95% and add human review.
- **Custom Labels pricing is expensive — $4/hr for training can run up fast:** Training a Custom Labels model can take 1-24 hours depending on dataset size. Budget $100-1,000 per model training run.
- **Rekognition doesn't store faces — CompareFaces and IndexFaces store references only:** If you want a face database, you manage it yourself. Rekognition just stores face vectors (not images) and returns similarity scores.