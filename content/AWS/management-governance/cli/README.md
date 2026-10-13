---
title: "AWS CLI"
description: "The CLI exposes service APIs; a plausible-looking command is not evidence that an operation or field exists."
tags:
  - aws/management-governance
date: 2026-10-12
---

# AWS CLI

The CLI exposes service APIs; a plausible-looking command is not evidence that an operation or field exists. Start with [[AWS/security/iam/README|IAM]] and verify identity, Region and API contract before making changes.

## Installation and shell completion

Use the [official CLI v2 installation/update guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), selecting the current supported OS/architecture and signature-verification steps. Linux has x86-64/ARM installers (or the supported installation script); macOS uses the signed PKG workflow, and Windows uses MSI. AWS's supported Snap option auto-refreshes and is unsuitable when a team must pin a minor version. Do not assume an arbitrary distribution package or `pip install awscli` installs current CLI v2.

After installation, run `command -v aws` on Unix and `aws --version`; on Windows use `where.exe aws` plus `aws --version`. Resolve duplicate v1/v2 executables or PATH conflicts before configuring credentials. Installation is local setup, not evidence of AWS authorization.

Follow the [shell-specific completion guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-completion.html). Find `aws_completer` with `command -v aws_completer`, then use its actual executable path. In Bash, for example:

```bash
# Replace the example path with the discovered completer path.
complete -C '/usr/local/bin/aws_completer' aws
```

Zsh requires `bashcompinit`/`compinit` setup before the Bash-compatible `complete` registration; PowerShell has its own documented completion function/registration. Persist only the appropriate commands in the selected shell's profile after reviewing it. Start a new shell and type `aws s` followed by Tab: service choices should appear. Missing completion is a local shell/PATH issue, not an IAM denial. No installer or shell-profile change is run by this note.

## Credentials and profiles

Prefer IAM Identity Center/temporary credentials or workload roles over persistent access keys. The config file uses [profile dev], while the credentials file uses [dev]. They are different formats. Environment variables/explicit profiles and role credentials have precedence rules; confirm the effective caller instead of assuming the instance profile is used.

```bash
aws --version
aws configure list --profile dev
aws sts get-caller-identity --profile dev
```

These are read-only CLI v2 checks; output can include account/user details. Do not share tokens or credential files. Set the intended Region explicitly where appropriate and avoid credentials in shell history.

## Output, pagination and contracts

Use structured JSON plus JMESPath queries for reproducible inspection. --page-size changes per-service request size while the CLI can still retrieve all pages. --no-paginate retrieves only the first service page; it is not a way to get a complete unpaginated inventory. --no-cli-pager disables the display pager, not API pagination. --max-items and continuation tokens have a distinct client pagination purpose.

```bash
aws ec2 describe-instances --region us-east-1 --output json --no-cli-pager
aws ec2 describe-instances --generate-cli-skeleton input
```

The first call requires EC2 Describe permission; the second produces a local shape example and is not deployment validation. Skeleton stability is not guaranteed across CLI versions; consult owning operation documentation and service constraints.

JSON/YAML inputs must follow exact nesting/case/enums. Quoting and file inputs avoid ambiguous shell shorthand. For binary data, understand CLI v2 base64/fileb semantics; do not confuse JSON strings with API binary payloads.

## Safe inspection exercise

Use a least-privilege test profile. Compare a complete paginated inventory with --no-paginate on a service containing more than one page; record why the latter is incomplete. Validate a candidate input against its owning schema, then test an unauthorized read to observe AccessDenied.

For writes, resolve exact identifiers, review effects/costs and use supported dry-run where available—not every API supports it. Capture returned IDs for asynchronous polling and handle terminal failures/timeouts. Cleanup must use those validated sandbox IDs rather than broad globs/account-wide deletions.

## Profile file formats and credential precedence

These examples show syntax only; never add real long-lived keys to shared notes.

```ini
# ~/.aws/config
[profile dev]
region = us-east-1
output = json
```

```ini
# ~/.aws/credentials
[dev]
aws_access_key_id = EXAMPLE_NOT_A_REAL_KEY
aws_secret_access_key = EXAMPLE_NOT_A_REAL_SECRET
```

Prefer temporary/federated credentials or workload roles. Verify aws configure list and GetCallerIdentity for the actual invocation environment; explicit profile/environment settings can change which credential source is selected. The account/role ARN is sensitive operational metadata even when it is not a password.

## JMESPath and inventory walkthrough

```bash
aws ec2 describe-instances --profile dev --region us-east-1 \
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Type:InstanceType}' \
  --output json --no-cli-pager
```

This read-only query assumes authorization and intentionally returns a structured projection. It does not list every kind of compute or every Region. Empty results can mean wrong Region/filters, not absence of all account resources.

| Flag           | What it changes                     | Common mistake                                   |
| -------------- | ----------------------------------- | ------------------------------------------------ |
| --page-size    | Size of individual service requests | Assuming it limits total inventory               |
| --no-paginate  | Stops automatic page retrieval      | Treating first page as complete                  |
| --max-items    | Client output limit/token behavior  | Ignoring continuation token                      |
| --no-cli-pager | Terminal display paging             | Confusing it with API pagination                 |
| --query        | JMESPath result projection          | Assuming a projection is an authorization filter |

For multi-account/Region inventory, enumerate intended scope with permissions and continuation handling, record failures separately and avoid hiding AccessDenied as an empty list.

## Inputs, binary data and asynchronous operations

Use reviewed file:// JSON/YAML inputs for complex structures, preserving exact case/enums. Shell shorthand and quoting do not replace schema validation. Binary payloads need the selected CLI v2 base64/fileb behavior, not a string guessed from the console.

Generate-cli-skeleton is a local shape aid whose output can change by CLI release; it is not a live dry-run. Supported --dry-run operations verify some authorization/constraints but do not establish application functionality. Many APIs have no dry-run.

Capture returned operation/job IDs, poll with a deadline/backoff, inspect terminal errors and page results. Never pipe unreviewed inventories into account-wide deletion. Cleanup should resolve exact sandbox targets and preserve unrelated user resources.

## References

- [CLI configuration file formats](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
- [Credential precedence](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
- [Pagination](https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-pagination.html)
- [JMESPath output filtering](https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-filter.html)

## Across the wiki

- [[Linux/shell-scripting/README|Shell Scripting]] — command-line tooling (Linux)
- [[Kubernetes/guides/tools/kubectl|kubectl]] — command-line tooling (Kubernetes)
- [[Architecture/solution-architecture-concepts/data-architecture/databases/postgres/psql|psql]] — command-line tooling (Architecture)
- [[Linux/shell-scripting/bash-cheatsheet|Bash Scripting Cheatsheet]] — command-line tooling (Linux)
