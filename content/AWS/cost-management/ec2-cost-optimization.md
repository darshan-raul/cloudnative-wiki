---
title: EC2 Cost Optimization
description: EC2 cost optimization — right-sizing, Spot instances, mixed policies, Auto Scaling, Graviton, zombie resources, and Compute Optimizer
tags:
  - aws
  - cost-management
  - compute
---

# EC2 Cost Optimization

EC2 is the largest single cost line for most AWS workloads. Optimizing EC2 spend means understanding the relationship between instance types, purchasing models, scaling behavior, and actual resource utilization.

## Right-Sizing

The most common source of EC2 waste is over-provisioned instances — buying t3.xlarge when t3.large would handle the load. Right-sizing means matching instance capacity to actual workload requirements.

**How to identify over-sized instances:**
- CloudWatch metrics: `CPUUtilization`, `NetworkIn`, `NetworkOut`, `VolumeReadOps`
- Compute Optimizer: AWS's ML-based recommendation engine. It analyzes CloudWatch data and tells you "you're using 40% of your t3.xlarge, a t3.large would handle it"
- CloudWatch Contributor Insights: Top contributors to CPU across your fleet

**Typical over-size patterns:**
- Database servers with 32 vCPU because "we might need it" but running at 15% average
- Application servers with 64GB RAM because the team always spec'd it that way, actual usage is 20GB
- CI/CD agents that run 30 minutes of work then sit idle for 23.5 hours

**Right-sizing formula:**
```
Current: t3.xlarge (4 vCPU, 16GB) @ $0.192/hour
Target: t3.large (2 vCPU, 8GB) @ $0.096/hour
Savings: $0.096/hour × 24 × 30 = $69/month per instance
```

## Auto Scaling

Auto Scaling is the primary mechanism for matching EC2 capacity to demand. Three types:

**Target tracking:** Maintain a metric at a target value. Example: keep CPU at 50%. ASG automatically adds/removes instances to keep CPU at target.

**Step scaling:** Add/remove instances in steps based on alarm thresholds. More control than target tracking, less complexity than scheduled.

**Scheduled scaling:** Predictable patterns (Monday morning traffic spike, end-of-month batch job). Schedule scaling actions in advance.

**Predictive scaling (Compute Optimizer):** ML-based. Analyzes historical traffic patterns and schedules capacity before demand arrives. Good for consistent diurnal patterns.

**Mixed instance policies:** Combine On-Demand with Spot in a single ASG:
```json
{
  "InstanceDistribution": {
    "OnDemandPercentageAboveBaseThreshold": 20,
    "SpotAllocationStrategy": "capacity-optimized"
  }
}
```
- 20% of instances are On-Demand (covers baseline)
- 80% are Spot (covers bursty traffic)
- ASG launches Spot from the most available capacity pools

## Spot Instances

Spot can reduce EC2 cost by 60-90% vs On-Demand. The key is designing for interruption.

**Interruption handling options:**
- `terminate` — shut down, lose state
- `stop` — stop, resume later (persistent capacity in capacity-optimized pools)
- `hibernate` — write memory to EBS root volume, stop, resume with state intact

**Spot Fleet vs ASG:** ASG with Spot mixed instances is the modern approach. Spot Fleet is older — useful for batch workloads that don't need ASG features.

**Capacity-optimized allocation:** ASG uses `capacity-optimized` to automatically pick the pools with most capacity available, reducing interruption frequency.

**Use cases for Spot:**
- Batch processing (Hadoop, Spark, ML training)
- CI/CD build agents
- Web servers behind a load balancer that can tolerate 2-minute interruption
- Stateless microservices

**Avoid for:**
- Databases
- Anything with state that can't be restored quickly
- Workloads requiring guaranteed availability

## Graviton (ARM)

AWS Graviton3 processors deliver better price-performance than Intel/AMD for many workloads:
- ~20% better performance per dollar for web servers
- ~40% better performance per dollar for distributed databases
- Lower power consumption, better perf/watt

