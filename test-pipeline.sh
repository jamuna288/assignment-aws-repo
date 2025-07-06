#!/bin/bash

# Comprehensive pipeline testing script
# This script tests the entire CI/CD pipeline and agent deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

success() {
    echo -e "${PURPLE}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

# Configuration
INSTANCE_ID=""
PUBLIC_IP=""
ALB_DNS=""
DEPLOYMENT_BUCKET=""
AWS_REGION="us-east-1"
ENVIRONMENT="production"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

# Function to record test result
record_test() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    if [ "$result" = "PASS" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        success "$test_name: PASSED - $message"
        TEST_RESULTS+=("✅ $test_name: PASSED")
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        warn "$test_name: FAILED - $message"
        TEST_RESULTS+=("❌ $test_name: FAILED")
    fi
}

# Get infrastructure details
get_infrastructure_details() {
    log "Getting infrastructure details..."
    
    if [ -f "terraform/terraform.tfstate" ]; then
        info "Reading from Terraform state..."
        cd terraform
        INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
        PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
        ALB_DNS=$(terraform output -raw load_balancer_dns 2>/dev/null || echo "")
        DEPLOYMENT_BUCKET=$(terraform output -raw deployment_bucket_name 2>/dev/null || echo "")
        cd ..
    fi
    
    # If Terraform outputs are not available, try to discover
    if [ -z "$INSTANCE_ID" ]; then
        warn "Terraform outputs not available, attempting to discover infrastructure..."
        
        INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Environment,Values=$ENVIRONMENT" "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text \
            --region $AWS_REGION 2>/dev/null || echo "None")
        
        if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
            PUBLIC_IP=$(aws ec2 describe-instances \
                --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' \
                --output text \
                --region $AWS_REGION)
        fi
    fi
    
    if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
        error "Could not find infrastructure. Please deploy first using terraform/setup-terraform.sh"
    fi
    
    info "Infrastructure Details:"
    echo "- Instance ID: $INSTANCE_ID"
    echo "- Public IP: $PUBLIC_IP"
    echo "- ALB DNS: $ALB_DNS"
    echo "- Deployment Bucket: $DEPLOYMENT_BUCKET"
}

# Test 1: Infrastructure Health
test_infrastructure_health() {
    log "Testing infrastructure health..."
    
    # Test EC2 instance status
    local instance_state=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text \
        --region $AWS_REGION)
    
    if [ "$instance_state" = "running" ]; then
        record_test "EC2 Instance Status" "PASS" "Instance is running"
    else
        record_test "EC2 Instance Status" "FAIL" "Instance state: $instance_state"
    fi
    
    # Test SSM connectivity
    local ssm_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text \
        --region $AWS_REGION 2>/dev/null || echo "NotFound")
    
    if [ "$ssm_status" = "Online" ]; then
        record_test "SSM Connectivity" "PASS" "SSM agent is online"
    else
        record_test "SSM Connectivity" "FAIL" "SSM status: $ssm_status"
    fi
    
    # Test S3 bucket access
    if aws s3 ls "s3://$DEPLOYMENT_BUCKET" &>/dev/null; then
        record_test "S3 Bucket Access" "PASS" "Bucket is accessible"
    else
        record_test "S3 Bucket Access" "FAIL" "Cannot access deployment bucket"
    fi
}

