#!/bin/bash

# Comprehensive setup script for CI/CD pipeline
# This script helps you set up the entire infrastructure and pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STACK_NAME="agent-infrastructure"
ENVIRONMENT="production"
REGION="us-east-1"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Installing it for JSON parsing..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq
        fi
    fi
    
    log "Prerequisites check completed"
}

# Function to get user input
get_user_input() {
    echo ""
    info "Please provide the following information:"
    
    read -p "AWS Region (default: us-east-1): " input_region
    REGION=${input_region:-$REGION}
    
    read -p "Environment (default: production): " input_env
    ENVIRONMENT=${input_env:-$ENVIRONMENT}
    
    read -p "EC2 Instance Type (default: t3.micro): " input_instance
    INSTANCE_TYPE=${input_instance:-t3.micro}
    
    # List available key pairs
    echo ""
    info "Available EC2 Key Pairs in region $REGION:"
    aws ec2 describe-key-pairs --region $REGION --query 'KeyPairs[].KeyName' --output table
    
    read -p "EC2 Key Pair Name: " KEY_PAIR_NAME
    if [ -z "$KEY_PAIR_NAME" ]; then
        error "Key pair name is required"
    fi
    
    read -p "Allowed CIDR for access (default: 0.0.0.0/0): " input_cidr
    ALLOWED_CIDR=${input_cidr:-0.0.0.0/0}
    
    echo ""
    info "Configuration Summary:"
    echo "- Region: $REGION"
    echo "- Environment: $ENVIRONMENT"
    echo "- Instance Type: $INSTANCE_TYPE"
    echo "- Key Pair: $KEY_PAIR_NAME"
    echo "- Allowed CIDR: $ALLOWED_CIDR"
    echo ""
    
    read -p "Continue with this configuration? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        error "Setup cancelled by user"
    fi
}

# Function to deploy CloudFormation stack
deploy_infrastructure() {
    log "Deploying AWS infrastructure..."
    
    # Check if stack already exists
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
        warn "Stack $STACK_NAME already exists. Updating..."
        
        aws cloudformation update-stack \
            --stack-name $STACK_NAME \
            --template-body file://infrastructure/cloudformation-template.yml \
            --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                        ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE \
                        ParameterKey=KeyPairName,ParameterValue=$KEY_PAIR_NAME \
                        ParameterKey=AllowedCIDR,ParameterValue=$ALLOWED_CIDR \
            --capabilities CAPABILITY_NAMED_IAM \
            --region $REGION
        
        log "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete \
            --stack-name $STACK_NAME \
            --region $REGION
    else
        aws cloudformation create-stack \
            --stack-name $STACK_NAME \
            --template-body file://infrastructure/cloudformation-template.yml \
            --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                        ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE \
                        ParameterKey=KeyPairName,ParameterValue=$KEY_PAIR_NAME \
                        ParameterKey=AllowedCIDR,ParameterValue=$ALLOWED_CIDR \
            --capabilities CAPABILITY_NAMED_IAM \
            --region $REGION
        
        log "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete \
            --stack-name $STACK_NAME \
            --region $REGION
    fi
    
    log "Infrastructure deployment completed"
}

# Function to get stack outputs
get_stack_outputs() {
    log "Retrieving stack outputs..."
    
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs' \
        --output json)
    
    INSTANCE_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="InstanceId") | .OutputValue')
    PUBLIC_IP=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="InstancePublicIP") | .OutputValue')
    DEPLOYMENT_BUCKET=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="DeploymentBucket") | .OutputValue')
    ALB_DNS=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="LoadBalancerDNS") | .OutputValue')
    
    info "Stack Outputs:"
    echo "- Instance ID: $INSTANCE_ID"
    echo "- Public IP: $PUBLIC_IP"
    echo "- Deployment Bucket: $DEPLOYMENT_BUCKET"
    echo "- Load Balancer DNS: $ALB_DNS"
}

# Function to create GitHub secrets template
create_github_secrets_template() {
    log "Creating GitHub secrets template..."
    
    # Get AWS account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    cat > github-secrets.txt << EOF
# GitHub Secrets Configuration
# Add these secrets to your GitHub repository:
# Go to Settings → Secrets and variables → Actions → New repository secret

AWS_ACCESS_KEY_ID=<your-github-actions-access-key-id>
AWS_SECRET_ACCESS_KEY=<your-github-actions-secret-access-key>
AWS_REGION=$REGION
EC2_INSTANCE_ID=$INSTANCE_ID
S3_DEPLOYMENT_BUCKET=$DEPLOYMENT_BUCKET
ENVIRONMENT=$ENVIRONMENT

# Additional Information:
# - AWS Account ID: $ACCOUNT_ID
# - Instance Public IP: $PUBLIC_IP
# - Load Balancer DNS: $ALB_DNS

# Next Steps:
# 1. Create an IAM user for GitHub Actions with the policy in DEPLOYMENT_GUIDE.md
# 2. Add the above secrets to your GitHub repository
# 3. Push your code to trigger the first deployment
EOF
    
    log "GitHub secrets template created: github-secrets.txt"
}

# Function to test local setup
test_local_setup() {
    log "Testing local setup..."
    
    if command -v docker &> /dev/null && command -v docker-compose &> /dev/null; then
        info "Docker is available. You can test locally with:"
        echo "  docker-compose up --build"
        echo ""
    else
        warn "Docker not found. Install Docker to test locally."
    fi
}

# Function to display next steps
display_next_steps() {
    echo ""
    log "🎉 Setup completed successfully!"
    echo ""
    info "Next Steps:"
    echo "1. Review the GitHub secrets in: github-secrets.txt"
    echo "2. Create an IAM user for GitHub Actions (see DEPLOYMENT_GUIDE.md)"
    echo "3. Add the secrets to your GitHub repository"
    echo "4. Push your code to the main branch to trigger deployment"
    echo "5. Monitor the deployment in GitHub Actions"
    echo ""
    info "Access your application:"
    echo "- Direct access: http://$PUBLIC_IP"
    echo "- Load balancer: http://$ALB_DNS"
    echo "- API documentation: http://$PUBLIC_IP/docs"
    echo ""
    info "Useful commands:"
    echo "- Manual deployment: ./scripts/deploy.sh $ENVIRONMENT $INSTANCE_ID"
    echo "- Security hardening: ssh to instance and run infrastructure/setup-ec2.sh"
    echo "- View logs: AWS CloudWatch or SSH to instance"
    echo ""
    warn "Important Security Notes:"
    echo "- Change default passwords and keys"
    echo "- Review security group rules"
    echo "- Enable CloudTrail for audit logging"
    echo "- Set up monitoring and alerting"
}

# Main execution
main() {
    echo ""
    log "🚀 Starting CI/CD Pipeline Setup"
    echo ""
    
    check_prerequisites
    get_user_input
    deploy_infrastructure
    get_stack_outputs
    create_github_secrets_template
    test_local_setup
    display_next_steps
}

# Handle script interruption
trap 'error "Setup interrupted"' INT TERM

# Run main function
main "$@"
