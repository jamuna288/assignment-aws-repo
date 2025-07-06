# Terraform Infrastructure for Agent CI/CD Pipeline

This directory contains Terraform configuration files to deploy the complete infrastructure for the agent CI/CD pipeline.

## 🏗️ Infrastructure Components

The Terraform configuration creates:

- **VPC and Networking**: Custom VPC with public subnet and internet gateway
- **EC2 Instance**: Ubuntu 20.04 instance with agent application
- **Security Groups**: Properly configured firewall rules
- **IAM Roles**: Least privilege access for EC2 and GitHub Actions
- **S3 Bucket**: Encrypted storage for deployment artifacts
- **Application Load Balancer**: High availability and health checks
- **CloudWatch**: Logging, monitoring, and alarms
- **Auto-scaling ready**: Foundation for horizontal scaling

## 🚀 Quick Start

### Prerequisites

1. **Install Terraform** (>= 1.0):
   ```bash
   # macOS
   brew install terraform
   
   # Linux
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. **Configure AWS CLI**:
   ```bash
   aws configure
   ```

3. **Create EC2 Key Pair**:
   ```bash
   aws ec2 create-key-pair --key-name agent-key --query 'KeyMaterial' --output text > ~/.ssh/agent-key.pem
   chmod 400 ~/.ssh/agent-key.pem
   ```

### One-Command Deployment

```bash
./setup-terraform.sh
```

This interactive script will:
- Validate prerequisites
- Collect configuration parameters
- Create `terraform.tfvars`
- Initialize, plan, and apply Terraform
- Generate GitHub secrets template
- Test the deployment

### Manual Deployment

1. **Copy and customize variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Plan deployment**:
   ```bash
   terraform plan
   ```

4. **Apply configuration**:
   ```bash
   terraform apply
   ```

5. **Get outputs**:
   ```bash
   terraform output
   ```

## 📋 Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for resources | `us-east-1` | No |
| `environment` | Environment name | `production` | No |
| `instance_type` | EC2 instance type | `t3.micro` | No |
| `key_pair_name` | EC2 Key Pair name | - | Yes |
| `allowed_cidr` | CIDR for access | `0.0.0.0/0` | No |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` | No |
| `public_subnet_cidr` | Public subnet CIDR | `10.0.1.0/24` | No |
| `enable_monitoring` | Enable detailed monitoring | `true` | No |
| `enable_cloudwatch_logs` | Enable CloudWatch logs | `true` | No |

## 📤 Outputs

After deployment, Terraform provides:

| Output | Description |
|--------|-------------|
| `instance_id` | EC2 instance ID |
| `instance_public_ip` | Public IP address |
| `instance_public_dns` | Public DNS name |
| `load_balancer_dns` | ALB DNS name |
| `deployment_bucket_name` | S3 bucket name |
| `application_url` | Direct application URL |
| `api_documentation_url` | API docs URL |
| `github_secrets` | GitHub secrets configuration |

## 🔒 Security Features

### Network Security
- Custom VPC with controlled access
- Security groups with minimal required ports
- Public subnet for web access only
- Private communication between components

### Access Control
- IAM roles with least privilege principle
- Instance profile for EC2 permissions
- Separate policies for different access levels
- No hardcoded credentials

### Data Protection
- Encrypted S3 bucket for deployments
- Encrypted EBS volumes
- Secure communication channels
- Audit logging enabled

## 📊 Monitoring and Logging

### CloudWatch Integration
- Application logs: `/aws/ec2/agent/application`
- Error logs: `/aws/ec2/agent/error`
- Nginx logs: `/aws/ec2/agent/nginx-*`
- Deployment logs: `/aws/ssm/deployment-logs`

### Metrics and Alarms
- CPU utilization monitoring
- Memory usage tracking
- Disk space monitoring
- Network performance metrics
- Custom application metrics

### Health Checks
- ALB health checks on `/docs` endpoint
- Instance status checks
- Service availability monitoring
- Automated recovery actions

## 🔧 Customization

### Instance Configuration

To modify the EC2 instance setup, edit `user-data.sh`:

