---
title: Organization guardrails and resource sharing
description: Test permission ceilings and RAM shares without conflating organization membership, delegated access and workload authorization.
tags:
  - cloud/aws/management-governance
date: 2026-10-12
---

# Organization guardrails and resource sharing

Start with [[AWS/management-governance/organizations/README|Organizations]], [[AWS/security/iam/policy-evaluation|policy evaluation]] and [[AWS/management-governance/organizations/delegated-admin|delegation]].

## Guardrail decisions

An SCP limits affected member principals; it does not grant IAM access. Allow-list paths and explicit denies have different reasoning. Management-account and service-linked-role exceptions matter when testing.

RCPs constrain supported resource access with their own scope; they are not renamed SCPs or replacements for every resource policy. IAM, trust, session, endpoint and KMS policies still matter. OU placement does not grant access between accounts.

Log/archive ownership, account vending and deployment authority are separate decisions. Trusted service access and supported delegated administration are not blanket authority over every member resource.

## RAM producer/consumer model

RAM shares supported resource types with supported principals/organization recipients. Owner resources remain owner-managed; consumers gain the specified supported use, not control over every configuration.

With Organizations sharing enabled, eligible organization recipients do not universally accept invitations. External shares have different invitation/resource constraints. Sharing TGW does not create attachments/routes; sharing a Resolver rule does not establish on-premises DNS/network prerequisites.

## Two-account sandbox drill

Prerequisites: approved owner/consumer sandbox accounts, a disposable supported Resolver rule or TGW, scoped RAM/service permissions, budget and an emergency administration path. Do not modify production root policies.

1. Record owner, intended consumer, share permission and allowed use.
2. Create a dedicated share limited to that consumer/OU and follow the applicable invitation/organization flow.
3. Verify supported consumer use and denial of owner-only changes.
4. Apply one narrow sandbox guardrail restriction with reviewed rollback. Test an allowed and a denied operation from the actual member role.
5. Inspect audit evidence and explain the policy/resource/network boundary responsible.
6. Restore the sandbox guardrail; detach/delete only the test share after removing consumer dependencies. Preserve owner resources unless they were solely lab resources.

Account closure and removing organization-wide protections are not routine cleanup. Share deletion does not prove every consumer-created resource vanished.

## Worked share: one TGW, one consumer attachment, one SCP deny

Use two approved **member** sandbox accounts in the same organization and Region, with RAM organization sharing already enabled and SCPs enabled. The owner creates a dedicated TGW; the consumer supplies a dedicated VPC and two subnets in different AZs. There are **no traffic routes** in this exercise: successfully creating/accepting an attachment demonstrates permitted consumer use, not VPC-to-VPC connectivity. Do not connect a production VPC. Budget TGW/attachment and supporting network charges.

Configure temporary profiles `ram-lab-owner`, `ram-lab-consumer` and `ram-lab-org-admin`. The third is the narrowly authorized organization administrator used only for the test policy attachment/rollback. Review its emergency rollback path, preserve existing SCP attachments and verify an available policy slot on the **consumer account**, not the organization root. Owner/consumer roles need the relevant RAM/EC2/describe/tag/service-linked-role actions; the consumer's identity policy must permit deletion of its lab attachment so the SCP denial can be distinguished from a pre-existing IAM denial.

Set RAM_LAB_REGION, RAM_LAB_VPC_ID, RAM_LAB_SUBNET_A and RAM_LAB_SUBNET_B to the consumer resources. Inspect `aws ram list-permissions --profile ram-lab-owner --region ... --resource-type ec2:TransitGateway` and set RAM_LAB_PERMISSION_ARN to the AWS-managed **AWSRAMDefaultPermissionTransitGateway** ARN actually returned. Inspect that permission before sharing; it permits supported consumer use, not owner TGW administration.

Run these Python cells in one session with Boto3 installed:

