variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "t3.large"], var.instance_type)
    error_message = "Instance type must be one of: t3.micro, t3.small, t3.medium, t3.large."
  }
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access"
  type        = string
}

variable "allowed_cidr" {
  description = "CIDR block allowed to access the application"
  type        = string
  default     = "0.0.0.0/0"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for first public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for second public subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "enable_monitoring" {
  description = "Enable detailed monitoring for EC2 instance"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs"
  type        = bool
  default     = true
}
