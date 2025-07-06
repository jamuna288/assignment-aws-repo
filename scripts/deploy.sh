#!/bin/bash

# Manual deployment script for agent
# Usage: ./deploy.sh [environment] [instance-id]

set -e

ENVIRONMENT=${1:-production}
INSTANCE_ID=${2}
REGION=${AWS_REGION:-us-east-1}
S3_BUCKET="${ENVIRONMENT}-agent-deployments-$(aws sts get-caller-identity --query Account --output text)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi
    
    if [ -z "$INSTANCE_ID" ]; then
        log "Instance ID not provided, attempting to discover..."
        INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Environment,Values=$ENVIRONMENT" "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text \
            --region $REGION)
        
        if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
            error "Could not find running instance with Environment tag: $ENVIRONMENT"
        fi
        
        log "Found instance: $INSTANCE_ID"
    fi
    
    if [ ! -d "Sample_Agent" ]; then
        error "Sample_Agent directory not found. Run this script from the repository root."
    fi
}

# Create deployment package
create_package() {
    log "Creating deployment package..."
    
    cd Sample_Agent
    
    # Create a clean package
    TEMP_DIR=$(mktemp -d)
    cp -r . "$TEMP_DIR/"
    
    # Remove unnecessary files
    find "$TEMP_DIR" -name "*.pyc" -delete
    find "$TEMP_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$TEMP_DIR" -name ".DS_Store" -delete 2>/dev/null || true
    
    # Create tarball
    DEPLOYMENT_FILE="agent-deployment-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "../$DEPLOYMENT_FILE" -C "$TEMP_DIR" .
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    cd ..
    
    log "Created deployment package: $DEPLOYMENT_FILE"
}

# Upload to S3
upload_package() {
    log "Uploading deployment package to S3..."
    
    aws s3 cp "$DEPLOYMENT_FILE" "s3://$S3_BUCKET/deployments/" --region $REGION
    
    if [ $? -eq 0 ]; then
        log "Package uploaded successfully"
    else
        error "Failed to upload package to S3"
    fi
}

# Deploy to EC2
deploy_to_ec2() {
    log "Deploying to EC2 instance: $INSTANCE_ID"
    
    COMMAND_ID=$(aws ssm send-command \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[
            '#!/bin/bash',
            'set -e',
            'echo \"Starting deployment at \$(date)\"',
            'cd /opt/agent',
            'sudo systemctl stop agent-service || true',
            'aws s3 cp s3://$S3_BUCKET/deployments/$DEPLOYMENT_FILE /tmp/',
            'sudo rm -rf /opt/agent/current/*',
            'sudo tar -xzf /tmp/$DEPLOYMENT_FILE -C /opt/agent/current/',
            'sudo chown -R agent:agent /opt/agent/current/',
            'cd /opt/agent/current',
            'sudo -u agent python3 -m venv venv',
            'sudo -u agent ./venv/bin/pip install --upgrade pip',
            'sudo -u agent ./venv/bin/pip install -r requirements.txt',
            'sudo systemctl start agent-service',
            'sudo systemctl enable agent-service',
            'sleep 10',
            'curl -f http://localhost:8000/docs || (echo \"Health check failed\" && exit 1)',
            'echo \"Deployment completed successfully at \$(date)\"'
        ]" \
        --targets "Key=InstanceIds,Values=$INSTANCE_ID" \
        --region $REGION \
        --query 'Command.CommandId' \
        --output text)
    
    if [ -z "$COMMAND_ID" ]; then
        error "Failed to send deployment command"
    fi
    
    log "Deployment command sent. Command ID: $COMMAND_ID"
    
    # Wait for command completion
    log "Waiting for deployment to complete..."
    
    for i in {1..30}; do
        STATUS=$(aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --region $REGION \
            --query 'Status' \
            --output text 2>/dev/null || echo "InProgress")
        
        case $STATUS in
            "Success")
                log "Deployment completed successfully!"
                break
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                error "Deployment failed with status: $STATUS"
                ;;
            "InProgress")
                echo -n "."
                sleep 10
                ;;
            *)
                warn "Unknown status: $STATUS"
                sleep 10
                ;;
        esac
        
        if [ $i -eq 30 ]; then
            error "Deployment timed out"
        fi
    done
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Get instance public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region $REGION)
    
    if [ "$PUBLIC_IP" != "None" ] && [ -n "$PUBLIC_IP" ]; then
        log "Testing application endpoint..."
        
        # Wait a bit for the service to be fully ready
        sleep 15
        
        if curl -f -s "http://$PUBLIC_IP/docs" > /dev/null; then
            log "✅ Application is responding correctly!"
            log "🌐 Access your application at: http://$PUBLIC_IP"
            log "📚 API documentation: http://$PUBLIC_IP/docs"
        else
            warn "Application endpoint test failed. Check the logs on the instance."
        fi
    else
        warn "Could not determine public IP address"
    fi
}

# Cleanup
cleanup() {
    log "Cleaning up temporary files..."
    rm -f "$DEPLOYMENT_FILE"
}

# Main execution
main() {
    log "Starting deployment process..."
    log "Environment: $ENVIRONMENT"
    log "Region: $REGION"
    
    check_prerequisites
    create_package
    upload_package
    deploy_to_ec2
    verify_deployment
    cleanup
    
    log "🎉 Deployment process completed!"
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"