```python
import json
import os
import time
import uuid
import boto3
from botocore.exceptions import ClientError

region = os.environ["RAM_LAB_REGION"]
owner_session = boto3.Session(profile_name="ram-lab-owner", region_name=region)
consumer_session = boto3.Session(profile_name="ram-lab-consumer", region_name=region)
owner = owner_session.client("ec2")
consumer = consumer_session.client("ec2")
ram = owner_session.client("ram")
consumer_account = consumer_session.client("sts").get_caller_identity()["Account"]
owner_account = owner_session.client("sts").get_caller_identity()["Account"]
assert consumer_account != owner_account
subnet_ids = [os.environ["RAM_LAB_SUBNET_A"], os.environ["RAM_LAB_SUBNET_B"]]
subnets = consumer.describe_subnets(SubnetIds=subnet_ids)["Subnets"]
assert len(subnets) == 2 and len({s["AvailabilityZone"] for s in subnets}) == 2
assert all(s["VpcId"] == os.environ["RAM_LAB_VPC_ID"] for s in subnets)

def wait_resource(fetch, success_states):
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        result = fetch()
        if result["State"] in success_states:
            return result
        if result["State"] in {"failed", "rejected", "deleted"}:
            raise RuntimeError(result)
        time.sleep(5)
    raise TimeoutError("Inspect captured resource IDs and state; no blind duplicate create")

tgw = owner.create_transit_gateway(
    Description="cloudnative-wiki RAM sandbox",
    Options={"AutoAcceptSharedAttachments": "disable",
             "DefaultRouteTableAssociation": "disable",
             "DefaultRouteTablePropagation": "disable"},
    TagSpecifications=[{"ResourceType": "transit-gateway",
                        "Tags": [{"Key": "Purpose", "Value": "wiki-ram-lab"}]}],
)["TransitGateway"]
tgw_id = tgw["TransitGatewayId"]
wait_resource(lambda: owner.describe_transit_gateways(
    TransitGatewayIds=[tgw_id])["TransitGateways"][0], {"available"})
share_arn = ram.create_resource_share(
    name="wiki-tgw-lab-" + uuid.uuid4().hex[:8],
    resourceArns=[tgw["TransitGatewayArn"]], principals=[consumer_account],
    allowExternalPrincipals=False, permissionArns=[os.environ["RAM_LAB_PERMISSION_ARN"]],
    clientToken=str(uuid.uuid4()),
)["resourceShare"]["resourceShareArn"]
print(tgw_id, share_arn, consumer_account)
```

Wait until the consumer sees the shared TGW using DescribeTransitGateways before proceeding; sharing propagation is not instantaneous. In this enabled same-organization case there is no external-share invitation to accept. If it remains absent, inspect organization sharing, share association status and actual principal/Region rather than broadening recipients.

```python
attachment = consumer.create_transit_gateway_vpc_attachment(
    TransitGatewayId=tgw_id, VpcId=os.environ["RAM_LAB_VPC_ID"], SubnetIds=subnet_ids,
    TagSpecifications=[{"ResourceType": "transit-gateway-attachment",
                        "Tags": [{"Key": "Purpose", "Value": "wiki-ram-lab"}]}],
)["TransitGatewayVpcAttachment"]
attachment_id = attachment["TransitGatewayAttachmentId"]
fetch_attachment = lambda: owner.describe_transit_gateway_vpc_attachments(
    TransitGatewayAttachmentIds=[attachment_id])["TransitGatewayVpcAttachments"][0]
wait_resource(fetch_attachment, {"pendingAcceptance"})
owner.accept_transit_gateway_vpc_attachment(TransitGatewayAttachmentId=attachment_id)
wait_resource(fetch_attachment, {"available"})
print(attachment_id, "accepted by owner; no routes installed")

def delete_permission_probe():
    try:
        consumer.delete_transit_gateway_vpc_attachment(
            TransitGatewayAttachmentId=attachment_id, DryRun=True)
    except ClientError as error:
        code = error.response["Error"]["Code"]
        if code in {"DryRunOperation", "UnauthorizedOperation"}:
            return code
        raise
    raise RuntimeError("Expected EC2 dry-run response")

assert delete_permission_probe() == "DryRunOperation", "Resolve baseline IAM denial first"
```

