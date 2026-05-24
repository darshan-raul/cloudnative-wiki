# Wazuh Production Infrastructure — Terraform
# Resources: NLB, EC2s (manager, indexer, dashboard), IAM, EBS, Security Groups
# Provider: AWS us-east-1 (adjust for multi-region)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================
# VARIABLES — fill these in via terraform.tfvars or env
# ============================================================
variable "aws_region" {
  description = "AWS region for Wazuh infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "security_account_id" {
  description = "Account ID where Wazuh infrastructure lives (Account A)"
  type        = string
  default     = "444444444444"  # REPLACE WITH YOUR ACTUAL ACCOUNT
}

variable "vpc_id" {
  description = "VPC ID for Wazuh nodes"
  type        = string
  default     = "vpc-abc123def"  # REPLACE
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Wazuh nodes (3 for indexer cluster)"
  type        = list(string)
  default     = ["subnet-abc123", "subnet-def456", "subnet-ghi789"]  # REPLACE
}

variable "agent_sg_id" {
  description = "Security group ID that agents will use to connect to manager NLB"
  type        = string
  default     = "sg-agent-comm"  # REPLACE
}

variable "keycloak_fqdn" {
  description = "Keycloak internal FQDN for OIDC"
  type        = string
  default     = "keycloak.internal.yourdomain.com"
}

variable "wazuh_fqdn" {
  description = "Wazuh dashboard FQDN"
  type        = string
  default     = "wazuh.internal.yourdomain.com"
}

# ============================================================
# DATA SOURCES
# ============================================================
data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# ============================================================
# KEY PAIR (for EC2 access — replace with your key)
# ============================================================
data "aws_key_pair" "deploy" {
  key_name = "wazuh-deploy-key"  # REPLACE with your key pair name
}

# ============================================================
# IAM — Wazuh Manager Instance Profile
# ============================================================
resource "aws_iam_role" "wazuh_manager_role" {
  name = "WazuhManagerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = "production"
    Application = "wazuh"
  }
}

resource "aws_iam_role_policy" "wazuh_manager_cross_org" {
  name = "WazuhManagerCrossOrgRead"
  role = aws_iam_role.wazuh_manager_role.id

  # Allow assuming roles in ALL org accounts — update with your actual org accounts
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::111111111111:role/WazuhCrossAccountRead",
          "arn:aws:iam::222222222222:role/WazuhCrossAccountRead",
          "arn:aws:iam::333333333333:role/WazuhCrossAccountRead"
          # ADD ALL YOUR ORG ACCOUNT IDs HERE
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.security_account_id}:secret:wazuh/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "wazuh_manager_profile" {
  name = "WazuhManagerInstanceProfile"
  role = aws_iam_role.wazuh_manager_role.name
}

# ============================================================
# SECURITY GROUPS
# ============================================================

# Manager SG — agents connect here via NLB
resource "aws_security_group" "wazuh_manager" {
  name        = "wazuh-manager-sg"
  description = "Wazuh manager — agent communication + API access"
  vpc_id      = var.vpc_id

  ingress = [
    # Agent → Manager (via NLB TCP 1514/1515)
    { description = "Agent communication TCP 1514", from_port = 1514, to_port = 1514, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    # Agent enrollment TCP 1515
    { description = "Agent enrollment TCP 1515", from_port = 1515, to_port = 1515, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    # Agentless syslog UDP 514
    { description = "Syslog UDP 514", from_port = 514, to_port = 514, protocol = "udp", cidr_blocks = ["0.0.0.0/0"] },
    # Wazuh API TCP 55000 (restrict to dashboard subnet in production)
    { description = "Wazuh API TCP 55000", from_port = 55000, to_port = 55000, protocol = "tcp", cidr_blocks = ["10.0.0.0/8"] },
    # SSH 22 (from jump host only — restrict further in production)
    { description = "SSH TCP 22", from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["10.0.0.0/16"] },
  ]

  egress = [
    { description = "All outbound", from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] },
  ]

  tags = { Name = "wazuh-manager-sg", Environment = "production" }
}

# Indexer SG — manager + dashboard only
resource "aws_security_group" "wazuh_indexer" {
  name        = "wazuh-indexer-sg"
  description = "Wazuh indexer — inter-node + dashboard access only"
  vpc_id      = var.vpc_id

  ingress = [
    # Inter-indexer communication
    { description = "Indexing cluster 9200-9300", from_port = 9200, to_port = 9300, protocol = "tcp", cidr_blocks = ["10.0.0.0/8"] },
    # From manager
    { description = "Manager to indexer 9200", from_port = 9200, to_port = 9200, protocol = "tcp", cidr_blocks = ["10.0.0.0/8"] },
    # From dashboard
    { description = "Dashboard to indexer 9200", from_port = 9200, to_port = 9200, protocol = "tcp", cidr_blocks = ["10.0.0.0/8"] },
  ]

  egress = [
    { description = "All outbound", from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] },
  ]

  tags = { Name = "wazuh-indexer-sg", Environment = "production" }
}

# Dashboard SG — HTTPS only from corporate
resource "aws_security_group" "wazuh_dashboard" {
  name        = "wazuh-dashboard-sg"
  description = "Wazuh dashboard — HTTPS from corporate network"
  vpc_id      = var.vpc_id

  ingress = [
    # HTTPS 443 from corporate
    { description = "HTTPS TCP 443", from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["10.0.0.0/8"] },
    # HTTP 80 redirect
    { description = "HTTP TCP 80", from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["10.0.0.0/8"] },
  ]

  egress = [
    { description = "All outbound", from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] },
  ]

  tags = { Name = "wazuh-dashboard-sg", Environment = "production" }
}