**Requirements:**
- Application must support ARM64 (most modern compiled languages do: Go, Rust, Node.js, Python, Java)
- AMI must be ARM64 (not all vendor AMIs have ARM variants)
- Some instance types only available as Graviton (M7g, C7g, R7g)

**Migration path:** Start with new workloads on Graviton. For existing workloads, re-platform gradually. Many teams run dual-architecture AMIs and route traffic based on performance results.

## Reserved Instance Strategy for EC2

**Baseline + Burst pattern:**
```
Baseline: 40 x m6i.large covered by 3-year All-Upfront RI @ $0.096/hour = $3.84/hour
Burst: Up to 100 instances covered by On-Demand/Spot @ $0.144/hour = $8.64/hour
Total capacity: 40 baseline + 60 burst = 100 instances
```

This covers always-on baseline at maximum discount, handles bursts with On-Demand/Spot, and avoids over-buying RIs for variable load.

## Zombie Resources

Resources that exist but are no longer used, still costing money:

**EC2 instances:**
- Development instances left running on weekends
- Old test environments after project completion
- `stopped` instances retain EBS volumes — still charged
- Failed ASG instances that didn't terminate cleanly

**EBS volumes:**
- Unattached volumes (orphaned after instance termination)
- Old snapshots from deleted instances
- AMIs not cleaned up after instance type changes

**Detection:** `aws ec2 describe-instances --filter "Name=instance-state-name,Values=running"` and look for instances with old launch times that should have been terminated.

AWS Instance Scheduler solution (AWS Solutions) automates stopping/starting instances on schedules using CloudWatch Events + Lambda.

## Compute Optimizer

AWS Compute Optimizer analyzes CloudWatch metrics and recommends:
- Right-sizing (instance type downgrades/upgrades)
- Memory utilization (for instances with CloudWatch detailed monitoring)
- Auto Scaling group recommendations

Recommendations come with confidence scores. High confidence = good data. Low confidence = not enough history.

**Limitation:** Compute Optimizer doesn't account for your RI/SP commitments — it just recommends based on current utilization. You still need to decide whether to act on recommendations given your existing commitments.

## References

- **Homepage:** https://aws.amazon.com/ec2/cost-optimization/
- **Documentation:** https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html
- **Pricing:** https://aws.amazon.com/ec2/cost-optimization/

## Pricing Examples

**Scenario 1:** A production workload running 12 m5.2xlarge instances (32 vCPU, 128GB RAM each). Compute Optimizer analysis shows actual average CPU is 18% and memory is 45%. Recommendation: downsize to m5.xlarge (16 vCPU, 64GB). Annual savings: 12 × ($0.384 - $0.192) × 24 × 365 = $20,000/year. After RI purchase for the right-sized instances: ~$15,000/year net savings.

**Scenario 2:** An auto scaling group for a web application has a minimum of 4 instances and maximum of 20. Compute Optimizer recommends the current m5.large instances are appropriately sized but the ASG's max count is 3x higher than needed (actual peak is 8 instances). Reducing max from 20 to 10 prevents runaway scaling during load tests. Estimated savings from preventing over-scaling: ~$3,500/month during peak testing periods.

## Nuggets & Gotchas

- **Compute Optimizer recommendations are not automatic:** You can enable auto-scaling recommendations but the actual instance changes still need to be initiated by you. There's no auto-apply without explicit opt-in.
- **Right-sizing doesn't account for RI/SP commitment overlap:** If you downsize from m5.2xlarge to m5.xlarge and you have existing RIs for m5.2xlarge, you may be paying for capacity you're no longer using while also paying for the new smaller instances. Plan the transition carefully.
- **Memory metrics require CloudWatch detailed monitoring (paid):** By default, EC2 sends basic metrics (CPU, network) every 5 minutes. Memory and disk metrics require the CloudWatch Agent installed and detailed monitoring enabled ($0.015/instance/hour).
- **Compute Optimizer has a 14-day lookback minimum:** Recommendations are based on at least 14 days of utilization data. During the first two weeks of a new deployment, you won't get recommendations.
- **ASG recommendations assume the current launch template is fixed:** It recommends instance types that are compatible with your current launch template. If you want to switch to Graviton, you need to update the launch template first.