DryRunOperation is an error-shaped response meaning permission is allowed **without deletion**. The TGW owner should still own its configuration. Test `consumer.modify_transit_gateway(TransitGatewayId=tgw_id, Options={"DnsSupport":"disable"}, DryRun=True)` with a role whose identity permissions allow the attempted action; expect UnauthorizedOperation because sharing does not transfer owner administration. Keep DryRun=True—do not change the TGW to prove the boundary.

The narrow SCP denies deletion of **this attachment only**, using the action's supported `ec2:transitGatewayAttachmentId` condition key. This avoids guessing an attachment resource ARN from either the TGW-owner or VPC-owner account. Resource `*` here is constrained by that exact attachment ID; it is not an account-wide deletion deny.

```python
org = boto3.Session(profile_name="ram-lab-org-admin", region_name=region).client("organizations")
policy = {
    "Version": "2012-10-17",
    "Statement": [{"Sid": "ProtectOnlyTheLabAttachment", "Effect": "Deny",
                   "Action": "ec2:DeleteTransitGatewayVpcAttachment",
                   "Resource": "*",
                   "Condition": {"StringEquals": {
                       "ec2:transitGatewayAttachmentId": attachment_id}}}],
}
print(json.dumps(policy, indent=2))  # Review this exact account/Region/resource first.
```

After review, create and attach only the dedicated policy:

```python
policy_id = org.create_policy(
    Content=json.dumps(policy), Name="wiki-ram-lab-" + uuid.uuid4().hex[:8],
    Description="Sandbox attachment deletion ceiling", Type="SERVICE_CONTROL_POLICY",
)["Policy"]["PolicySummary"]["Id"]
org.attach_policy(PolicyId=policy_id, TargetId=consumer_account)
deadline = time.monotonic() + 180
while time.monotonic() < deadline:
    if delete_permission_probe() == "UnauthorizedOperation":
        break
    time.sleep(3)
else:
    raise TimeoutError("SCP not observed; inspect attachment ID/condition and policy path")
print("SCP denies deletion; describe remains allowed")
print(consumer.describe_transit_gateway_vpc_attachments(
    TransitGatewayAttachmentIds=[attachment_id])["TransitGatewayVpcAttachments"][0]["State"])
```

Expected: describe still returns available, while deletion dry-run changes from DryRunOperation to UnauthorizedOperation with unchanged identity permissions. Keep API/CloudTrail evidence, current attachment/policy IDs and timestamps; an error code alone does not identify every policy layer. SCPs constrain the consumer role, do not grant the share, and do not constrain the management account or service-linked roles.

Rollback through the approved organization administrator: detach **policy_id only** from consumer_account, confirm dry-run becomes allowed again after propagation, then delete that test policy. Actual cleanup is now permitted: delete attachment_id from the consumer, wait until that exact attachment is deleted/absent, delete share_arn from the owner with RAM DeleteResourceShare, then delete tgw_id. Inspect asynchronous deletion and retained dependencies; remove only dedicated VPC/subnets/roles if no longer needed. Do not remove pre-existing SCPs, close accounts, disable organization sharing or delete shared network resources.

[TGW sharing and ownership](https://docs.aws.amazon.com/vpc/latest/tgw/working-with-transit-gateways.html), [RAM share request](https://docs.aws.amazon.com/cli/latest/reference/ram/create-resource-share.html), [EC2 attachment creation](https://docs.aws.amazon.com/cli/latest/reference/ec2/create-transit-gateway-vpc-attachment.html), [deletion dry-run](https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-transit-gateway-vpc-attachment.html), [attachment action/resource authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html).

## References

- [SCP evaluation](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_evaluation.html).
- [RCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html).
- [RAM sharing model](https://docs.aws.amazon.com/ram/latest/userguide/what-is.html).
- [Sharing/invitations](https://docs.aws.amazon.com/ram/latest/userguide/working-with-shared-invitations.html).
- [RAM permissions](https://docs.aws.amazon.com/ram/latest/userguide/permissions.html).
