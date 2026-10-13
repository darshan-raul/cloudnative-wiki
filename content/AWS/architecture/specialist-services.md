---
title: Specialist AWS service selection
description: Distinguish optional authorization, directory, security-evidence, edge, desktop and media services before planning deeper specialist labs.
tags:
  - cloud/aws/architecture
date: 2026-10-12
---

# Specialist AWS service selection

These are optional workload branches after [[AWS/foundations/README|foundations]] and [[AWS/architecture/well-architected|architecture review]], not services every deployment must include. Start with a specific requirement and verify current eligibility/Region support before a paid lab.

## Identity and evidence

Verified Permissions externalizes **application** authorization with Cedar; it does not replace AWS IAM permission evaluation. Model principal/action/resource/context and test both allowed and forbidden application requests.

Directory Service supplies supported directory integrations/managed directory capabilities. An Active Directory dependency is different from simply needing [[AWS/security/iam/identity-center|workforce SSO]]; choose synchronization, DNS/network and recovery ownership explicitly.

Security Lake normalizes supported security data for downstream analysis; it is not a universal automatic incident-response system. Audit Manager collects/maps supported audit evidence; Artifact provides compliance reports/agreements. Neither establishes workload compliance without scoped controls and human assessment.

CloudHSM and Private CA address different requirements: hardware-backed key operations versus private certificate issuance. Compare operational key/certificate lifecycle, access, availability and cost with [[AWS/security/kms/README|KMS]] and [[AWS/security/certificate-manager/README|ACM/Private CA]].

## Data, devices and user workloads

[[AWS/analytics/opensearch/README|OpenSearch]] serverless/vector features need supported collection/index, encryption/network/data access and query-capacity design; “serverless” does not mean a zero-cost idle deployment.

IoT Core/Greengrass address supported device connectivity and edge execution. Separate device certificate/policy, topic permissions, fleet update and disconnected behavior from cloud IAM users. Do not recommend retired SageMaker Edge Manager as a current edge lab.

WorkSpaces serves supported virtual desktop requirements. Assess user/directory, network, images, endpoint access, session persistence and operating costs instead of treating it as a generic EC2 replacement.

MediaConvert batch transcoding and MediaLive live processing have different input, latency, redundancy and capacity requirements. For a test, use owned nonsensitive media and limit job/channel duration; live resources can continue billing after the client disconnects.

## Selection drill

Pick one specialist requirement and write the principal/data boundary, dependencies, supported deployment mode, price dimensions, acceptance test and cleanup inventory. Use its owning getting-started workflow in a sandbox only after those choices are approved. Explain why a core service is insufficient and one specialist alternative is unnecessary.

No optional specialist deployment is required to complete the core learning path.

## Owning references

- [Verified Permissions](https://docs.aws.amazon.com/verifiedpermissions/latest/userguide/what-is-avp.html).
- [Directory Service](https://docs.aws.amazon.com/directoryservice/latest/admin-guide/what_is.html).
- [Security Lake](https://docs.aws.amazon.com/security-lake/latest/userguide/what-is-security-lake.html).
- [Audit Manager](https://docs.aws.amazon.com/audit-manager/latest/userguide/what-is.html).
- [Artifact](https://docs.aws.amazon.com/artifact/latest/ug/what-is-aws-artifact.html).
- [CloudHSM](https://docs.aws.amazon.com/cloudhsm/latest/userguide/introduction.html).
- [IoT Core](https://docs.aws.amazon.com/iot/latest/developerguide/what-is-aws-iot.html).
- [Greengrass](https://docs.aws.amazon.com/greengrass/v2/developerguide/what-is-iot-greengrass.html).
- [WorkSpaces](https://docs.aws.amazon.com/workspaces/latest/adminguide/amazon-workspaces.html).
- [MediaConvert](https://docs.aws.amazon.com/mediaconvert/latest/ug/what-is.html).
- [MediaLive](https://docs.aws.amazon.com/medialive/latest/ug/what-is.html).
