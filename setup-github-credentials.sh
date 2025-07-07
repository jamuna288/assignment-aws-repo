#!/bin/bash

echo "🔐 Setting up AWS Credentials for GitHub Actions"
echo "==============================================="

echo ""
echo "📋 Step 1: Create IAM User for GitHub Actions"
echo "---------------------------------------------"

# Create IAM user for GitHub Actions
echo "Creating IAM user 'github-actions-user'..."

aws iam create-user --user-name github-actions-user --path /github-actions/ 2>/dev/null || echo "User might already exist"

echo ""
echo "📝 Step 2: Create IAM Policy"
echo "----------------------------"

# Create policy document
cat > github-actions-policy.json << 'EOF'
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
                "arn:aws:s3:::production-agent-deployments-739275482209",
                "arn:aws:s3:::production-agent-deployments-739275482209/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:SendCommand",
                "ssm:GetCommandInvocation",
                "ssm:DescribeInstanceInformation",
                "ssm:ListCommandInvocations"
            ],
            "Resource": [
                "arn:aws:ec2:us-east-1:739275482209:instance/i-01acfb7448e3fe4ee",
                "arn:aws:ssm:us-east-1:739275482209:document/AWS-RunShellScript",
                "arn:aws:ssm:us-east-1:*:*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the policy
aws iam create-policy \
    --policy-name GitHubActionsDeploymentPolicy \
    --policy-document file://github-actions-policy.json \
    --description "Policy for GitHub Actions to deploy to EC2" 2>/dev/null || echo "Policy might already exist"

echo ""
echo "🔗 Step 3: Attach Policy to User"
echo "--------------------------------"

# Attach policy to user
aws iam attach-user-policy \
    --user-name github-actions-user \
    --policy-arn arn:aws:iam::739275482209:policy/GitHubActionsDeploymentPolicy

echo ""
echo "🔑 Step 4: Create Access Keys"
echo "-----------------------------"

# Create access keys
echo "Creating access keys for github-actions-user..."
ACCESS_KEYS=$(aws iam create-access-key --user-name github-actions-user --output json 2>/dev/null)

if [ $? -eq 0 ]; then
    ACCESS_KEY_ID=$(echo $ACCESS_KEYS | jq -r '.AccessKey.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo $ACCESS_KEYS | jq -r '.AccessKey.SecretAccessKey')
    
    echo ""
    echo "✅ SUCCESS! AWS Credentials Created"
    echo "=================================="
    echo ""
    echo "🔐 Add these secrets to GitHub:"
    echo "Go to: https://github.com/jamuna288/assignment-aws-repo/settings/secrets/actions"
    echo ""
    echo "AWS_ACCESS_KEY_ID = $ACCESS_KEY_ID"
    echo "AWS_SECRET_ACCESS_KEY = $SECRET_ACCESS_KEY"
    echo "AWS_REGION = us-east-1"
    echo "EC2_INSTANCE_ID = i-01acfb7448e3fe4ee"
    echo "S3_DEPLOYMENT_BUCKET = production-agent-deployments-739275482209"
    echo "ENVIRONMENT = production"
    echo ""
    echo "⚠️  IMPORTANT: Save these credentials securely!"
    echo "   The secret access key will not be shown again."
    
    # Save to file for reference
    cat > github-secrets-values.txt << EOF
# GitHub Secrets Values - KEEP SECURE!
# Add these to: https://github.com/jamuna288/assignment-aws-repo/settings/secrets/actions

AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
AWS_REGION=us-east-1
EC2_INSTANCE_ID=i-01acfb7448e3fe4ee
S3_DEPLOYMENT_BUCKET=production-agent-deployments-739275482209
ENVIRONMENT=production
EOF
    
    echo ""
    echo "📄 Credentials also saved to: github-secrets-values.txt"
    echo "   (Remember to delete this file after adding secrets to GitHub)"
    
else
    echo "❌ Failed to create access keys. User might already have maximum keys."
    echo "   You can list existing keys with:"
    echo "   aws iam list-access-keys --user-name github-actions-user"
fi

# Cleanup
rm -f github-actions-policy.json

echo ""
echo "🚀 Next Steps:"
echo "1. Add the secrets to GitHub (link above)"
echo "2. Push a commit to trigger the workflow"
echo "3. Monitor the deployment in GitHub Actions"
