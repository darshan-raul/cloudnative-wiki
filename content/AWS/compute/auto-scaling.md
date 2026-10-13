---
title: "EC2 Auto Scaling and capacity lifecycle"
description: "Design health replacement, scaling signals, warm-up, interruption recovery and reversible fleet updates."
tags:
  - cloud/aws/compute
date: 2026-10-12
---

# EC2 Auto Scaling and capacity lifecycle

An Auto Scaling group maintains desired capacity within bounds. It does not make an unhealthy application healthy or provide a durable database by itself. Start with [[AWS/compute/ec2/README|EC2]] and [[AWS/networking/load-balancing/README|load balancing]].

## Separate the control loops

Health replacement restores group capacity. Dynamic scaling changes desired capacity in response to demand. Instance refresh rolls the fleet to a new configuration. Capacity reservations address launch-capacity needs; RIs/SPs are billing mechanisms with separate rules.

Use target tracking for a signal proportional to per-instance load; step scaling for explicit alarm thresholds; predictive scaling only with a workload suitable for forecasting. Define instance warm-up and prevent scale-in before work drains.

Lifecycle hooks pause supported launch/terminate transitions for a bounded workflow. Complete or abandon them deliberately and monitor timeout behavior. They do not universally run before the guest OS starts.

## Resilient capacity

Use diversified mixed-instance policies when suitable, with interruption-aware Spot handling and durable checkpoints. Warm pools reduce selected initialization work but incur retained-resource cost and have supported-configuration constraints. A large maximum capacity or quota increase does not guarantee instance availability.

## Sandbox refresh exercise

Prerequisites: the [[AWS/compute/ec2/README|launch-template lab]], two approved subnets, a small group and a disposable application with a health endpoint. Paid compute/LB/storage charges apply.

1. Create a group with a fixed launch-template version, minimum/desired two and a small maximum. Verify healthy targets in both AZs.
2. Create a new version displaying a different test marker; start an instance refresh with explicit healthy-capacity and warm-up settings.
3. Watch progress and health; confirm new instances serve the new marker before old ones drain.
4. Repeat with a deliberately unhealthy sandbox version and prove rollback/abort behavior. Do not count a launched instance as successful application deployment.
5. Review scaling history and alarm evidence for the failure.

Cleanup: disable lab scaling policies/schedules, scale to zero, delete the dedicated group, then remove its dedicated LB, template versions, volumes and logs. Preserve shared network resources. A group can recreate an instance that you manually terminate until desired capacity changes.

### Worked two-instance refresh

Use Bash on Linux, AWS CLI v2 and jq. The EC2 template lab supplies `wiki-ec2-lab`; choose an x86_64 image matching its t3 instance type, with cloud-init, systemd and `/usr/bin/python3` already available. This example does not install packages over the internet. Supply two private sandbox subnet IDs in `ASG_LAB_SUBNETS` (comma-separated), a dedicated reachable ALB's HTTP instance target group ARN in `ASG_LAB_TG_ARN`, and `ASG_LAB_URL` as that ALB's reachable HTTP URL. Configure health path `/health` on port 8080 and allow only the ALB SG to reach instance port 8080. The launch-template role/profile and subnet egress must support your selected SSM access. Stop if the subnet/target-group VPCs do not match.

Save `asg-user-v1.yaml` with this cloud-init payload, then save copies `asg-user-v2.yaml` with MARKER changed to `v2`, and `asg-user-bad.yaml` with MARKER `bad` and HEALTHY `False`:

```yaml
#cloud-config
write_files:
  - path: /opt/wiki-asg.py
    permissions: "0644"
    content: |
      from http.server import BaseHTTPRequestHandler, HTTPServer
      MARKER = "v1"
      HEALTHY = True
      class Handler(BaseHTTPRequestHandler):
          def do_GET(self):
              self.send_response(503 if self.path == "/health" and not HEALTHY else 200)
              self.end_headers()
              self.wfile.write(MARKER.encode())
      HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
  - path: /etc/systemd/system/wiki-asg.service
    permissions: "0644"
    content: |
      [Unit]
      Description=Disposable wiki ASG marker
      After=network.target
      [Service]
      ExecStart=/usr/bin/python3 /opt/wiki-asg.py
      Restart=on-failure
      [Install]
      WantedBy=multi-user.target
runcmd:
  - [systemctl, daemon-reload]
  - [systemctl, enable, --now, wiki-asg.service]
```

Make numeric template versions from the existing base (whose version 1 has no marker service). Do not change its default version or use `$Latest`:

```bash
aws sts get-caller-identity
: "${ASG_LAB_SUBNETS:?Set two dedicated subnet IDs}"
: "${ASG_LAB_TG_ARN:?Set the dedicated target group ARN}"
ASG_LAB_V1=$(aws ec2 create-launch-template-version \
  --launch-template-name wiki-ec2-lab --source-version 1 \
  --launch-template-data "$(jq -cn --arg u "$(base64 -w0 asg-user-v1.yaml)" '{UserData:$u}')" \
  --query LaunchTemplateVersion.VersionNumber --output text)
ASG_LAB_V2=$(aws ec2 create-launch-template-version \
  --launch-template-name wiki-ec2-lab --source-version "$ASG_LAB_V1" \
  --launch-template-data "$(jq -cn --arg u "$(base64 -w0 asg-user-v2.yaml)" '{UserData:$u}')" \
  --query LaunchTemplateVersion.VersionNumber --output text)
ASG_LAB_BAD=$(aws ec2 create-launch-template-version \
  --launch-template-name wiki-ec2-lab --source-version "$ASG_LAB_V1" \
  --launch-template-data "$(jq -cn --arg u "$(base64 -w0 asg-user-bad.yaml)" '{UserData:$u}')" \
  --query LaunchTemplateVersion.VersionNumber --output text)
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name wiki-asg-lab \
  --launch-template "LaunchTemplateName=wiki-ec2-lab,Version=$ASG_LAB_V1" \
  --vpc-zone-identifier "$ASG_LAB_SUBNETS" \
  --target-group-arns "$ASG_LAB_TG_ARN" \
  --min-size 2 --desired-capacity 2 --max-size 3 \
  --health-check-type ELB --health-check-grace-period 120 \
  --default-instance-warmup 60
aws elbv2 describe-target-health --target-group-arn "$ASG_LAB_TG_ARN"
```

