# 🚀 Agent CI/CD Pipeline

**Automated CI/CD pipeline for deploying agents from GitHub to AWS EC2 with enterprise-grade security and monitoring.**

[![Deploy Status](https://img.shields.io/badge/deploy-success-brightgreen)](http://54.221.105.106)
[![Infrastructure](https://img.shields.io/badge/infrastructure-terraform-blue)](./terraform/)
[![Security](https://img.shields.io/badge/security-hardened-green)](./scripts/security-setup.sh)
[![Monitoring](https://img.shields.io/badge/monitoring-cloudwatch-orange)](https://console.aws.amazon.com/cloudwatch/)

## 📋 Table of Contents

- [🎯 Overview](#-overview)
- [🏗️ Architecture](#️-architecture)
- [🚀 Quick Start](#-quick-start)
- [📁 Project Structure](#-project-structure)
- [🔧 Local Development](#-local-development)
- [🚀 Deployment Options](#-deployment-options)
- [🔒 Security Features](#-security-features)
- [📊 Monitoring & Logging](#-monitoring--logging)
- [🧪 Testing](#-testing)
- [🛠️ Configuration](#️-configuration)
- [📚 API Documentation](#-api-documentation)
- [🔧 Troubleshooting](#-troubleshooting)
- [📈 Scaling](#-scaling)
- [🤝 Contributing](#-contributing)

## 🎯 Overview

This project provides a complete CI/CD pipeline solution for deploying intelligent agents to AWS infrastructure. It includes:

- **Automated Infrastructure**: Terraform-managed AWS resources
- **Secure Deployments**: GitHub Actions with AWS SSM
- **Production Ready**: Load balancing, monitoring, and logging
- **Security First**: IAM roles, encrypted storage, network security
- **Scalable Architecture**: Ready for horizontal scaling

### 🌟 Key Features

- ✅ **One-command deployment** with Terraform
- ✅ **GitHub Actions CI/CD** with automated testing
- ✅ **Zero-downtime deployments** via AWS SSM
- ✅ **Enterprise security** with least-privilege IAM
- ✅ **Comprehensive monitoring** with CloudWatch
- ✅ **Load balancing** with Application Load Balancer
- ✅ **Automated testing** and health checks
- ✅ **Docker support** for local development

## 🏗️ Architecture

```mermaid
graph TB
    A[GitHub Repository] --> B[GitHub Actions]
    B --> C[Build & Test]
    C --> D[S3 Deployment Bucket]
    D --> E[AWS SSM]
    E --> F[EC2 Instance]
    F --> G[Application Load Balancer]
    G --> H[Users]
    
    F --> I[CloudWatch Logs]
    F --> J[CloudWatch Metrics]
    
    subgraph "AWS Infrastructure"
        K[VPC]
        L[Security Groups]
        M[IAM Roles]
        N[S3 Bucket]
        O[CloudWatch]
    end
```

### 🔧 Components

| Component | Purpose | Technology |
|-----------|---------|------------|
| **GitHub Actions** | CI/CD Pipeline | YAML Workflows |
| **AWS EC2** | Application Runtime | Ubuntu 22.04 |
| **AWS S3** | Deployment Artifacts | Encrypted Storage |
| **AWS SSM** | Secure Deployment | Systems Manager |
| **AWS ALB** | Load Balancing | Application Load Balancer |
| **CloudWatch** | Monitoring & Logs | AWS CloudWatch |
| **Terraform** | Infrastructure as Code | HashiCorp Terraform |
| **FastAPI** | Agent Application | Python Framework |

## 🚀 Quick Start

### Prerequisites

- AWS Account with appropriate permissions
- AWS CLI installed and configured
- Terraform >= 1.0
- Git repository access
- EC2 Key Pair in your target region

### Option 1: Terraform Deployment (Recommended)

```bash
# Clone the repository
git clone <your-repo-url>
cd assignment-aws-repo

# Deploy infrastructure
cd terraform
./setup-terraform.sh
```

**What this does:**
- 🏗️ Creates complete AWS infrastructure
- 🔐 Sets up security groups and IAM roles
- 📊 Configures monitoring and logging
- 📝 Generates GitHub secrets template
- ✅ Tests the deployment

### Option 2: CloudFormation Deployment

```bash
# Deploy using CloudFormation
./setup.sh
```

### Option 3: Manual Setup

Follow the comprehensive [Deployment Guide](DEPLOYMENT_GUIDE.md) for step-by-step instructions.

## 📁 Project Structure

```
assignment-aws-repo/
├── 📁 .github/workflows/          # GitHub Actions CI/CD
│   └── deploy.yml                 # Main deployment workflow
├── 📁 Sample_Agent/               # Agent application code
│   ├── 📁 agent/                  # Core agent logic
│   │   ├── agentf.py             # Main agent function
│   │   ├── llm.py                # Language model integration
│   │   └── tools.py              # Agent tools and utilities
│   ├── 📁 tests/                  # Unit and integration tests
│   │   ├── __init__.py
│   │   └── test_main.py          # API endpoint tests
│   ├── main.py                   # FastAPI application
│   ├── requirements.txt          # Python dependencies
│   ├── Dockerfile               # Container configuration
│   └── startup.sh               # Application startup script
├── 📁 terraform/                  # Infrastructure as Code
│   ├── main.tf                   # Main Terraform configuration
│   ├── variables.tf              # Input variables
│   ├── outputs.tf                # Output values
│   ├── user-data.sh              # EC2 initialization script
│   ├── terraform.tfvars.example  # Example variables
│   ├── setup-terraform.sh        # Automated setup script
│   └── README.md                 # Terraform documentation
├── 📁 infrastructure/             # Alternative deployment methods
│   ├── cloudformation-template.yml # CloudFormation template
│   └── setup-ec2.sh             # EC2 setup script
├── 📁 scripts/                    # Utility scripts
│   ├── deploy.sh                 # Manual deployment
│   └── security-setup.sh         # Security hardening
├── 📁 docs/                       # Documentation
│   └── api/                      # API documentation
├── docker-compose.yml            # Local development setup
├── nginx.conf                    # Nginx configuration
├── test-pipeline.sh              # Pipeline testing script
├── setup.sh                     # Main setup script
├── DEPLOYMENT_GUIDE.md           # Comprehensive deployment guide
├── github-secrets.txt            # GitHub secrets template
└── README.md                     # This file
```

## 🔧 Local Development

### Using Docker (Recommended)

```bash
# Start the development environment
docker-compose up --build

# Access the application
open http://localhost:8000/docs
```

### Direct Python Development

```bash
cd Sample_Agent

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run the application
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Development URLs

- **Application**: http://localhost:8000
- **API Documentation**: http://localhost:8000/docs
- **Interactive API**: http://localhost:8000/redoc

## 🚀 Deployment Options

### 1. Automated Deployment (GitHub Actions)

**Trigger**: Push to `main` branch

```bash
git add .
git commit -m "Deploy new agent version"
git push origin main
```

**Pipeline Steps**:
1. 🧪 **Test**: Run unit tests and linting
2. 📦 **Build**: Create deployment package
3. ⬆️ **Upload**: Store artifacts in S3
4. 🚀 **Deploy**: Deploy via AWS SSM
5. ✅ **Verify**: Health checks and validation

### 2. Manual Deployment

```bash
# Deploy to production
./scripts/deploy.sh production i-1234567890abcdef0

# Deploy to staging
./scripts/deploy.sh staging i-0987654321fedcba0
```

### 3. Infrastructure Updates

```bash
# Update infrastructure
cd terraform
terraform plan
terraform apply

# Destroy infrastructure (careful!)
terraform destroy
```

## 🔒 Security Features

### 🛡️ Network Security
- ✅ **Custom VPC** with controlled access
- ✅ **Security Groups** with minimal required ports
- ✅ **Private Subnets** for sensitive components
- ✅ **WAF Integration** ready (optional)

### 🔐 Access Control
- ✅ **IAM Roles** with least privilege principle
- ✅ **Instance Profiles** for EC2 permissions
- ✅ **SSH Key-based** authentication only
- ✅ **SSM Session Manager** for secure access

### 🔒 Data Protection
- ✅ **Encrypted S3** storage for deployments
- ✅ **Encrypted EBS** volumes
- ✅ **TLS/SSL** ready configuration
- ✅ **Secrets Management** via AWS SSM

### 🚨 Security Monitoring
- ✅ **Fail2ban** intrusion prevention
- ✅ **UFW Firewall** configuration
- ✅ **File Integrity** monitoring
- ✅ **Audit Logging** enabled
- ✅ **Security Alerts** and notifications

### 🔧 Security Hardening

```bash
# Run security hardening on EC2 instance
ssh -i ~/.ssh/your-key.pem ubuntu@your-instance-ip
sudo ./scripts/security-setup.sh
```

## 📊 Monitoring & Logging

### 📈 CloudWatch Integration

**Log Groups**:
- `/aws/ec2/agent/application` - Application logs
- `/aws/ec2/agent/error` - Error logs
- `/aws/ec2/agent/nginx-access` - Nginx access logs
- `/aws/ec2/agent/nginx-error` - Nginx error logs
- `/aws/ssm/deployment-logs` - Deployment logs

**Metrics & Alarms**:
- 🖥️ **CPU Utilization** monitoring
- 💾 **Memory Usage** tracking
- 💿 **Disk Space** monitoring
- 🌐 **Network Performance** metrics
- 🎯 **Custom Application** metrics

### 📊 Dashboards

Access your monitoring dashboards:
- **CloudWatch Dashboard**: [AWS Console](https://console.aws.amazon.com/cloudwatch/)
- **Application Metrics**: Custom namespace `Agent/Application`
- **Infrastructure Metrics**: Standard AWS/EC2 namespace

### 🚨 Alerting

**Configured Alarms**:
- High CPU utilization (>80%)
- Low disk space (<20%)
- Application errors (>5/min)
- Failed deployments

## 🧪 Testing

### Unit Tests

```bash
cd Sample_Agent
pip install pytest pytest-asyncio httpx
python -m pytest tests/ -v
```

### Integration Tests

```bash
# Test the entire pipeline
./test-pipeline.sh
```

### Load Testing

```bash
# Install Apache Bench
sudo apt-get install apache2-utils

# Run load test
ab -n 1000 -c 10 http://your-instance-ip/recommendation
```

### API Testing

```bash
# Test recommendation endpoint
curl -X POST "http://your-instance-ip/recommendation" \
     -H "Content-Type: application/json" \
     -d '{"input_text": "My flight is delayed"}'
```

## 🛠️ Configuration

### GitHub Secrets

Add these secrets to your GitHub repository:

| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | GitHub Actions AWS access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | GitHub Actions AWS secret key | `wJalrXUt...` |
| `AWS_REGION` | Target AWS region | `us-east-1` |
| `EC2_INSTANCE_ID` | Target EC2 instance ID | `i-1234567890abcdef0` |
| `S3_DEPLOYMENT_BUCKET` | S3 bucket for deployments | `prod-agent-deployments-123456789` |
| `ENVIRONMENT` | Environment tag | `production` |

### Environment Variables

**Application Configuration**:
```bash
# Set in your deployment environment
export ENVIRONMENT=production
export AWS_REGION=us-east-1
export LOG_LEVEL=INFO
```

**Terraform Variables**:
```hcl
# terraform/terraform.tfvars
aws_region = "us-east-1"
environment = "production"
instance_type = "t3.micro"
key_pair_name = "your-key-pair"
allowed_cidr = "0.0.0.0/0"
```

## 📚 API Documentation

### 🔗 Endpoints

Once deployed, access the interactive API documentation:

- **Swagger UI**: `http://your-instance-ip/docs`
- **ReDoc**: `http://your-instance-ip/redoc`

### 📝 API Reference

#### POST `/recommendation`

Get intelligent agent recommendations for flight-related queries.

**Request Body**:
```json
{
  "input_text": "My flight is delayed by 3 hours"
}
```

**Response**:
```json
{
  "response": {
    "message": "We sincerely apologize for the flight delay. Here are your options:",
    "recommendations": [
      "Check with gate agent for updated departure time",
      "Consider rebooking on next available flight",
      "Request meal vouchers if delay exceeds 3 hours",
      "Contact customer service for accommodation if overnight delay"
    ],
    "passenger_message": "We understand your frustration and are working to get you to your destination as quickly as possible."
  }
}
```

#### GET `/docs`

Access the interactive API documentation (Swagger UI).

#### GET `/redoc`

Access the alternative API documentation (ReDoc).

### 🧪 Example Usage

```bash
# Flight delay query
curl -X POST "http://54.221.105.106/recommendation" \
     -H "Content-Type: application/json" \
     -d '{"input_text": "Flight delayed due to weather"}'

# Flight cancellation query
curl -X POST "http://54.221.105.106/recommendation" \
     -H "Content-Type: application/json" \
     -d '{"input_text": "My flight was cancelled"}'
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Deployment Fails with Permission Errors

**Symptoms**: GitHub Actions fails with AWS permission errors

**Solution**:
```bash
# Check IAM policies
aws iam list-attached-role-policies --role-name your-github-actions-role

# Verify GitHub secrets
# Go to GitHub Settings → Secrets and verify all required secrets are set
```

#### 2. Application Not Accessible

**Symptoms**: 502 Bad Gateway or connection refused

**Solution**:
```bash
# Check service status
ssh -i ~/.ssh/your-key.pem ubuntu@your-instance-ip
sudo systemctl status agent-service

# Check logs
sudo journalctl -u agent-service -f

# Test locally on instance
curl http://localhost:8000/docs
```

#### 3. SSM Command Fails

**Symptoms**: Deployment commands fail to execute

**Solution**:
```bash
# Check SSM agent status
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=your-instance-id"

# Verify IAM role
aws iam get-role --role-name your-ec2-role

# Check instance tags
aws ec2 describe-instances --instance-ids your-instance-id \
  --query 'Reservations[].Instances[].Tags'
```

#### 4. Health Check Failures

**Symptoms**: Load balancer shows unhealthy targets

**Solution**:
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn your-target-group-arn

# Verify application is running
curl -f http://your-instance-ip/docs

# Check security group rules
aws ec2 describe-security-groups --group-ids your-sg-id
```

### Debug Commands

```bash
# Infrastructure debugging
terraform show
terraform state list

# Application debugging
docker-compose logs
sudo tail -f /var/log/agent/agent.log

# Network debugging
sudo netstat -tlnp | grep :8000
sudo ufw status verbose
```

### Log Locations

| Component | Log Location |
|-----------|--------------|
| Application | `/var/log/agent/agent.log` |
| Application Errors | `/var/log/agent/agent-error.log` |
| Nginx Access | `/var/log/nginx/access.log` |
| Nginx Errors | `/var/log/nginx/error.log` |
| System | `/var/log/syslog` |
| User Data | `/var/log/user-data.log` |

## 📈 Scaling

### Horizontal Scaling

#### Auto Scaling Groups

```hcl
# Add to terraform/main.tf
resource "aws_launch_template" "agent" {
  name_prefix   = "${var.environment}-agent-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  
  vpc_security_group_ids = [aws_security_group.agent.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
}

resource "aws_autoscaling_group" "agent" {
  name                = "${var.environment}-agent-asg"
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns   = [aws_lb_target_group.agent.arn]
  health_check_type   = "ELB"
  
  min_size         = 2
  max_size         = 10
  desired_capacity = 2
  
  launch_template {
    id      = aws_launch_template.agent.id
    version = "$Latest"
  }
}
```

#### Blue-Green Deployments

```bash
# Create new deployment
./scripts/deploy.sh production --blue-green

# Switch traffic
aws elbv2 modify-listener --listener-arn $LISTENER_ARN \
  --default-actions Type=forward,TargetGroupArn=$NEW_TARGET_GROUP
```

### Vertical Scaling

```bash
# Update instance type
cd terraform
terraform apply -var="instance_type=t3.medium"
```

### Performance Optimization

- **CloudFront**: Add CDN for static content
- **ElastiCache**: Add Redis for caching
- **RDS**: Add database for persistent storage
- **Lambda**: Add serverless functions for specific tasks

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

### Development Workflow

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/amazing-feature`
3. **Make** your changes
4. **Add** tests for new functionality
5. **Run** the test suite: `./test-pipeline.sh`
6. **Commit** your changes: `git commit -m 'Add amazing feature'`
7. **Push** to the branch: `git push origin feature/amazing-feature`
8. **Submit** a pull request

### Code Standards

- **Python**: Follow PEP 8 style guide
- **Terraform**: Use consistent formatting with `terraform fmt`
- **Documentation**: Update README and docs for new features
- **Testing**: Maintain test coverage above 80%

### Pull Request Process

1. Update documentation for any new features
2. Add tests for bug fixes and new functionality
3. Ensure all tests pass
4. Update the CHANGELOG.md
5. Request review from maintainers

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support & Resources

### Documentation
- 📖 [Deployment Guide](DEPLOYMENT_GUIDE.md) - Comprehensive setup instructions
- 🏗️ [Terraform README](terraform/README.md) - Infrastructure documentation
- 🔒 [Security Guide](docs/security.md) - Security best practices

### Support Channels
- 🐛 [GitHub Issues](https://github.com/your-repo/issues) - Bug reports and feature requests
- 💬 [Discussions](https://github.com/your-repo/discussions) - Community support
- 📧 Email: your-support-email@domain.com

### External Resources
- [AWS Documentation](https://docs.aws.amazon.com/)
- [Terraform Documentation](https://www.terraform.io/docs/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

## 🎯 Current Deployment Status

**Live Application**: http://54.221.105.106  
**API Documentation**: http://54.221.105.106/docs  
**Load Balancer**: http://production-agent-alb-1334460343.us-east-1.elb.amazonaws.com  

**Infrastructure Status**: ✅ **DEPLOYED**  
**Application Status**: ✅ **RUNNING**  
**CI/CD Pipeline**: ✅ **READY**  

---

**Built with ❤️ for reliable, secure, and scalable agent deployments**