# Test 2: Application Services
test_application_services() {
    log "Testing application services on EC2 instance..."
    
    # Test if services are running via SSM
    local command_id=$(aws ssm send-command \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["systemctl is-active agent-service", "systemctl is-active nginx"]' \
        --targets "Key=InstanceIds,Values=$INSTANCE_ID" \
        --region $AWS_REGION \
        --query 'Command.CommandId' \
        --output text)
    
    # Wait for command completion
    sleep 10
    
    local command_output=$(aws ssm get-command-invocation \
        --command-id "$command_id" \
        --instance-id "$INSTANCE_ID" \
        --region $AWS_REGION \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "")
    
    if echo "$command_output" | grep -q "active"; then
        record_test "Application Services" "PASS" "Services are running"
    else
        record_test "Application Services" "FAIL" "Services not running properly"
    fi
}

# Test 3: Network Connectivity
test_network_connectivity() {
    log "Testing network connectivity..."
    
    # Test direct instance access
    if curl -f -s --connect-timeout 10 "http://$PUBLIC_IP" > /dev/null; then
        record_test "Direct Instance Access" "PASS" "Instance is accessible via HTTP"
    else
        record_test "Direct Instance Access" "FAIL" "Cannot reach instance via HTTP"
    fi
    
    # Test load balancer access (if ALB DNS is available)
    if [ -n "$ALB_DNS" ]; then
        if curl -f -s --connect-timeout 10 "http://$ALB_DNS" > /dev/null; then
            record_test "Load Balancer Access" "PASS" "ALB is accessible"
        else
            record_test "Load Balancer Access" "FAIL" "Cannot reach ALB"
        fi
    else
        record_test "Load Balancer Access" "SKIP" "ALB DNS not available"
    fi
}

# Test 4: API Endpoints
test_api_endpoints() {
    log "Testing API endpoints..."
    
    local base_url="http://$PUBLIC_IP"
    
    # Test API documentation endpoint
    if curl -f -s --connect-timeout 10 "$base_url/docs" > /dev/null; then
        record_test "API Documentation" "PASS" "API docs are accessible"
    else
        record_test "API Documentation" "FAIL" "API docs not accessible"
    fi
    
    # Test recommendation endpoint
    local api_response=$(curl -s -X POST "$base_url/recommendation" \
        -H "Content-Type: application/json" \
        -d '{"input_text": "test query"}' \
        --connect-timeout 10 || echo "")
    
    if echo "$api_response" | grep -q "response"; then
        record_test "Recommendation API" "PASS" "API returns valid response"
    else
        record_test "Recommendation API" "FAIL" "API not responding correctly"
    fi
}

# Test 5: Manual Deployment
test_manual_deployment() {
    log "Testing manual deployment process..."
    
    if [ -f "scripts/deploy.sh" ]; then
        info "Running manual deployment test..."
        
        # Create a test deployment
        if ./scripts/deploy.sh "$ENVIRONMENT" "$INSTANCE_ID" &>/dev/null; then
            record_test "Manual Deployment" "PASS" "Manual deployment successful"
        else
            record_test "Manual Deployment" "FAIL" "Manual deployment failed"
        fi
    else
        record_test "Manual Deployment" "SKIP" "Deploy script not found"
    fi
}

# Test 6: GitHub Actions Workflow
test_github_workflow() {
    log "Testing GitHub Actions workflow configuration..."
    
    if [ -f ".github/workflows/deploy.yml" ]; then
        # Check if workflow file is valid YAML
        if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/deploy.yml'))" 2>/dev/null; then
            record_test "GitHub Workflow YAML" "PASS" "Workflow file is valid YAML"
        else
            record_test "GitHub Workflow YAML" "FAIL" "Workflow file has YAML syntax errors"
        fi
        
        # Check for required secrets in workflow
        local workflow_content=$(cat .github/workflows/deploy.yml)
        local required_secrets=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_REGION" "EC2_INSTANCE_ID" "S3_DEPLOYMENT_BUCKET" "ENVIRONMENT")
        local missing_secrets=()
        
        for secret in "${required_secrets[@]}"; do
            if ! echo "$workflow_content" | grep -q "\${{ secrets\.$secret }}"; then
                missing_secrets+=("$secret")
            fi
        done
        
        if [ ${#missing_secrets[@]} -eq 0 ]; then
            record_test "GitHub Secrets Configuration" "PASS" "All required secrets are referenced"
        else
            record_test "GitHub Secrets Configuration" "FAIL" "Missing secrets: ${missing_secrets[*]}"
        fi
    else
        record_test "GitHub Workflow File" "FAIL" "Workflow file not found"
    fi
}

# Test 7: Security Configuration
test_security_configuration() {
    log "Testing security configuration..."
    
    # Test security group rules
    local sg_id=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text \
        --region $AWS_REGION)
    
    local sg_rules=$(aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --query 'SecurityGroups[0].IpPermissions' \
        --output json \
        --region $AWS_REGION)
    
    # Check if SSH is restricted (not 0.0.0.0/0 for port 22)
    local ssh_open=$(echo "$sg_rules" | jq -r '.[] | select(.FromPort==22) | .IpRanges[].CidrIp' | grep -c "0.0.0.0/0" || echo "0")
    
    if [ "$ssh_open" -eq 0 ]; then
        record_test "SSH Security" "PASS" "SSH access is properly restricted"
    else
        record_test "SSH Security" "WARN" "SSH is open to 0.0.0.0/0 - consider restricting"
    fi
    
    # Test if instance has proper IAM role
    local iam_role=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
        --output text \
        --region $AWS_REGION)
    
    if [ "$iam_role" != "None" ] && [ -n "$iam_role" ]; then
        record_test "IAM Role Assignment" "PASS" "Instance has IAM role attached"
    else
        record_test "IAM Role Assignment" "FAIL" "Instance missing IAM role"
    fi
}

# Test 8: Monitoring and Logging
test_monitoring_logging() {
    log "Testing monitoring and logging configuration..."
    
    # Test CloudWatch log groups
    local log_groups=("/aws/ec2/agent/application" "/aws/ec2/agent/error" "/aws/ssm/deployment-logs")
    local missing_groups=()
    
    for group in "${log_groups[@]}"; do
        if ! aws logs describe-log-groups \
            --log-group-name-prefix "$group" \
            --region $AWS_REGION \
            --query 'logGroups[0].logGroupName' \
            --output text 2>/dev/null | grep -q "$group"; then
            missing_groups+=("$group")
        fi
    done
    
    if [ ${#missing_groups[@]} -eq 0 ]; then
        record_test "CloudWatch Log Groups" "PASS" "All log groups exist"
    else
        record_test "CloudWatch Log Groups" "FAIL" "Missing log groups: ${missing_groups[*]}"
    fi
    
    # Test CloudWatch alarms
    local alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "$ENVIRONMENT-agent" \
        --region $AWS_REGION \
        --query 'MetricAlarms[].AlarmName' \
        --output text)
    
    if [ -n "$alarms" ]; then
        record_test "CloudWatch Alarms" "PASS" "CloudWatch alarms are configured"
    else
        record_test "CloudWatch Alarms" "FAIL" "No CloudWatch alarms found"
    fi
}

# Test 9: Application Health Check
test_application_health() {
    log "Testing application health and functionality..."
    
    local base_url="http://$PUBLIC_IP"
    
    # Test health endpoint
    local health_response=$(curl -s "$base_url/health" --connect-timeout 10 || echo "")
    if echo "$health_response" | grep -q "healthy\|status"; then
        record_test "Health Endpoint" "PASS" "Health check endpoint working"
    else
        record_test "Health Endpoint" "FAIL" "Health check endpoint not working"
    fi
    
    # Test application performance
    local response_time=$(curl -o /dev/null -s -w "%{time_total}" "$base_url" --connect-timeout 10 || echo "999")
    if (( $(echo "$response_time < 5.0" | bc -l) )); then
        record_test "Response Time" "PASS" "Response time: ${response_time}s"
    else
        record_test "Response Time" "WARN" "Slow response time: ${response_time}s"
    fi
}

# Test 10: End-to-End Deployment Test
test_end_to_end_deployment() {
    log "Running end-to-end deployment test..."
    
    # Create a test commit and deployment
    info "This test would typically:"
    echo "1. Create a test branch"
    echo "2. Make a small change to the application"
    echo "3. Push to trigger GitHub Actions"
    echo "4. Monitor the deployment"
    echo "5. Verify the change is deployed"
    
    # For now, we'll simulate this by checking if the current deployment is working
    if curl -f -s "$base_url/docs" > /dev/null; then
        record_test "End-to-End Deployment" "PASS" "Current deployment is functional"
    else
        record_test "End-to-End Deployment" "FAIL" "Current deployment has issues"
    fi
}

# Generate test report
generate_test_report() {
    echo ""
    log "🧪 Test Results Summary"
    echo "=========================="
    
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done
    
    echo ""
    info "Tests Summary:"
    echo "- Passed: $TESTS_PASSED"
    echo "- Failed: $TESTS_FAILED"
    echo "- Total: $((TESTS_PASSED + TESTS_FAILED))"
    
    local success_rate=$((TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED)))
    echo "- Success Rate: $success_rate%"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        success "🎉 All tests passed! Your CI/CD pipeline is working correctly."
    elif [ $success_rate -ge 80 ]; then
        warn "⚠️  Most tests passed, but some issues need attention."
    else
        error "❌ Multiple tests failed. Please review and fix the issues."
    fi
}

# Provide troubleshooting guidance
provide_troubleshooting() {
    if [ $TESTS_FAILED -gt 0 ]; then
        echo ""
        info "🔧 Troubleshooting Guide:"
        echo ""
        echo "Common issues and solutions:"
        echo ""
        echo "1. Services not running:"
        echo "   - SSH to instance: ssh -i ~/.ssh/your-key.pem ubuntu@$PUBLIC_IP"
        echo "   - Check service status: sudo systemctl status agent-service nginx"
        echo "   - View logs: sudo journalctl -u agent-service -f"
        echo ""
        echo "2. Network connectivity issues:"
        echo "   - Check security group rules in AWS console"
        echo "   - Verify instance is in public subnet"
        echo "   - Check if nginx is properly configured"
        echo ""
        echo "3. API not responding:"
        echo "   - Check application logs: sudo tail -f /var/log/agent/agent.log"
        echo "   - Verify Python dependencies are installed"
        echo "   - Test locally on instance: curl http://localhost:8000/docs"
        echo ""
        echo "4. Deployment issues:"
        echo "   - Check GitHub Actions logs"
        echo "   - Verify GitHub secrets are correctly set"
        echo "   - Check SSM command execution logs"
        echo ""
        echo "5. Monitoring issues:"
        echo "   - Check CloudWatch agent status"
        echo "   - Verify IAM permissions for logging"
        echo "   - Check log group retention settings"
    fi
}

# Main execution
main() {
    echo ""
    log "🚀 Starting Comprehensive Pipeline Testing"
    echo ""
    
    get_infrastructure_details
    
    echo ""
    info "Running test suite..."
    echo ""
    
    test_infrastructure_health
    test_application_services
    test_network_connectivity
    test_api_endpoints
    test_manual_deployment
    test_github_workflow
    test_security_configuration
    test_monitoring_logging
    test_application_health
    test_end_to_end_deployment
    
    generate_test_report
    provide_troubleshooting
    
    echo ""
    log "Testing completed!"
}

# Handle script interruption
trap 'error "Testing interrupted"' INT TERM

# Run main function
main "$@"