Observe until two healthy targets exist, with a ten-minute learner stop limit; on timeout inspect scaling activities, cloud-init and target-health reasons rather than continuing. Confirm both target AZs and `v1` responses. Explicit target tracking uses a per-instance CPU signal (`asg-tracking.json`):

```json
{
  "TargetValue": 50.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ASGAverageCPUUtilization"
  },
  "DisableScaleIn": false
}
```

```bash
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name wiki-asg-lab --policy-name wiki-asg-cpu \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration file://asg-tracking.json
aws autoscaling describe-policies --auto-scaling-group-name wiki-asg-lab
# Remove it for a deterministic fixed-size refresh; do not generate an unbounded load.
aws autoscaling delete-policy --auto-scaling-group-name wiki-asg-lab \
  --policy-name wiki-asg-cpu
```

Expect service-created policy/alarm references, not instant scale-out from configuration alone. With desired two, minimum healthy 100% and maximum healthy 150%, refresh can temporarily run a third instance. Budget for this extra capacity; launch availability is still required. Start the refresh with **the new version in DesiredConfiguration**:

```bash
ASG_LAB_REFRESH=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name wiki-asg-lab \
  --desired-configuration "$(jq -cn --arg v "$ASG_LAB_V2" \
    '{LaunchTemplate:{LaunchTemplateName:"wiki-ec2-lab",Version:$v}}')" \
  --preferences '{"MinHealthyPercentage":100,"MaxHealthyPercentage":150,"InstanceWarmup":60,"SkipMatching":true,"AutoRollback":true,"CheckpointPercentages":[50,100],"CheckpointDelay":120}' \
  --query InstanceRefreshId --output text)
aws autoscaling describe-instance-refreshes --auto-scaling-group-name wiki-asg-lab \
  --instance-refresh-ids "$ASG_LAB_REFRESH"
aws autoscaling describe-scaling-activities --auto-scaling-group-name wiki-asg-lab
```

At the first checkpoint, save healthy-target evidence and both markers if both versions are still serving. Checkpoint delay resumes automatically; it is not an approval gate. Poll these read-only commands no longer than 30 minutes for `Successful`, `Failed`, `Cancelled`, `RollbackSuccessful` or `RollbackFailed`; record StatusReason and stop on timeout. After success, inspect the group's template version and both members: they should use the captured v2 numeric version, with healthy `v2` application responses. [Refresh request contract](https://docs.aws.amazon.com/cli/latest/reference/autoscaling/start-instance-refresh.html).

Repeat the start command with `ASG_LAB_BAD` instead of `ASG_LAB_V2`. New bad targets answer 503 at `/health`. This alone is not a promise of immediate rollback: health replacement may retry until the refresh fails. For a bounded drill, while the bad refresh is still in progress explicitly request:

```bash
aws autoscaling rollback-instance-refresh --auto-scaling-group-name wiki-asg-lab
```

Observe `RollbackSuccessful`, restored v2 numeric group/member configuration and healthy `v2` markers. Automatic rollback is enabled for supported failure conditions, but manual rollback is the chosen bounded failure path here. It requires the refresh's desired configuration and a previous fixed numeric template version, without unsupported SSM AMI aliases. [Rollback requirements](https://docs.aws.amazon.com/autoscaling/ec2/userguide/instance-refresh-rollback.html).

For a separate **cancellation** drill, start another refresh and call `aws autoscaling cancel-instance-refresh --auto-scaling-group-name wiki-asg-lab` while it is active. Save the member version mix before/after: cancellation stops further replacements and does not revert already-replaced members. Restore the known-good configuration through a new v2 refresh if needed; do not call cancellation a rollback.

Cleanup after a terminal refresh: delete any remaining lab policy, set minimum/desired to zero, wait for no group instances, and delete `wiki-asg-lab`. Verify the target group is empty, then remove only the dedicated ALB/listeners/group and the three captured template versions. Keep the EC2 lab's template/base or shared network resources if still needed.

```bash
aws autoscaling update-auto-scaling-group --auto-scaling-group-name wiki-asg-lab \
  --min-size 0 --desired-capacity 0
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names wiki-asg-lab \
  --query 'AutoScalingGroups[0].Instances'
# Run only after the instance list is empty.
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name wiki-asg-lab
aws ec2 delete-launch-template-versions --launch-template-name wiki-ec2-lab \
  --versions "$ASG_LAB_V1" "$ASG_LAB_V2" "$ASG_LAB_BAD"
```

## References

- [Auto Scaling overview](https://docs.aws.amazon.com/autoscaling/ec2/userguide/what-is-amazon-ec2-auto-scaling.html).
- [Instance refresh](https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html).
- [Lifecycle hooks](https://docs.aws.amazon.com/autoscaling/ec2/userguide/lifecycle-hooks.html).
- [Warm pools](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html).