# ============================================================
# NETWORK LOAD BALANCER — Agent Communication
# ============================================================
resource "aws_lb" "wazuh_agent_nlb" {
  name               = "wazuh-agent-nlb"
  type               = "network"
  scheme             = "internal"
  subnets            = var.private_subnet_ids
  enable_cross_zone_load_balancing = true

  tags = { Name = "wazuh-agent-nlb", Environment = "production" }
}

# Target group for agent communication TCP 1514
resource "aws_lb_target_group" "agents_1514" {
  name     = "wazuh-agents-1514"
  port     = 1514
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 5
  }
}

# Target group for agent enrollment TCP 1515
resource "aws_lb_target_group" "agents_1515" {
  name     = "wazuh-agents-1515"
  port     = 1515
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 5
  }
}

# TCP 1514 listener
resource "aws_lb_listener" "agents_1514" {
  load_balancer_arn = aws_lb.wazuh_agent_nlb.arn
  port              = 1514
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents_1514.arn
  }
}

# TCP 1515 listener
resource "aws_lb_listener" "agents_1515" {
  load_balancer_arn = aws_lb.wazuh_agent_nlb.arn
  port              = 1515
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agents_1515.arn
  }
}

# ============================================================
# MANAGER NODES (2 for HA active-active)
# ============================================================
resource "aws_instance" "wazuh_manager" {
  count = 2

  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2023 — REPLACE with your region's AL2023 AMI
  instance_type = "t3.large"
  subnet_id     = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  key_name      = data.aws_key_pair.deploy.key_name

  iam_instance_profile = aws_iam_instance_profile.wazuh_manager_profile.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  vpc_security_group_ids = [aws_security_group.wazuh_manager.id]

  user_data = templatefile("${path.module}/userdata-manager.tpl", {
    manager_number = count.index + 1
    cluster_key    = "REPLACE_WITH_32_CHAR_CLUSTER_KEY"
    indexer_hosts  = join(",", [for i in range(3) : "10.0.1.${30 + i}:9200"])  # placeholder IPs
  })

  tags = {
    Name        = "wazuh-manager-${count.index + 1}"
    Environment = "production"
    Application = "wazuh"
    Component   = "manager"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Register managers with NLB target groups
resource "aws_lb_target_group_attachment" "manager_1514" {
  count = 2

  target_group_arn = aws_lb_target_group.agents_1514.arn
  target_id        = aws_instance.wazuh_manager[count.index].id
  port             = 1514
}

resource "aws_lb_target_group_attachment" "manager_1515" {
  count = 2

  target_group_arn = aws_lb_target_group.agents_1515.arn
  target_id        = aws_instance.wazuh_manager[count.index].id
  port             = 1515
}

# ============================================================
# INDEXER NODES (3-node cluster)
# ============================================================
resource "aws_instance" "wazuh_indexer" {
  count = 3

  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2023
  instance_type = "t3.xlarge"
  subnet_id     = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  key_name      = data.aws_key_pair.deploy.key_name

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    iops        = 3000
    encrypted   = true
  }

  vpc_security_group_ids = [aws_security_group.wazuh_indexer.id]

  user_data = templatefile("${path.module}/userdata-indexer.tpl", {
    node_number = count.index + 1
    node_name   = "indexer-${count.index + 1}"
    cluster_hosts = join(",", [for i in range(3) : "10.0.1.${30 + i}"])
  })

  tags = {
    Name        = "wazuh-indexer-${count.index + 1}"
    Environment = "production"
    Application = "wazuh"
    Component   = "indexer"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# DASHBOARD NODE
# ============================================================
resource "aws_instance" "wazuh_dashboard" {
  count = 1

  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2023
  instance_type = "t3.large"
  subnet_id     = var.private_subnet_ids[0]
  key_name      = data.aws_key_pair.deploy.key_name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  vpc_security_group_ids = [aws_security_group.wazuh_dashboard.id]

  user_data = templatefile("${path.module}/userdata-dashboard.tpl", {
    indexer_hosts = join(",", [for i in range(3) : "10.0.1.${30 + i}:9200"])
    wazuh_fqdn   = var.wazuh_fqdn
  })

  tags = {
    Name        = "wazuh-dashboard-1"
    Environment = "production"
    Application = "wazuh"
    Component   = "dashboard"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# OUTPUTS — for reference and automation
# ============================================================
output "manager_nlb_dns" {
  description = "NLB DNS name for agent configuration"
  value       = aws_lb.wazuh_agent_nlb.dns_name
}

output "manager_private_ips" {
  description = "Manager node private IPs"
  value       = [for m in aws_instance.wazuh_manager : m.private_ip]
}

output "indexer_private_ips" {
  description = "Indexer node private IPs"
  value       = [for i in aws_instance.wazuh_indexer : i.private_ip]
}

output "dashboard_private_ip" {
  description = "Dashboard node private IP"
  value       = aws_instance.wazuh_dashboard[0].private_ip
}

output "manager_role_arn" {
  description = "Manager IAM role ARN for cross-account policies"
  value       = aws_iam_role.wazuh_manager_role.arn
}