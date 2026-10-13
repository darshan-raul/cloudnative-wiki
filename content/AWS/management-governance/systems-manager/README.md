---
title: "AWS Systems Manager"
description: "Systems Manager operates supported managed nodes across EC2 and hybrid environments."
tags:
  - aws/management-governance
date: 2026-10-12
---

# AWS Systems Manager

Systems Manager operates supported managed nodes across EC2 and hybrid environments. Agent installation alone is not enrollment: nodes need a supported SSM Agent, instance/activation role and reachable service endpoints. Prerequisites: [[AWS/security/iam/README|IAM]], [[AWS/networking/README|networking]] and [[AWS/management-governance/cli/README|CLI]].

## Fleet operations and sessions

Run Command executes documents on targeted nodes with configured MaxConcurrency and MaxErrors; default concurrency is 50, not a universal one-hundred-execution ceiling. Specify absolute/percentage limits and account for partial failures. State Manager maintains associations; Inventory collects supported metadata. Automation provides runbooks with roles/approval/error handling.

Session Manager avoids routine inbound SSH/RDP exposure but still requires authorized identities, node connectivity and audit configuration. Ordinary session content can use configured logging; SSH and port-forwarding sessions do not provide tunnel-content logging. CloudTrail API records are not a transcript of tunneled traffic.

Parameter Store offers hierarchical configuration and SecureString where appropriate. KMS decryption, parameter access and logging policies matter; retrieving a parameter is not permission to print it into a shared log.

## Hybrid and patch contracts

Hybrid CreateActivation requires an IAM role and uses expiration-date, not expiration-in-seconds. Treat activation code/ID as sensitive enrollment material. As of June 30, 2026 AWS removed Advanced Instances Tier/registration charges; after the transition, September 30 hybrid Session Manager pricing is \$0.05/session and Run Command \$0.002/invocation. EC2 and hybrid pricing differ; service integrations may add charges.

[[AWS/management-governance/systems-manager/patch-manager|Patch Manager]] uses OS-specific baselines or Quick Setup patch policies. Approval rules contain PatchRules; an Amazon Linux 2 baseline cannot be labelled an AL2023 product. RegisterPatchBaselineForPatchGroup maps a baseline to a patch group; setting a default baseline is not that mapping.

## Read-only command exercise

Use one disposable managed node and a restricted operator role. Verify enrollment, then execute a read-only document with explicitly bounded concurrency/errors:

```bash
aws ssm describe-instance-information
aws ssm send-command --instance-ids i-0123456789abcdef0 \
  --document-name AWS-RunShellScript \
  --parameters '{"commands":["uname -s"]}' \
  --max-concurrency 1 --max-errors 0
```

The command requires an authorized Linux sandbox node and permissions; record its returned CommandId and inspect invocation/output until a terminal status, with a timeout. Deny a second operator to verify authorization. For sessions, test the configured log destination and explicitly document tunnel-content limitations.

Remove sandbox associations/activations/nodes, parameters and created log outputs according to retention. Do not disable production agents/roles. Budget node compute, hybrid invocations/sessions and charged supporting services separately.

## Managed-node architecture and prerequisites

```text
Operator identity → authorized SSM API/document
  → service command/session
  → managed node agent + role + endpoint connectivity
  → invocation/output/audit evidence
```

EC2 node roles and hybrid activation roles establish the managed-node identity. Nodes need supported OS/agent, DNS/time/network and outbound service endpoint access; opening inbound SSH is not an SSM prerequisite. Private environments may use supported VPC endpoints with appropriate security groups/policies. An installed agent with missing identity/connectivity is not a healthy managed node.

## Run Command, State Manager and Automation

| Capability      | Work                                    | Failure/control boundary                                 |
| --------------- | --------------------------------------- | -------------------------------------------------------- |
| Run Command     | Execute a supported document on targets | Invocation status, bounded concurrency/errors and output |
| State Manager   | Maintain associations/configuration     | Targeting, schedule, compliance and association errors   |
| Automation      | Multi-step operational runbook          | Execution role, approvals, branch/retry/failure behavior |
| Inventory       | Collect supported metadata              | Collection configuration and freshness                   |
| Session Manager | Authorized interactive/tunnel access    | Session policy, identity/connectivity and logging limits |

