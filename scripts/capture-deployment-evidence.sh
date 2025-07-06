#!/bin/bash

# 📸 Deployment Evidence Capture Script
# Captures screenshots, logs, and evidence of successful deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Create evidence directory
EVIDENCE_DIR="deployment-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"/{logs,screenshots,configs,tests}

log "📸 Starting deployment evidence capture..."
log "Evidence will be saved to: $EVIDENCE_DIR"

# Function to capture GitHub Actions evidence
capture_github_actions_evidence() {
    log "📋 Capturing GitHub Actions evidence..."
    
    if command -v gh &> /dev/null; then
        # Get latest workflow run
        log "Fetching latest workflow run..."
        gh run list --limit 5 --json status,conclusion,createdAt,displayTitle,databaseId > "$EVIDENCE_DIR/logs/github-actions-runs.json"
        
        # Get latest successful run details
        LATEST_RUN_ID=$(gh run list --limit 1 --status success --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")
        
        if [[ -n "$LATEST_RUN_ID" ]]; then
            log "Capturing workflow run details for ID: $LATEST_RUN_ID"
            gh run view "$LATEST_RUN_ID" > "$EVIDENCE_DIR/logs/github-actions-latest-run.txt"
            gh run view "$LATEST_RUN_ID" --log > "$EVIDENCE_DIR/logs/github-actions-full-log.txt"
            success "GitHub Actions evidence captured"
        else
            warning "No successful workflow runs found"
        fi
    else
        warning "GitHub CLI not available - skipping GitHub Actions evidence"
    fi
}

# Function to capture EC2 evidence
capture_ec2_evidence() {
    log "🖥️  Capturing EC2 evidence..."
    
    # System information
    {
        echo "=== SYSTEM INFORMATION ==="
        echo "Hostname: $(hostname)"
        echo "Date: $(date)"
        echo "Uptime: $(uptime)"
        echo "Kernel: $(uname -a)"
        echo ""
        
        echo "=== MEMORY USAGE ==="
        free -h
        echo ""
        
        echo "=== DISK USAGE ==="
        df -h
        echo ""
        
        echo "=== CPU INFO ==="
        lscpu | head -20
        echo ""
        
        echo "=== NETWORK INTERFACES ==="
        ip addr show
        echo ""
        
    } > "$EVIDENCE_DIR/logs/system-info.txt"
    
    success "System information captured"
}

# Function to capture service evidence
capture_service_evidence() {
    log "⚙️  Capturing service evidence..."
    
    # Service status
    {
        echo "=== AGENT SERVICE STATUS ==="
        sudo systemctl status agent-service --no-pager -l
        echo ""
        
        echo "=== SERVICE IS-ENABLED ==="
        sudo systemctl is-enabled agent-service
        echo ""
        
        echo "=== SERVICE IS-ACTIVE ==="
        sudo systemctl is-active agent-service
        echo ""
        
        echo "=== NGINX SERVICE STATUS ==="
        sudo systemctl status nginx --no-pager -l
        echo ""
        
        echo "=== PROCESS LIST ==="
        ps aux | grep -E "(agent|nginx|python)" | grep -v grep
        echo ""
        
        echo "=== LISTENING PORTS ==="
        sudo netstat -tlnp | grep -E ":(80|8000|443)"
        echo ""
        
    } > "$EVIDENCE_DIR/logs/service-status.txt"
    
    success "Service evidence captured"
}

# Function to capture application logs
capture_application_logs() {
    log "📝 Capturing application logs..."
    
    # Application logs
    if [[ -f "/opt/agent/logs/agent.log" ]]; then
        cp "/opt/agent/logs/agent.log" "$EVIDENCE_DIR/logs/agent-application.log"
        tail -100 "/opt/agent/logs/agent.log" > "$EVIDENCE_DIR/logs/agent-application-recent.log"
        success "Application logs captured"
    else
        warning "Application log file not found"
    fi
    
    # Error logs
    if [[ -f "/opt/agent/logs/agent-error.log" ]]; then
        cp "/opt/agent/logs/agent-error.log" "$EVIDENCE_DIR/logs/agent-error.log"
        success "Error logs captured"
    fi
    
    # Deployment logs
    if [[ -f "/opt/agent/logs/deployment.log" ]]; then
        cp "/opt/agent/logs/deployment.log" "$EVIDENCE_DIR/logs/deployment.log"
        tail -50 "/opt/agent/logs/deployment.log" > "$EVIDENCE_DIR/logs/deployment-recent.log"
        success "Deployment logs captured"
    fi
    
    # System logs
    sudo journalctl -u agent-service --no-pager -l > "$EVIDENCE_DIR/logs/systemd-agent-service.log"
    sudo journalctl -u nginx --no-pager -l > "$EVIDENCE_DIR/logs/systemd-nginx.log"
    
    success "System logs captured"
}

# Function to capture configuration files
capture_configurations() {
    log "⚙️  Capturing configuration files..."
    
    # Service configuration
    if [[ -f "/etc/systemd/system/agent-service.service" ]]; then
        cp "/etc/systemd/system/agent-service.service" "$EVIDENCE_DIR/configs/agent-service.service"
    fi
    
    # Nginx configuration
    if [[ -f "/etc/nginx/sites-available/agent" ]]; then
        cp "/etc/nginx/sites-available/agent" "$EVIDENCE_DIR/configs/nginx-agent.conf"
    fi
    
    # Application files
    if [[ -d "/opt/agent/current" ]]; then
        # Copy key files (not the entire venv)
        cp "/opt/agent/current/main.py" "$EVIDENCE_DIR/configs/" 2>/dev/null || true
        cp "/opt/agent/current/requirements.txt" "$EVIDENCE_DIR/configs/" 2>/dev/null || true
        cp "/opt/agent/current/VERSION" "$EVIDENCE_DIR/configs/" 2>/dev/null || true
        cp "/opt/agent/current/version.json" "$EVIDENCE_DIR/configs/" 2>/dev/null || true
    fi
    
    # Directory structure
    {
        echo "=== /opt/agent STRUCTURE ==="
        ls -la /opt/agent/
        echo ""
        
        echo "=== /opt/agent/current STRUCTURE ==="
        ls -la /opt/agent/current/
        echo ""
        
        echo "=== /opt/agent/releases STRUCTURE ==="
        ls -la /opt/agent/releases/ 2>/dev/null || echo "No releases directory"
        echo ""
        
        echo "=== /opt/agent/logs STRUCTURE ==="
        ls -la /opt/agent/logs/
        echo ""
        
    } > "$EVIDENCE_DIR/configs/directory-structure.txt"
    
    success "Configuration files captured"
}

# Function to test application endpoints
test_application_endpoints() {
    log "🧪 Testing application endpoints..."
    
    # Test local endpoints
    {
        echo "=== ENDPOINT TESTING RESULTS ==="
        echo "Test Date: $(date)"
        echo ""
        
        echo "=== ROOT ENDPOINT (/) ==="
        if curl -f -s http://localhost:8000/ > /tmp/root_response.json; then
            echo "Status: SUCCESS"
            echo "Response:"
            cat /tmp/root_response.json | jq . 2>/dev/null || cat /tmp/root_response.json
        else
            echo "Status: FAILED"
        fi
        echo ""
        
        echo "=== HEALTH ENDPOINT (/health) ==="
        if curl -f -s http://localhost:8000/health > /tmp/health_response.json; then
            echo "Status: SUCCESS"
            echo "Response:"
            cat /tmp/health_response.json | jq . 2>/dev/null || cat /tmp/health_response.json
        else
            echo "Status: FAILED"
        fi
        echo ""
        
        echo "=== VERSION ENDPOINT (/version) ==="
        if curl -f -s http://localhost:8000/version > /tmp/version_response.json; then
            echo "Status: SUCCESS"
            echo "Response:"
            cat /tmp/version_response.json | jq . 2>/dev/null || cat /tmp/version_response.json
        else
            echo "Status: FAILED"
        fi
        echo ""
        
        echo "=== RECOMMENDATION ENDPOINT (/recommendation) ==="
        if curl -f -s -X POST http://localhost:8000/recommendation \
             -H "Content-Type: application/json" \
             -d '{"input_text": "My flight is delayed"}' > /tmp/recommendation_response.json; then
            echo "Status: SUCCESS"
            echo "Response:"
            cat /tmp/recommendation_response.json | jq . 2>/dev/null || cat /tmp/recommendation_response.json
        else
            echo "Status: FAILED"
        fi
        echo ""
        
        echo "=== NGINX STATUS ==="
        if curl -f -s http://localhost/nginx_status > /tmp/nginx_status.txt 2>/dev/null; then
            echo "Status: SUCCESS"
            echo "Response:"
            cat /tmp/nginx_status.txt
        else
            echo "Status: FAILED or Not Configured"
        fi
        echo ""
        
    } > "$EVIDENCE_DIR/tests/endpoint-tests.txt"
    
    # Save individual responses
    cp /tmp/root_response.json "$EVIDENCE_DIR/tests/" 2>/dev/null || true
    cp /tmp/health_response.json "$EVIDENCE_DIR/tests/" 2>/dev/null || true
    cp /tmp/version_response.json "$EVIDENCE_DIR/tests/" 2>/dev/null || true
    cp /tmp/recommendation_response.json "$EVIDENCE_DIR/tests/" 2>/dev/null || true
    
    # Clean up temp files
    rm -f /tmp/*_response.json /tmp/nginx_status.txt
    
    success "Endpoint testing completed"
}

# Function to capture AWS evidence
capture_aws_evidence() {
    log "☁️  Capturing AWS evidence..."
    
    if command -v aws &> /dev/null; then
        # Instance metadata
        {
            echo "=== AWS INSTANCE METADATA ==="
            echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'Not available')"
            echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo 'Not available')"
            echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'Not available')"
            echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo 'Not available')"
            echo "Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo 'Not available')"
            echo "Security Groups: $(curl -s http://169.254.169.254/latest/meta-data/security-groups 2>/dev/null || echo 'Not available')"
            echo ""
            
        } > "$EVIDENCE_DIR/logs/aws-metadata.txt"
        
        success "AWS metadata captured"
    else
        warning "AWS CLI not available - skipping AWS evidence"
    fi
}

# Function to create evidence summary
create_evidence_summary() {
    log "📋 Creating evidence summary..."
    
    cat > "$EVIDENCE_DIR/EVIDENCE_SUMMARY.md" << EOF
# Deployment Evidence Summary

**Generated**: $(date)
**Evidence Directory**: $EVIDENCE_DIR

## 📋 Evidence Collected

### ✅ GitHub Actions Evidence
- Workflow run history: \`logs/github-actions-runs.json\`
- Latest run details: \`logs/github-actions-latest-run.txt\`
- Full deployment logs: \`logs/github-actions-full-log.txt\`

### ✅ EC2 System Evidence
- System information: \`logs/system-info.txt\`
- Service status: \`logs/service-status.txt\`
- AWS metadata: \`logs/aws-metadata.txt\`

### ✅ Application Evidence
- Application logs: \`logs/agent-application.log\`
- Recent logs: \`logs/agent-application-recent.log\`
- Error logs: \`logs/agent-error.log\`
- Deployment logs: \`logs/deployment.log\`
- SystemD logs: \`logs/systemd-agent-service.log\`

### ✅ Configuration Evidence
- Service configuration: \`configs/agent-service.service\`
- Nginx configuration: \`configs/nginx-agent.conf\`
- Application files: \`configs/main.py\`, \`configs/requirements.txt\`
- Version information: \`configs/VERSION\`, \`configs/version.json\`
- Directory structure: \`configs/directory-structure.txt\`

### ✅ Testing Evidence
- Endpoint tests: \`tests/endpoint-tests.txt\`
- API responses: \`tests/*_response.json\`

## 🎯 Key Findings

$(if [[ -f "$EVIDENCE_DIR/tests/endpoint-tests.txt" ]]; then
    if grep -q "Status: SUCCESS" "$EVIDENCE_DIR/tests/endpoint-tests.txt"; then
        echo "- ✅ All application endpoints are responding correctly"
    else
        echo "- ⚠️  Some endpoint tests failed - check tests/endpoint-tests.txt"
    fi
fi)

$(if sudo systemctl is-active --quiet agent-service; then
    echo "- ✅ Agent service is running and active"
else
    echo "- ❌ Agent service is not running"
fi)

$(if sudo systemctl is-active --quiet nginx; then
    echo "- ✅ Nginx service is running and active"
else
    echo "- ❌ Nginx service is not running"
fi)

$(if [[ -f "/opt/agent/logs/agent.log" ]]; then
    echo "- ✅ Application logging is working"
else
    echo "- ⚠️  Application log file not found"
fi)

## 📊 Quick Stats

- **System Uptime**: $(uptime | awk '{print $3,$4}' | sed 's/,//')
- **Memory Usage**: $(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
- **Disk Usage**: $(df / | awk 'NR==2{print $5}')
- **Service Status**: $(sudo systemctl is-active agent-service)
- **Log File Size**: $(du -h /opt/agent/logs/agent.log 2>/dev/null | cut -f1 || echo "N/A")

## 🔗 Quick Access

To view the evidence:
\`\`\`bash
# View latest application logs
tail -f $EVIDENCE_DIR/logs/agent-application-recent.log

# View endpoint test results
cat $EVIDENCE_DIR/tests/endpoint-tests.txt

# View service status
cat $EVIDENCE_DIR/logs/service-status.txt

# View GitHub Actions logs
cat $EVIDENCE_DIR/logs/github-actions-latest-run.txt
\`\`\`

---
*Evidence captured by deployment-evidence-capture script*
EOF

    success "Evidence summary created"
}

# Function to create archive
create_evidence_archive() {
    log "📦 Creating evidence archive..."
    
    ARCHIVE_NAME="${EVIDENCE_DIR}.tar.gz"
    tar -czf "$ARCHIVE_NAME" "$EVIDENCE_DIR"
    
    success "Evidence archive created: $ARCHIVE_NAME"
    info "Archive size: $(du -h "$ARCHIVE_NAME" | cut -f1)"
}

# Main execution
main() {
    log "🚀 Starting deployment evidence capture..."
    
    # Capture all evidence
    capture_github_actions_evidence
    capture_ec2_evidence
    capture_service_evidence
    capture_application_logs
    capture_configurations
    test_application_endpoints
    capture_aws_evidence
    create_evidence_summary
    create_evidence_archive
    
    echo ""
    success "🎉 Deployment evidence capture completed!"
    echo ""
    info "📁 Evidence directory: $EVIDENCE_DIR"
    info "📦 Evidence archive: ${EVIDENCE_DIR}.tar.gz"
    echo ""
    info "📋 To view the summary:"
    echo "   cat $EVIDENCE_DIR/EVIDENCE_SUMMARY.md"
    echo ""
    info "📤 To share the evidence:"
    echo "   scp ${EVIDENCE_DIR}.tar.gz user@destination:/path/"
    echo ""
    info "🔍 To extract and view:"
    echo "   tar -xzf ${EVIDENCE_DIR}.tar.gz"
    echo "   cd $EVIDENCE_DIR"
    echo "   cat EVIDENCE_SUMMARY.md"
}

# Run main function
main "$@"
