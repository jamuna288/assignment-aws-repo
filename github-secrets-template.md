# GitHub Secrets Configuration Template

This document provides the complete list of GitHub Secrets required for the enhanced CI/CD pipeline with rollback, versioning, and notifications.

## 🔐 Required GitHub Secrets

### AWS Configuration Secrets
```
AWS_ACCESS_KEY_ID
Description: AWS Access Key ID for GitHub Actions
Example: AKIA1234567890ABCDEF
Required: Yes
```

```
AWS_SECRET_ACCESS_KEY
Description: AWS Secret Access Key for GitHub Actions
Example: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Required: Yes
```

```
AWS_REGION
Description: AWS Region where your resources are deployed
Example: us-east-1
Required: Yes
```

### EC2 Configuration Secrets
```
EC2_INSTANCE_ID
Description: EC2 Instance ID where the agent will be deployed
Example: i-1234567890abcdef0
Required: Yes
```

```
EC2_PUBLIC_IP
Description: Public IP address of the EC2 instance (for notifications)
Example: 54.123.45.67
Required: Optional (can be retrieved dynamically)
```

### S3 Configuration Secrets
```
S3_DEPLOYMENT_BUCKET
Description: S3 bucket name for storing deployment artifacts
Example: my-agent-deployments-bucket-123456789
Required: Yes
```

### SSH Configuration Secrets (Backup - SSM is primary)
```
EC2_SSH_PRIVATE_KEY
Description: Private SSH key for EC2 access (base64 encoded)
Example: LS0tLS1CRUdJTi... (base64 encoded private key)
Required: Optional (SSM is used primarily)
```

```
EC2_SSH_USER
Description: SSH username for EC2 access
Example: ubuntu
Required: Optional
```

### Notification Secrets
```
SLACK_WEBHOOK_URL
Description: Slack webhook URL for deployment notifications
Example: https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
Required: Optional
```

```
EMAIL_WEBHOOK_URL
Description: Email webhook URL for deployment notifications (e.g., Zapier, IFTTT)
Example: https://hooks.zapier.com/hooks/catch/123456/abcdef/
Required: Optional
```

```
TEAMS_WEBHOOK_URL
Description: Microsoft Teams webhook URL for notifications
Example: https://outlook.office.com/webhook/...
Required: Optional
```

### Environment Configuration
```
ENVIRONMENT
Description: Deployment environment tag
Example: production
Required: Yes
```

```
APPLICATION_NAME
Description: Name of the application for tagging and identification
Example: flight-agent
Required: Optional (defaults to 'flight-agent')
```

## 🚀 How to Add Secrets to GitHub

### Method 1: GitHub Web Interface
1. Go to your repository on GitHub
2. Click on **Settings** tab
3. Click on **Secrets and variables** → **Actions**
4. Click **New repository secret**
5. Add each secret with the name and value from above

### Method 2: GitHub CLI
```bash
# Install GitHub CLI if not already installed
# https://cli.github.com/

# Login to GitHub
gh auth login

# Add secrets (replace with your actual values)
gh secret set AWS_ACCESS_KEY_ID --body "AKIA1234567890ABCDEF"
gh secret set AWS_SECRET_ACCESS_KEY --body "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
gh secret set AWS_REGION --body "us-east-1"
gh secret set EC2_INSTANCE_ID --body "i-1234567890abcdef0"
gh secret set S3_DEPLOYMENT_BUCKET --body "my-agent-deployments-bucket"
gh secret set ENVIRONMENT --body "production"

# Optional notification secrets
gh secret set SLACK_WEBHOOK_URL --body "https://hooks.slack.com/services/..."
gh secret set EMAIL_WEBHOOK_URL --body "https://hooks.zapier.com/hooks/catch/..."
```