Create custom documents with actual schema/runtime and validate on one node before fleet rollout. Tag targets can include more machines than intended; inspect resolved target scope. A successful SendCommand response means submission, not successful execution on every target.

## Session, parameter and hybrid workflows

For a normal session, verify plugin/client requirements, least-privilege session actions and the configured S3/CloudWatch log destination. Port forwarding/SSH tunnels do not provide content transcripts; CloudTrail API evidence is not their payload audit. Terminate sessions and remove temporary access deliberately.

Parameter Store paths support structured configuration; SecureString needs decryption authority. Store/retrieve only intended parameters and avoid outputting values in shared command logs. Secrets rotation/backend credentials may call for a different service/workflow.

For hybrid enrollment, create an activation with a real role, registration limit and expiration-date, register the supported agent using protected activation material, then verify ManagedNode status. Revoke unused activations and decommission test registrations without disrupting production nodes. Current operation-based hybrid pricing replaced the old per-managed-instance tier.

## Invocation and evidence walkthrough

1. Verify the exact managed-node identity/OS and operator permissions.
2. Submit a harmless read-only command to one disposable node.
3. Capture CommandId and inspect per-node invocation status/output with a timeout.
4. Compare success, failed/undeliverable/timed-out states explicitly.
5. Verify concurrency/error controls before moving to a canary group.
6. Retain required audit output and remove only sandbox associations/nodes/resources.

