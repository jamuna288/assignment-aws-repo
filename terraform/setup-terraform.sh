#!/bin/bash

# Terraform setup script for agent infrastructure
# This script helps you deploy the infrastructure using Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install it first: https://www.terraform.io/downloads.html"
    fi
    
    # Check Terraform version
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    log "Terraform version: $TERRAFORM_VERSION"
    
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

# Get user input for configuration
get_user_input() {
    echo ""
    info "Please provide the following information:"
    
    read -p "AWS Region (default: us-east-1): " input_region
    AWS_REGION=${input_region:-us-east-1}
    
    read -p "Environment (default: production): " input_env
    ENVIRONMENT=${input_env:-production}
    
    read -p "EC2 Instance Type (default: t3.micro): " input_instance
    INSTANCE_TYPE=${input_instance:-t3.micro}
    
    # List available key pairs
    echo ""
    info "Available EC2 Key Pairs in region $AWS_REGION:"
    aws ec2 describe-key-pairs --region $AWS_REGION --query 'KeyPairs[].KeyName' --output table || warn "Could not list key pairs"
    
    read -p "EC2 Key Pair Name: " KEY_PAIR_NAME
    if [ -z "$KEY_PAIR_NAME" ]; then
        error "Key pair name is required"
    fi
    
    read -p "Allowed CIDR for access (default: 0.0.0.0/0): " input_cidr
    ALLOWED_CIDR=${input_cidr:-0.0.0.0/0}
    
    echo ""
    info "Configuration Summary:"
    echo "- Region: $AWS_REGION"
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

# Create terraform.tfvars file
create_tfvars() {
    log "Creating terraform.tfvars file..."
    
    cat > terraform.tfvars << EOF
# Terraform variables for agent infrastructure
aws_region = "$AWS_REGION"
environment = "$ENVIRONMENT"
instance_type = "$INSTANCE_TYPE"
key_pair_name = "$KEY_PAIR_NAME"
allowed_cidr = "$ALLOWED_CIDR"
vpc_cidr = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
enable_monitoring = true
enable_cloudwatch_logs = true
EOF
    
    log "terraform.tfvars file created"
}

# Initialize Terraform
init_terraform() {
    log "Initializing Terraform..."
    terraform init
    
    if [ $? -eq 0 ]; then
        log "Terraform initialization completed"
    else
        error "Terraform initialization failed"
    fi
}

# Plan Terraform deployment
plan_terraform() {
    log "Creating Terraform plan..."
    terraform plan -out=tfplan
    
    if [ $? -eq 0 ]; then
        log "Terraform plan created successfully"
        echo ""
        info "Review the plan above. The following resources will be created:"
        echo "- VPC and networking components"
        echo "- EC2 instance with security groups"
        echo "- S3 bucket for deployments"
        echo "- IAM roles and policies"
        echo "- Application Load Balancer"
        echo "- CloudWatch log groups and alarms"
        echo ""
    else
        error "Terraform plan failed"
    fi
}

# Apply Terraform configuration
apply_terraform() {
    read -p "Do you want to apply this Terraform plan? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        warn "Terraform apply cancelled by user"
        return 0
    fi
    
    log "Applying Terraform configuration..."
    terraform apply tfplan
    
    if [ $? -eq 0 ]; then
        log "Terraform apply completed successfully"
    else
        error "Terraform apply failed"
    fi
}

# Get outputs and create GitHub secrets
get_outputs() {
    log "Retrieving Terraform outputs..."
    
    # Get outputs in JSON format
    OUTPUTS=$(terraform output -json)
    
    # Extract values
    INSTANCE_ID=$(echo $OUTPUTS | jq -r '.instance_id.value')
    PUBLIC_IP=$(echo $OUTPUTS | jq -r '.instance_public_ip.value')
    DEPLOYMENT_BUCKET=$(echo $OUTPUTS | jq -r '.deployment_bucket_name.value')
    ALB_DNS=$(echo $OUTPUTS | jq -r '.load_balancer_dns.value')
    APP_URL=$(echo $OUTPUTS | jq -r '.application_url.value')
    API_DOCS_URL=$(echo $OUTPUTS | jq -r '.api_documentation_url.value')
    
    info "Infrastructure Details:"
    echo "- Instance ID: $INSTANCE_ID"
    echo "- Public IP: $PUBLIC_IP"
    echo "- Deployment Bucket: $DEPLOYMENT_BUCKET"
    echo "- Load Balancer DNS: $ALB_DNS"
    echo "- Application URL: $APP_URL"
    echo "- API Documentation: $API_DOCS_URL"
    
    # Create GitHub secrets file
    create_github_secrets
}

# Create GitHub secrets template
create_github_secrets() {
    log "Creating GitHub secrets template..."
    
    # Get AWS account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    cat > ../github-secrets.txt << EOF
# GitHub Secrets Configuration
# Add these secrets to your GitHub repository:
# Go to Settings → Secrets and variables → Actions → New repository secret

AWS_ACCESS_KEY_ID=<your-github-actions-access-key-id>
AWS_SECRET_ACCESS_KEY=<your-github-actions-secret-access-key>
AWS_REGION=$AWS_REGION
EC2_INSTANCE_ID=$INSTANCE_ID
S3_DEPLOYMENT_BUCKET=$DEPLOYMENT_BUCKET
ENVIRONMENT=$ENVIRONMENT

# Additional Information:
# - AWS Account ID: $ACCOUNT_ID
# - Instance Public IP: $PUBLIC_IP
# - Load Balancer DNS: $ALB_DNS
# - Application URL: $APP_URL
# - API Documentation: $API_DOCS_URL

# Next Steps:
# 1. Create an IAM user for GitHub Actions with the policy in DEPLOYMENT_GUIDE.md
# 2. Add the above secrets to your GitHub repository
# 3. Push your code to trigger the first deployment
# 4. Test the deployment using the provided URLs
EOF
    
    log "GitHub secrets template created: ../github-secrets.txt"
}

# Test the deployment
test_deployment() {
    log "Testing the deployed infrastructure..."
    
    echo ""
    info "Waiting for instance to be fully ready..."
    sleep 30
    
    # Test direct instance access
    if curl -f -s "$APP_URL" > /dev/null; then
        log "✅ Direct instance access: SUCCESS"
    else
        warn "❌ Direct instance access: FAILED"
    fi
    
    # Test load balancer access
    if curl -f -s "http://$ALB_DNS" > /dev/null; then
        log "✅ Load balancer access: SUCCESS"
    else
        warn "❌ Load balancer access: FAILED (may take a few minutes to be ready)"
    fi
    
    # Test API documentation
    if curl -f -s "$API_DOCS_URL" > /dev/null; then
        log "✅ API documentation: SUCCESS"
    else
        warn "❌ API documentation: FAILED"
    fi
}

# Display next steps
display_next_steps() {
    echo ""
    log "🎉 Terraform deployment completed successfully!"
    echo ""
    info "Access your application:"
    echo "- Direct access: $APP_URL"
    echo "- Load balancer: http://$ALB_DNS"
    echo "- API documentation: $API_DOCS_URL"
    echo ""
    info "Next Steps:"
    echo "1. Review the GitHub secrets in: ../github-secrets.txt"
    echo "2. Create an IAM user for GitHub Actions (see ../DEPLOYMENT_GUIDE.md)"
    echo "3. Add the secrets to your GitHub repository"
    echo "4. Push your code to the main branch to trigger deployment"
    echo "5. Monitor the deployment in GitHub Actions"
    echo ""
    info "Useful commands:"
    echo "- View outputs: terraform output"
    echo "- SSH to instance: ssh -i ~/.ssh/$KEY_PAIR_NAME.pem ubuntu@$PUBLIC_IP"
    echo "- Destroy infrastructure: terraform destroy"
    echo ""
    warn "Important Security Notes:"
    echo "- The instance is accessible from $ALLOWED_CIDR"
    echo "- Consider restricting access to your IP range"
    echo "- Review security group rules in AWS console"
    echo "- Enable CloudTrail for audit logging"
}

# Main execution
main() {
    echo ""
    log "🚀 Starting Terraform Infrastructure Deployment"
    echo ""
    
    # Change to terraform directory
    cd "$(dirname "$0")"
    
    check_prerequisites
    get_user_input
    create_tfvars
    init_terraform
    plan_terraform
    apply_terraform
    get_outputs
    test_deployment
    display_next_steps
}

# Handle script interruption
trap 'error "Setup interrupted"' INT TERM

# Run main function
main "$@"
