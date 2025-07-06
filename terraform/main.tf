terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "agent-cicd"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current" {}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-agent-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-agent-igw"
  }
}

# Public Subnet 1
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-agent-public-subnet-1"
    Type = "public"
  }
}

# Public Subnet 2 (required for ALB)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-agent-public-subnet-2"
    Type = "public"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.environment}-agent-public-rt"
  }
}

# Route Table Association 1
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# Route Table Association 2
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "agent" {
  name_prefix = "${var.environment}-agent-sg"
  vpc_id      = aws_vpc.main.id
  description = "Security group for agent application"

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # HTTP access
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # HTTPS access
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Application port (for direct access during testing)
  ingress {
    description = "Application"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # All outbound traffic
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-agent-sg"
  }
}

# S3 Bucket for deployments
resource "aws_s3_bucket" "deployments" {
  bucket = "${var.environment}-agent-deployments-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.environment}-agent-deployments"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deployments" {
  bucket = aws_s3_bucket.deployments.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "deployments" {
  bucket = aws_s3_bucket.deployments.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "deployments" {
  bucket = aws_s3_bucket.deployments.id

  rule {
    id     = "delete_old_deployments"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "${var.environment}-agent-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-agent-ec2-role"
  }
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.environment}-agent-s3-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.deployments.arn,
          "${aws_s3_bucket.deployments.arn}/*"
        ]
      }
    ]
  })
}

# Attach managed policies to EC2 role
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.environment}-agent-instance-profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    Name = "${var.environment}-agent-instance-profile"
  }
}

# User Data Script
locals {
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    environment        = var.environment
    deployment_bucket  = aws_s3_bucket.deployments.bucket
    aws_region        = var.aws_region
  }))
}

# EC2 Instance
resource "aws_instance" "agent" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.agent.id]
  subnet_id             = aws_subnet.public_1.id
  iam_instance_profile  = aws_iam_instance_profile.ec2_profile.name

  user_data = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name        = "${var.environment}-agent-instance"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_lb" "agent" {
  name               = "${var.environment}-agent-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.agent.id]
  subnets           = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  enable_deletion_protection = false

  tags = {
    Name = "${var.environment}-agent-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "agent" {
  name     = "${var.environment}-agent-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/docs"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.environment}-agent-tg"
  }
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "agent" {
  target_group_arn = aws_lb_target_group.agent.arn
  target_id        = aws_instance.agent.id
  port             = 80
}

# Load Balancer Listener
resource "aws_lb_listener" "agent" {
  load_balancer_arn = aws_lb.agent.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    
    forward {
      target_group {
        arn = aws_lb_target_group.agent.arn
      }
    }
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/ec2/agent/application"
  retention_in_days = 14

  tags = {
    Name = "${var.environment}-agent-app-logs"
  }
}

resource "aws_cloudwatch_log_group" "error" {
  name              = "/aws/ec2/agent/error"
  retention_in_days = 14

  tags = {
    Name = "${var.environment}-agent-error-logs"
  }
}

resource "aws_cloudwatch_log_group" "deployment" {
  name              = "/aws/ssm/deployment-logs"
  retention_in_days = 7

  tags = {
    Name = "${var.environment}-deployment-logs"
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.environment}-agent-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"

  dimensions = {
    InstanceId = aws_instance.agent.id
  }

  tags = {
    Name = "${var.environment}-agent-high-cpu-alarm"
  }
}