```bash
# Add custom packages
apt-get install -y your-package

# Configure additional services
systemctl enable your-service

# Set environment variables
echo "CUSTOM_VAR=value" >> /etc/environment
```

### Security Hardening

Additional security measures can be added:

```hcl
# In main.tf, add to security group
resource "aws_security_group_rule" "custom_rule" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.agent.id
}
```

### Scaling Configuration

For auto-scaling, add:

```hcl
resource "aws_launch_template" "agent" {
  name_prefix   = "${var.environment}-agent-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name
  
  vpc_security_group_ids = [aws_security_group.agent.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  
  user_data = local.user_data
}

resource "aws_autoscaling_group" "agent" {
  name                = "${var.environment}-agent-asg"
  vpc_zone_identifier = [aws_subnet.public.id]
  target_group_arns   = [aws_lb_target_group.agent.arn]
  health_check_type   = "ELB"
  
  min_size         = 1
  max_size         = 3
  desired_capacity = 1
  
  launch_template {
    id      = aws_launch_template.agent.id
    version = "$Latest"
  }
}
```

## 🧪 Testing

### Infrastructure Testing

Test the deployed infrastructure:

```bash
# From repository root
./test-pipeline.sh
```

### Manual Testing

```bash
# SSH to instance
ssh -i ~/.ssh/your-key.pem ubuntu@$(terraform output -raw instance_public_ip)

# Check services
sudo systemctl status agent-service nginx

# Test application
curl http://localhost:8000/docs
```

### Load Testing

```bash
# Install Apache Bench
sudo apt-get install apache2-utils

# Run load test
ab -n 1000 -c 10 http://$(terraform output -raw instance_public_ip)/
```

## 🔄 Updates and Maintenance

### Updating Infrastructure

```bash
# Modify terraform files
# Plan changes
terraform plan

# Apply updates
terraform apply
```

### Rolling Updates

For zero-downtime updates:

1. Create new instance with updated configuration
2. Update load balancer to include new instance
3. Drain traffic from old instance
4. Terminate old instance

### Backup and Recovery

```bash
# Create AMI backup
aws ec2 create-image \
  --instance-id $(terraform output -raw instance_id) \
  --name "agent-backup-$(date +%Y%m%d)" \
  --description "Agent application backup"

# Backup Terraform state
aws s3 cp terraform.tfstate s3://your-backup-bucket/terraform-state/
```

## 💰 Cost Optimization

### Instance Right-Sizing

Monitor and adjust instance types:

```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$(terraform output -raw instance_id) \
  --start-time $(date -u -d '1 week ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average
```

### Resource Cleanup

```bash
# Remove unused resources
terraform destroy

# Clean up S3 bucket contents
aws s3 rm s3://$(terraform output -raw deployment_bucket_name) --recursive
```

## 🆘 Troubleshooting

### Common Issues

1. **Terraform Init Fails**:
   ```bash
   # Clear cache and retry
   rm -rf .terraform
   terraform init
   ```

2. **Instance Not Accessible**:
   ```bash
   # Check security group
   aws ec2 describe-security-groups --group-ids $(terraform output -raw security_group_id)
   
   # Check instance status
   aws ec2 describe-instance-status --instance-ids $(terraform output -raw instance_id)
   ```

3. **User Data Script Fails**:
   ```bash
   # Check user data logs
   ssh -i ~/.ssh/your-key.pem ubuntu@$(terraform output -raw instance_public_ip)
   sudo tail -f /var/log/user-data.log
   ```

4. **State Lock Issues**:
   ```bash
   # Force unlock (use carefully)
   terraform force-unlock LOCK_ID
   ```

### Debug Commands

```bash
# Terraform debug mode
export TF_LOG=DEBUG
terraform apply

# AWS CLI debug
aws ec2 describe-instances --debug

# Check Terraform state
terraform show
terraform state list
```

## 📚 Additional Resources

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)

## 🤝 Contributing

When modifying Terraform configurations:

1. Test changes in a separate environment first
2. Use `terraform plan` to review changes
3. Update documentation for new variables/outputs
4. Test with the pipeline testing script
5. Update version constraints as needed
