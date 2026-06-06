---
title: AWS CLI
description: AWS CLI (Command Line Interface) — unified tool for interacting with all AWS services. Installation, configuration, profiles, autocomplete, and common workflows.
tags:
  - aws
  - management
  - cli
---

# AWS CLI

The AWS CLI is a unified command-line tool for managing all AWS services. It provides direct access to AWS APIs and is the backbone of most AWS automation, CI/CD pipelines, and scripting.

## Installation

```bash
# Linux/macOS
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscli.zip"
unzip awscli.zip
sudo ./aws/install

# macOS (Homebrew)
brew install awscli

# Verify
aws --version
```

## Configuration

```bash
aws configure
# AWS Access Key ID: AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Default region name: us-east-1
# Default output format: json
```

This creates `~/.aws/credentials` and `~/.aws/config`:

```
~/.aws/credentials:
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[profile dev]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

~/.aws/config:
[default]
region = us-east-1
output = json

[profile dev]
region = us-west-2
output = json
```

## Named Profiles

Use profiles for multiple accounts/regions:

```bash
# Use a profile
aws ec2 describe-instances --profile dev
aws ec2 describe-instances --profile prod

# Set default profile
export AWS_PROFILE=dev
```

## Common Commands by Service

### EC2

```bash
aws ec2 describe-instances
aws ec2 describe-vpcs
aws ec2 describe-subnets
aws ec2 run-instances --image-id ami-0abcdef1234567890 --instance-type t3.micro
aws ec2 terminate-instances --instance-ids i-xxxxx
aws ec2 describe-security-groups
```

### S3

```bash
aws s3 ls
aws s3 cp myfile.txt s3://my-bucket/
aws s3 sync ./local-dir s3://my-bucket/
aws s3 rm s3://my-bucket/myfile.txt
aws s3 ls s3://my-bucket/ --recursive
```

### IAM

```bash
aws iam list-users
aws iam create-role --role-name MyRole --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name MyRole --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
aws iam get-policy --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
```

### CloudFormation

```bash
aws cloudformation create-stack --stack-name my-vpc --template-body file://vpc.yaml
aws cloudformation describe-stacks --stack-name my-vpc
aws cloudformation update-stack --stack-name my-vpc --template-body file://vpc.yaml
aws cloudformation delete-stack --stack-name my-vpc
aws cloudformation list-stacks
```

### Lambda

```bash
aws lambda list-functions
aws lambda invoke --function-name my-function --payload '{"key":"value"}' output.txt
aws lambda get-function --function-name my-function
aws lambda update-function-code --function-name my-function --zip-file fileb://function.zip
```

### STS (Security Token Service)

```bash
# Get caller identity (verify credentials work)
aws sts get-caller-identity

# Assume a role
aws sts assume-role --role-arn arn:aws:iam::123456789012:role/MyRole --role-session-name MySession

# Get a session token (for MFA)
aws sts get-session-token --serial-number arn:aws:iam::123456789012:mfa/username
```

## Useful Flags

```bash
--query         # Filter output with JMESPath
--output        # json, text, table
--region        # Override default region
--profile       # Use specific credentials
--dry-run       # Validate without executing
--debug         # Show API calls (for debugging)
--no-paginate   # Don't auto-paginate (for scripts)
--page-size     # Custom page size for list operations
```

### Query Examples

```bash
# Get only instance IDs and state
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId, State.Name]'

# List all S3 bucket names
aws s3api list-buckets --query 'Buckets[].Name'

# Get VPC CIDR from VPC ID
aws ec2 describe-vpcs --vpc-ids vpc-xxxxx --query 'Vpcs[].CidrBlock'
```

## CLI Auto-Completion

```bash
# Bash
complete -C '/usr/local/bin/aws_completer' aws

# Zsh
autoload -U compinit
compinit
eval "$(register-python-argcomplete aws)"
```

## Pagination

The CLI auto-paginates large results. For scripts, use `--no-paginate`:

```bash
# Gets ALL instances (may take time, lots of API calls)
aws ec2 describe-instances --no-paginate > all-instances.txt

# Limit per page (faster, but may miss some)
aws ec2 describe-instances --page-size 100
```

## JSON Output and Parsing

```bash
# Get instance IPs
aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateIpAddress' --output text

# Get security group rules as JSON
aws ec2 describe-security-groups --group-id sg-xxxxx --output json

# jq for complex parsing
aws ec2 describe-instances | jq '.Reservations[].Instances[] | select(.State.Name=="running") | .InstanceId'
```

## AWS CLI v2 vs v1

AWS CLI v2 is the current version with improvements:
- **Session manager** plugin for connecting to EC2 without SSH
- **Automatic prompt** for missing parameters
- **Built-in credential caching**
- **SSO integration** with AWS IAM Identity Center

```bash
# Check version
aws --version
# aws-cli/2.15.0 Python/3.11.6
```

## Environment Variables

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1
export AWS_PROFILE=default
export AWS_CONFIG_FILE=~/.aws/config
export AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials
```

## Session Manager (SSM)

```bash
# Connect to EC2 without SSH (requires SSM Agent)
aws ssm start-session --target i-xxxxx

# With Session Manager plugin (no port 22 needed)
session-manager-plugin

# Copy files via Session Manager
aws ssm start-session --target i-xxxxx --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["22"],"localPortNumber":5000}'
```

## Troubleshooting

```bash
# Test credentials
aws sts get-caller-identity

# Check configuration
aws configure list

# Debug API calls
aws ec2 describe-instances --debug

# Validate IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/myuser \
  --action-names ec2:DescribeInstances \
  --resource-arns "*"
```

## References

- **Homepage:** https://aws.amazon.com/cli/
- **Documentation:** https://docs.aws.amazon.com/cli/
- **Pricing:** https://aws.amazon.com/cli/ (free)

## Pricing Examples

**Scenario 1:** A DevOps engineer running 50 AWS CLI commands per day as part of automated deployments. 50 × 365 = 18,250 CLI calls/month. The AWS CLI makes API calls — each API call costs money for some services (e.g., Lambda invoke costs $0.20/million after free tier). But for most services (EC2 describe, S3 list), CLI calls are covered by existing service charges. Total: $0/month for CLI itself.

**Scenario 2:** A CI/CD pipeline running `aws codepipeline start-pipeline-execution` 100 times/day to deploy applications. Pipeline runs 100/day × 30 = 3,000/month. Total: $0/month for the CLI itself. The pipeline also runs CloudFormation create-change-set and describe-stacks-api calls — all within free tier for most organizations.

## Nuggets & Gotchas

- **CLI credentials override instance profile credentials:** If you run `aws configure` on an EC2 instance that also has an instance profile, the CLI credentials (stored in `~/.aws/credentials`) take precedence. This is a common source of "why is my code using the wrong account?" issues.
- **`aws s3 sync` does not delete files by default:** `aws s3 sync ./local s3://bucket` only uploads new/changed files. To delete files in S3 that don't exist locally, add `--delete` flag. Without it, old files accumulate and cost money.
- **`--output text` strips quotes from strings — don't use it for file paths:** If a bucket name has special characters, `--output text` may strip quotes and cause issues in scripts. Use `--output json` for programmatic use.
- **CLI pagination can silently skip results if rate limited:** If the CLI hits a rate limit (e.g., 1000 calls/minute for some APIs), it retries but may not retry all pages correctly. For high-volume scripts, use `--max-items` and handle pagination manually with `--starting-token`.
- **`aws configure sso` requires SSO to be set up first:** If you run `aws configure sso` without having SSO configured in IAM Identity Center, it fails with an unclear error. Set up SSO first via the AWS SSO console.