### Method 3: Bulk Import Script
```bash
#!/bin/bash
# bulk-add-secrets.sh

# Set your values here
export AWS_ACCESS_KEY_ID="AKIA1234567890ABCDEF"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_REGION="us-east-1"
export EC2_INSTANCE_ID="i-1234567890abcdef0"
export S3_DEPLOYMENT_BUCKET="my-agent-deployments-bucket"
export ENVIRONMENT="production"

# Add required secrets
gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID"
gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY"
gh secret set AWS_REGION --body "$AWS_REGION"
gh secret set EC2_INSTANCE_ID --body "$EC2_INSTANCE_ID"
gh secret set S3_DEPLOYMENT_BUCKET --body "$S3_DEPLOYMENT_BUCKET"
gh secret set ENVIRONMENT --body "$ENVIRONMENT"

echo "✅ All required secrets added successfully!"
```

## 🔍 Verification Commands

### Check if secrets are properly set:
```bash
# List all secrets (names only, values are hidden)
gh secret list

# Test AWS credentials
aws sts get-caller-identity

# Test EC2 access
aws ec2 describe-instances --instance-ids YOUR_INSTANCE_ID

# Test S3 access
aws s3 ls s3://YOUR_DEPLOYMENT_BUCKET
```

## 🛡️ Security Best Practices

### 1. AWS IAM Policy for GitHub Actions
Create a dedicated IAM user with minimal permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::YOUR_DEPLOYMENT_BUCKET",
                "arn:aws:s3:::YOUR_DEPLOYMENT_BUCKET/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:SendCommand",
                "ssm:GetCommandInvocation",
                "ssm:ListCommands",
                "ssm:DescribeInstanceInformation"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:instance/YOUR_INSTANCE_ID",
                "arn:aws:ssm:*:*:document/AWS-RunShellScript",
                "arn:aws:ssm:*:*:command/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:log-group:/aws/ssm/*"
        }
    ]
}
```

### 2. SSH Key Security (if used)
```bash
# Generate a dedicated SSH key for GitHub Actions
ssh-keygen -t rsa -b 4096 -C "github-actions@yourdomain.com" -f ~/.ssh/github_actions_key

# Base64 encode the private key for GitHub Secrets
base64 -w 0 ~/.ssh/github_actions_key

# Add the public key to your EC2 instance
cat ~/.ssh/github_actions_key.pub >> ~/.ssh/authorized_keys
```

### 3. Webhook Security
- Use HTTPS webhooks only
- Implement webhook signature verification where possible
- Rotate webhook URLs periodically
- Monitor webhook usage

## 📋 Secrets Validation Checklist

- [ ] AWS_ACCESS_KEY_ID is set and valid
- [ ] AWS_SECRET_ACCESS_KEY is set and valid
- [ ] AWS_REGION matches your EC2 instance region
- [ ] EC2_INSTANCE_ID is correct and instance exists
- [ ] S3_DEPLOYMENT_BUCKET exists and is accessible
- [ ] ENVIRONMENT is set (production/staging)
- [ ] SLACK_WEBHOOK_URL is set (if using Slack notifications)
- [ ] EMAIL_WEBHOOK_URL is set (if using email notifications)
- [ ] IAM permissions are properly configured
- [ ] EC2 instance has SSM agent installed and running
- [ ] Security groups allow necessary traffic

## 🚨 Troubleshooting

### Common Issues:

1. **AWS Permission Denied**
   - Check IAM policy permissions
   - Verify AWS credentials are correct
   - Ensure region matches

2. **SSM Command Fails**
   - Check if SSM agent is running on EC2
   - Verify instance has proper IAM role
   - Check security groups

3. **S3 Access Denied**
   - Verify bucket exists and is accessible
   - Check bucket policy and IAM permissions
   - Ensure region is correct

4. **Notification Failures**
   - Test webhook URLs manually
   - Check webhook format and authentication
   - Verify network connectivity

## 📞 Support

If you encounter issues:
1. Check GitHub Actions logs
2. Check AWS CloudWatch logs
3. Verify all secrets are properly set
4. Test individual components manually
5. Review IAM permissions and policies

---

**⚠️ Important Security Notes:**
- Never commit secrets to your repository
- Regularly rotate access keys and tokens
- Use least-privilege principle for IAM policies
- Monitor secret usage and access logs
- Enable AWS CloudTrail for audit logging