Use [[AWS/management-governance/systems-manager/patch-manager|Patch Manager's fleet plan]] for OS baselines, canaries, reboot and package-level reporting. Do not run broad shell updates merely to prove SSM connectivity.

## Worked command submission versus completion

Use the Linux node from the read-only exercise, with a supported online agent, node role/endpoints and an operator permitted to use AWS-RunShellScript **only on that sandbox node**. Set SSM_LAB_INSTANCE_ID to its verified managed-node ID. Python/Boto3 uses temporary credentials in that node's Region. This sends `uname -s`, not a fleet update:

```python
import os
import time
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

ssm = boto3.client("ssm", config=Config(
    connect_timeout=5, read_timeout=10,
    retries={"mode": "standard", "total_max_attempts": 2},
))
node_id = os.environ["SSM_LAB_INSTANCE_ID"]
command_id = ssm.send_command(
    InstanceIds=[node_id], DocumentName="AWS-RunShellScript",
    Parameters={"commands": ["uname -s"]},
    MaxConcurrency="1", MaxErrors="0", TimeoutSeconds=60,
)["Command"]["CommandId"]
deadline = time.monotonic() + 180
while time.monotonic() < deadline:
    try:
        invocation = ssm.get_command_invocation(CommandId=command_id, InstanceId=node_id)
    except ClientError as error:
        if error.response["Error"]["Code"] != "InvocationDoesNotExist":
            raise
        time.sleep(3)  # Submission/invocation visibility is eventually consistent.
        continue
    if invocation["Status"] == "Success":
        assert invocation["ResponseCode"] == 0
        assert invocation["StandardOutputContent"].strip() == "Linux"
        print(command_id, "Success: Linux")
        break
    if invocation["Status"] in {"Failed", "Cancelled", "TimedOut"}:
        raise RuntimeError((command_id, invocation["StatusDetails"], invocation["ResponseCode"]))
    time.sleep(3)
else:
    raise TimeoutError(f"Inspect invocation {command_id} on {node_id}; do not report success")
```

Expected: CommandId at submission, possibly Pending/InProgress, then successful invocation with exit code zero and Linux. A sandbox operator lacking SendCommand permission must receive AccessDenied. An offline node can instead become undeliverable/delivery-timed-out; report that result rather than an empty output as success. TimeoutSeconds controls delivery eligibility, not a general shell execution deadline; for longer custom documents also configure the document's supported execution timeout. Inspect this exact invocation without repeating the operation:

```bash
aws ssm get-command-invocation \
  --command-id "${SSM_LAB_COMMAND_ID:?}" \
  --instance-id "${SSM_LAB_INSTANCE_ID:?}" \
  --query '{Status:Status,Details:StatusDetails,Exit:ResponseCode,Output:StandardOutputContent}'
```

Set SSM_LAB_COMMAND_ID to the returned ID. This query is suitable because the command prints only a nonsensitive OS label; do not reuse the output projection for commands containing secrets. [GetCommandInvocation status/consistency](https://docs.aws.amazon.com/cli/latest/reference/ssm/get-command-invocation.html), [SendCommand delivery timeout](https://docs.aws.amazon.com/systems-manager/latest/APIReference/API_SendCommand.html).

## A scoped interactive session and synthetic SecureString

Install the [Session Manager CLI plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html), confirm StartSession permission for this node/document and review the approved normal-shell logging configuration/destination. Start an ordinary session, enter `uname -s`, then `exit`:

```bash
aws ssm start-session --target "${SSM_LAB_INSTANCE_ID:?}"
```

Record its SessionId and verify the configured S3/CloudWatch transcript plus the API audit event. If the client disconnects without ending it, terminate only that returned session ID with `aws ssm terminate-session --session-id ...`. This normal-shell evidence does not extend to SSH/port-forward tunnel contents. Preserve required logs; do not turn off shared audit configuration for cleanup.

For Parameter Store, use a dedicated customer-managed symmetric KMS key and a lab role allowed to PutParameter/GetParameter/DeleteParameter on the lab prefix plus applicable key encrypt/decrypt authorization. Set SSM_LAB_KMS_KEY_ARN to that verified key. The following creates a unique synthetic value, checks decrypted data **without printing it**, and deletes that exact parameter:

```python
import uuid

parameter_name = "/cloudnative-wiki/ssm-lab/" + uuid.uuid4().hex
synthetic_value = "synthetic-not-a-password"
ssm.put_parameter(Name=parameter_name, Type="SecureString", Value=synthetic_value,
                  KeyId=os.environ["SSM_LAB_KMS_KEY_ARN"], Overwrite=False)
try:
    result = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
    assert result["Parameter"]["Value"] == synthetic_value
    print(parameter_name, "decrypted synthetic value verified")
finally:
    ssm.delete_parameter(Name=parameter_name)
```

Before deletion, a separate identity denied parameter read or KMS decrypt should fail the respective operation; distinguish these two policy layers. If running that negative experiment manually, defer the final cleanup until its evidence is recorded. This is configuration storage, not password rotation. Remove only dedicated node/role/key/log resources if they were created for this exercise and are no longer needed; do not deregister shared managed nodes. [PutParameter](https://docs.aws.amazon.com/systems-manager/latest/APIReference/API_PutParameter.html), [GetParameter decryption](https://docs.aws.amazon.com/systems-manager/latest/APIReference/API_GetParameter.html).

## References

- [Managed-node prerequisites](https://docs.aws.amazon.com/systems-manager/latest/userguide/managed-node-prerequisites.html)
- [Run Command controls](https://docs.aws.amazon.com/systems-manager/latest/userguide/send-commands-multiple.html)
- [Session logging limitations](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html)
- [CreateActivation contract](https://docs.aws.amazon.com/cli/latest/reference/ssm/create-activation.html)
- [Current Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/)

## Across the wiki

- [[Linux/ssh/ssh-config|SSH Config and Tricks]] — remote access (Linux)
- [[Kubernetes/eks/security/access/endpoint-access|Cluster Endpoint Access]] — remote access (Kubernetes)
- [[Kubernetes/concepts/L08-operations/02-kubectl-debug|kubectl Debug Toolkit]] — remote access (Kubernetes)
