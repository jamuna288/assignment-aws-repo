# CI/CD Pipeline Deployment Guide

This guide walks you through setting up an automated CI/CD pipeline for deploying agents from GitHub to AWS EC2.

## Architecture Overview

```
GitHub Repository → GitHub Actions → S3 Bucket → EC2 Instance (via SSM)
                                              ↓
                                         CloudWatch Logs
```

## Prerequisites

- AWS Account with appropriate permissions
- GitHub repository
- Domain name (optional, for HTTPS)
- AWS CLI installed locally

## Step 1: AWS Infrastructure Setup

### Option A: Using CloudFormation (Recommended)

1. **Deploy the infrastructure:**
   ```bash
   aws cloudformation create-stack \
     --stack-name agent-infrastructure \
     --template-body file://infrastructure/cloudformation-template.yml \
     --parameters ParameterKey=Environment,ParameterValue=production \
                  ParameterKey=InstanceType,ParameterValue=t3.micro \
                  ParameterKey=KeyPairName,ParameterValue=your-key-pair \
     --capabilities CAPABILITY_NAMED_IAM \
     --region us-east-1
   ```

2. **Wait for stack creation:**
   ```bash
   aws cloudformation wait stack-create-complete \
     --stack-name agent-infrastructure \
     --region us-east-1
   ```

3. **Get outputs:**
   ```bash
   aws cloudformation describe-stacks \
     --stack-name agent-infrastructure \
     --query 'Stacks[0].Outputs' \
     --region us-east-1
   ```

### Option B: Manual Setup

1. **Create EC2 instance** with Ubuntu 20.04 LTS
2. **Attach IAM role** with SSM and S3 permissions
3. **Configure security groups** (ports 22, 80, 443)
4. **Run setup script** on the instance:
   ```bash
   curl -o setup-ec2.sh https://raw.githubusercontent.com/your-repo/assignment-aws-repo/main/infrastructure/setup-ec2.sh
   chmod +x setup-ec2.sh
   sudo ./setup-ec2.sh
   ```

## Step 2: GitHub Secrets Configuration

Add the following secrets to your GitHub repository:

### Required Secrets

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS Access Key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Key | `wJalrXUt...` |
| `AWS_REGION` | AWS Region | `us-east-1` |
| `EC2_INSTANCE_ID` | EC2 Instance ID | `i-1234567890abcdef0` |
| `S3_DEPLOYMENT_BUCKET` | S3 Bucket Name | `production-agent-deployments-123456789` |
| `ENVIRONMENT` | Environment Tag | `production` |

### Setting up secrets:

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret from the table above

## Step 3: AWS IAM Setup

### GitHub Actions IAM User

Create an IAM user for GitHub Actions with the following policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::your-deployment-bucket",
                "arn:aws:s3:::your-deployment-bucket/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:SendCommand",
                "ssm:ListCommands",
                "ssm:GetCommandInvocation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}
```

### EC2 Instance IAM Role

The EC2 instance needs an IAM role with:
- `AmazonSSMManagedInstanceCore` (managed policy)
- `CloudWatchAgentServerPolicy` (managed policy)
- Custom policy for S3 access:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::your-deployment-bucket",
                "arn:aws:s3:::your-deployment-bucket/*"
            ]
        }
    ]
}
```

## Step 4: Testing the Pipeline

### Local Testing

1. **Test locally with Docker:**
   ```bash
   docker-compose up --build
   ```

2. **Access the application:**
   - Application: http://localhost
   - API Docs: http://localhost/docs

### Manual Deployment

1. **Run manual deployment:**
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh production i-1234567890abcdef0
   ```

### Automated Deployment

1. **Push to main branch:**
   ```bash
   git add .
   git commit -m "Deploy agent"
   git push origin main
   ```

2. **Monitor GitHub Actions:**
   - Go to **Actions** tab in your repository
   - Watch the deployment progress

## Step 5: Monitoring and Logging

### CloudWatch Logs

- Application logs: `/aws/ec2/agent/application`
- Error logs: `/aws/ec2/agent/error`
- Deployment logs: `/aws/ssm/deployment-logs`

### CloudWatch Metrics

- CPU Utilization
- Memory Usage
- Disk Usage
- Custom application metrics

### Health Checks

- Application health: `http://your-instance-ip/docs`
- Load balancer health: `http://your-alb-dns/health`

## Step 6: Security Best Practices

### Network Security

- ✅ Security groups with minimal required ports
- ✅ VPC with private subnets (if using ALB)
- ✅ WAF rules (optional)

### Application Security

- ✅ Non-root user for application
- ✅ Environment-specific configurations
- ✅ Secrets management via AWS SSM
- ✅ HTTPS with SSL certificates

### Access Control

- ✅ IAM roles with least privilege
- ✅ SSH key-based authentication
- ✅ SSM Session Manager for secure access

## Troubleshooting

### Common Issues

1. **Deployment fails with permission errors:**
   - Check IAM roles and policies
   - Verify GitHub secrets are correct

2. **Application not accessible:**
   - Check security group rules
   - Verify nginx configuration
   - Check application logs

3. **SSM command fails:**
   - Ensure SSM agent is running
   - Check instance IAM role
   - Verify instance is tagged correctly

### Debugging Commands

```bash
# Check application status
sudo systemctl status agent-service

# View application logs
sudo journalctl -u agent-service -f

# Check nginx status
sudo systemctl status nginx

# Test application locally on instance
curl http://localhost:8000/docs

# Check SSM agent
sudo systemctl status amazon-ssm-agent
```

## Scaling and Optimization

### Auto Scaling

- Use Auto Scaling Groups for multiple instances
- Configure Application Load Balancer
- Implement blue-green deployments

### Performance

- Use CloudFront for static content
- Implement caching strategies
- Monitor and optimize resource usage

### Cost Optimization

- Use appropriate instance types
- Implement lifecycle policies for S3
- Set up CloudWatch billing alarms

## Maintenance

### Regular Tasks

- Update system packages monthly
- Rotate access keys quarterly
- Review and update security groups
- Monitor CloudWatch alarms

### Backup Strategy

- Regular AMI snapshots
- Database backups (if applicable)
- Configuration backups in version control

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review CloudWatch logs
3. Create GitHub issues for pipeline problems
4. Contact your DevOps team for infrastructure issues
