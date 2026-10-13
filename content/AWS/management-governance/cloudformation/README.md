---
title: "AWS CloudFormation"
description: "CloudFormation manages resource lifecycle from declarative YAML/JSON templates."
tags:
  - aws/management-governance
date: 2026-10-12
---

# AWS CloudFormation

CloudFormation manages resource lifecycle from declarative YAML/JSON templates. A stack is a lifecycle unit, not a guarantee that every change is nondisruptive. Prerequisites: [[AWS/security/iam/README|IAM]], [[AWS/management-governance/cli/README|CLI]] and networking for network templates.

## Template and ownership

Resources, Parameters, Outputs, Conditions and intrinsic functions describe desired infrastructure. A template with one subnet and no route/IGW cannot truthfully claim separate public and private subnets. A nested stack's outputs are available through GetAtt NestedStack.Outputs.OutputName; imports of existing resources require the supported resource-import workflow, not merely Ref or If.

DeletionPolicy and UpdateReplacePolicy control supported retention/replacement behavior. Retained resources remain yours to govern/pay for; stack deletion does not certify complete cleanup. Stack policies restrict resource-update actions, not concurrency locks.

## Changes, drift and StackSets

Review change sets before execution; resource replacement can still cause downtime/data impact. A change set requires a name. Drift detection returns an ID used to poll status, not a stack name:

```bash
aws cloudformation create-change-set --stack-name sandbox-stack \
  --change-set-name reviewed-update --change-set-type UPDATE \
  --template-body file://sandbox.yaml
aws cloudformation detect-stack-drift --stack-name sandbox-stack
aws cloudformation describe-stack-drift-detection-status \
  --stack-drift-detection-id example-returned-detection-id
```

These commands require an existing stack, valid template, permissions and actual returned ID. Additional parameters/capabilities may be required by the template. Creating a change set does not execute it.

StackSets use self-managed administration/execution roles or service-managed Organizations trusted access/delegation. AWS RAM is not their setup permission path. Plan regions/accounts, operation preferences, failures and rollback independently from ordinary single-account stacks.

## Safe lifecycle exercise

Use a budgeted disposable stack with one small resource and explicit outputs. Validate the template, create the stack and inspect events/outputs. Propose a benign update, review a named change set and execute only after identifying replacement/security implications.

Introduce a reversible sandbox drift and detect it, checking supported resource/property coverage. An unauthorized deployment role should fail. Restore declared state or deliberately import/retain according to the documented workflow; drift detection itself does not automatically repair resources.

Delete the test stack, verify events and inspect retained/externally created resources, log/artifact buckets and role dependencies. Never delete production data merely because a template's name contains sandbox.

## Complete public/private subnet teaching template

This isolated template defines a public route to an internet gateway and an isolated private route table. It does not create EC2/NAT endpoints, promise private internet egress or implement an application security model.

Replace nonoverlapping CIDRs/Region assumptions and review the template before deploying into an authorized sandbox. The public subnet does not automatically assign public IPs.

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: Disposable two-subnet network teaching example
Resources:
  Vpc:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.42.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true
  InternetGateway:
    Type: AWS::EC2::InternetGateway
  GatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref Vpc
      InternetGatewayId: !Ref InternetGateway
  PublicSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref Vpc
      CidrBlock: 10.42.1.0/24
      AvailabilityZone: !Select [0, !GetAZs ""]
      MapPublicIpOnLaunch: false
  PrivateSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref Vpc
      CidrBlock: 10.42.2.0/24
      AvailabilityZone: !Select [0, !GetAZs ""]
      MapPublicIpOnLaunch: false
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref Vpc
  PublicDefaultRoute:
    Type: AWS::EC2::Route
    DependsOn: GatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway
  PublicAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet
      RouteTableId: !Ref PublicRouteTable
  PrivateRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref Vpc
  PrivateAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnet
      RouteTableId: !Ref PrivateRouteTable
Outputs:
  VpcId:
    Value: !Ref Vpc
  PublicSubnetId:
    Value: !Ref PublicSubnet
  PrivateSubnetId:
    Value: !Ref PrivateSubnet
```

Inspect routing after creation: public subnet routing alone does not give an instance a public address, and private subnet has no NAT route. Adding NAT is a separate billable/availability decision, not implied by this template.

## Template functions, nested stacks and imports

| Construct       | Meaning                                | Caveat                                              |
| --------------- | -------------------------------------- | --------------------------------------------------- |
| Ref             | Supported resource/parameter reference | Returned value is resource-specific                 |
| GetAtt          | Supported resource attribute           | Nested outputs use NestedStack.Outputs.OutputName   |
| Sub/Join        | Construct strings                      | Preserve escaping and actual resource identifiers   |
| If/Conditions   | Include/select declared configuration  | Does not adopt an existing external resource        |
| ImportValue     | Reference supported exported values    | Cross-stack dependencies constrain updates/deletion |
| Resource import | Adopt supported existing resources     | Required identifiers/template and drift validation  |

## Lifecycle and cross-account rollout

Validate, create a named change set, review replacements/security, execute intentionally, then inspect stack events and outputs. A failed update can leave retained/external resources and requires understanding rollback state. Stack policy restricts updates; it is not a deployment concurrency lock.

StackSets distribute supported templates through self-managed roles or service-managed Organizations trusted access. Choose targets/Regions and bounded operation preferences, review partial failures and avoid assuming one account success means every target succeeded.

DeletionPolicy/UpdateReplacePolicy and retained resources are explicit durability/cost decisions. Deleting a stack is not proof its data/log buckets or imported resources disappeared. Verify only disposable resources are removed after the exercise.

## References

- [Change-set CLI contract](https://docs.aws.amazon.com/cli/latest/reference/cloudformation/create-change-set.html)
- [Drift-status contract](https://docs.aws.amazon.com/cli/latest/reference/cloudformation/describe-stack-drift-detection-status.html)
- [Nested stacks](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html)
- [Resource import](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/resource-import.html)
- [StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-concepts.html)

## Across the wiki

- [[DevOps/infrastructure-as-code/README|Infrastructure as Code]] — infrastructure as code (DevOps)
- [[Kubernetes/eks/automation/control-planes/ack|AWS Controllers for Kubernetes (ACK)]] — infrastructure as code (Kubernetes)
- [[DevOps/devsecops/stage2-build/10-iac-security|M10: Infrastructure-as-Code Security]] — infrastructure as code (DevOps)
- [[Kubernetes/eks/getting-started/cluster-creation|Cluster Creation]] — infrastructure as code (Kubernetes)
