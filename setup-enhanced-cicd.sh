#!/bin/bash

# 🚀 Enhanced CI/CD Setup Script
# Sets up complete CI/CD pipeline with rollback, versioning, and notifications

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
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

header() {
    echo -e "${PURPLE}$1${NC}"
}

# Display banner
show_banner() {
    echo -e "${PURPLE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║    🚀 Enhanced CI/CD Pipeline Setup                          ║
║                                                              ║
║    Features:                                                 ║
║    • Rollback mechanism on failed deployment                 ║
║    • AWS SSM deployment (no SSH keys needed)                ║
║    • Slack/Email/Teams notifications                         ║
║    • Versioning and tagging                                  ║
║    • Comprehensive logging and monitoring                    ║
║    • Security best practices                                 ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    header "🔍 Checking Prerequisites"
    echo "=========================="
    
    local missing_tools=()
    
    # Check required tools
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        warning "jq not found - installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            missing_tools+=("jq")
        fi
    fi
    
    # Check GitHub CLI
    if ! command -v gh &> /dev/null; then
        warning "GitHub CLI not found"
        info "Please install GitHub CLI from: https://cli.github.com/"
        info "Or run: curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
        info "Then: echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null"
        info "Finally: sudo apt update && sudo apt install gh"
        missing_tools+=("gh")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
        error "Please install the missing tools and run this script again"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Setup GitHub Secrets
setup_github_secrets() {
    header "🔐 Setting up GitHub Secrets"
    echo "============================="
    
    # Check if GitHub CLI is authenticated
    if ! gh auth status &> /dev/null; then
        warning "GitHub CLI not authenticated"
        echo "Please run: gh auth login"
        read -p "Press Enter after authenticating with GitHub CLI..."
    fi
    
    echo "This script will help you set up all required GitHub Secrets."
    echo "You can skip any secret that's already configured."
    echo ""
    
    # Function to add secret
    add_secret() {
        local secret_name="$1"
        local secret_description="$2"
        local secret_example="$3"
        local required="$4"
        
        # Check if secret already exists
        if gh secret list | grep -q "^$secret_name"; then
            success "$secret_name already configured"
            return 0
        fi
        
        echo ""
        echo "🔑 $secret_name"
        echo "Description: $secret_description"
        if [[ -n "$secret_example" ]]; then
            echo "Example: $secret_example"
        fi
        
        if [[ "$required" == "true" ]]; then
            echo "Status: REQUIRED"
        else
            echo "Status: Optional"
        fi
        
        read -p "Enter value for $secret_name (or press Enter to skip): " -r secret_value
        
        if [[ -n "$secret_value" ]]; then
            if gh secret set "$secret_name" --body "$secret_value"; then
                success "$secret_name added successfully"
            else
                error "Failed to add $secret_name"
            fi
        else
            if [[ "$required" == "true" ]]; then
                warning "$secret_name is required but was skipped"
            else
                info "$secret_name skipped"
            fi
        fi
    }
    
    # AWS Secrets
    echo "🔧 AWS Configuration Secrets:"
    add_secret "AWS_ACCESS_KEY_ID" "AWS Access Key ID for GitHub Actions" "AKIA1234567890ABCDEF" "true"
    add_secret "AWS_SECRET_ACCESS_KEY" "AWS Secret Access Key for GitHub Actions" "wJalrXUt..." "true"
    add_secret "AWS_REGION" "AWS Region where your resources are deployed" "us-east-1" "true"
    
    # EC2 Secrets
    echo ""
    echo "🖥️  EC2 Configuration Secrets:"
    add_secret "EC2_INSTANCE_ID" "EC2 Instance ID where the agent will be deployed" "i-1234567890abcdef0" "true"
    
    # S3 Secrets
    echo ""
    echo "📦 S3 Configuration Secrets:"
    add_secret "S3_DEPLOYMENT_BUCKET" "S3 bucket name for storing deployment artifacts" "my-agent-deployments-bucket" "true"
    
    # Environment
    echo ""
    echo "🌍 Environment Configuration:"
    add_secret "ENVIRONMENT" "Deployment environment tag" "production" "true"
    
    # Notification Secrets (Optional)
    echo ""
    echo "📢 Notification Secrets (Optional):"
    add_secret "SLACK_WEBHOOK_URL" "Slack webhook URL for deployment notifications" "https://hooks.slack.com/services/..." "false"
    add_secret "EMAIL_WEBHOOK_URL" "Email webhook URL for deployment notifications" "https://hooks.zapier.com/..." "false"
    add_secret "TEAMS_WEBHOOK_URL" "Microsoft Teams webhook URL for notifications" "https://outlook.office.com/webhook/..." "false"
    
    success "GitHub Secrets setup completed"
}

# Validate configuration
validate_configuration() {
    header "✅ Validating Configuration"
    echo "============================"
    
    local validation_errors=()
    
    # Check required secrets
    local required_secrets=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_REGION" "EC2_INSTANCE_ID" "S3_DEPLOYMENT_BUCKET" "ENVIRONMENT")
    
    for secret in "${required_secrets[@]}"; do
        if gh secret list | grep -q "^$secret"; then
            success "$secret is configured"
        else
            validation_errors+=("$secret is missing")
        fi
    done
    
    # Test AWS credentials (if possible)
    if command -v aws &> /dev/null; then
        log "Testing AWS credentials..."
        if aws sts get-caller-identity &> /dev/null; then
            success "AWS credentials are valid"
        else
            warning "AWS credentials test failed (this might be normal if using different credentials)"
        fi
    fi
    
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        error "Configuration validation failed:"
        for err in "${validation_errors[@]}"; do
            echo "  - $err"
        done
        return 1
    fi
    
    success "Configuration validation passed"
    return 0
}

# Setup notification channels
setup_notifications() {
    header "📢 Setting up Notifications"
    echo "==========================="
    
    echo "Would you like to set up notification channels?"
    echo "This will help you get notified about deployment status."
    echo ""
    
    read -p "Set up notifications? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f "scripts/setup-notifications.sh" ]]; then
            ./scripts/setup-notifications.sh
        else
            warning "Notification setup script not found"
            info "You can set up notifications manually by adding webhook URLs to GitHub Secrets"
        fi
    else
        info "Skipping notification setup"
    fi
}

# Create deployment documentation
create_documentation() {
    header "📚 Creating Documentation"
    echo "=========================="
    
    cat > DEPLOYMENT_GUIDE_ENHANCED.md << 'EOF'
# Enhanced CI/CD Deployment Guide

## 🚀 Features

This enhanced CI/CD pipeline provides:

- **Automatic Rollback**: Failed deployments automatically rollback to the previous version
- **AWS SSM Deployment**: Secure deployment without SSH keys
- **Versioning**: Semantic versioning with Git tags
- **Notifications**: Slack, Email, and Teams notifications
- **Health Checks**: Comprehensive deployment verification
- **Manual Rollback**: GitHub Actions workflow for manual rollbacks

## 🔄 Deployment Process

### Automatic Deployment
1. Push code to `main` branch
2. GitHub Actions triggers automatically
3. Tests run and code is packaged with version info
4. Deployment package uploaded to S3 with versioning
5. AWS SSM deploys to EC2 securely
6. Health checks verify deployment
7. Notifications sent on success/failure
8. Automatic rollback on failure

### Manual Rollback
```bash
# Via GitHub Actions (Recommended for production)
gh workflow run deploy-enhanced.yml -f action=rollback -f version=v2024.01.15-abc123

# Via local script (for testing)
./scripts/rollback-manager.sh rollback v2024.01.15-abc123
```

## 📋 Available Commands

### Rollback Manager
```bash
# List available backups
./scripts/rollback-manager.sh list

# Rollback to latest backup
./scripts/rollback-manager.sh rollback

# Rollback to specific version
./scripts/rollback-manager.sh rollback v2024.01.15-abc123

# Check current status
./scripts/rollback-manager.sh status

# Verify deployment health
./scripts/rollback-manager.sh verify

# Cleanup old backups
./scripts/rollback-manager.sh cleanup

# Trigger GitHub Actions rollback
./scripts/rollback-manager.sh github v2024.01.15-abc123
```

### Notification Testing
```bash
# Test all notification channels
./test-notifications.sh
```

## 🔐 Security Features

- No SSH keys stored in GitHub
- AWS SSM for secure deployment
- Least privilege IAM policies
- Encrypted S3 storage
- Secure webhook notifications

## 📊 Monitoring

- CloudWatch logs for all deployments
- Health check endpoints
- Deployment status tracking
- Version information in all deployments

## 🆘 Troubleshooting

### Common Issues

1. **Deployment Fails**
   - Check GitHub Actions logs
   - Verify AWS credentials and permissions
   - Check EC2 instance SSM agent status

2. **Rollback Needed**
   - Use GitHub Actions rollback workflow
   - Or use local rollback manager script

3. **Notifications Not Working**
   - Verify webhook URLs in GitHub Secrets
   - Test webhooks manually
   - Check network connectivity

### Support Commands
```bash
# Check service status
sudo systemctl status agent-service

# View logs
tail -f /opt/agent/logs/agent.log

# Check deployment history
ls -la /opt/agent/releases/

# Manual health check
curl http://localhost:8000/health
```

## 📈 Best Practices

1. Always test in staging before production
2. Monitor deployment notifications
3. Keep backup retention policy (default: 10 backups)
4. Regular health checks
5. Document any manual interventions
6. Use semantic versioning
7. Test rollback procedures regularly

EOF

    success "Created DEPLOYMENT_GUIDE_ENHANCED.md"
    
    # Create quick reference
    cat > QUICK_REFERENCE.md << 'EOF'
# Quick Reference - Enhanced CI/CD

## 🚀 Deployment Commands

```bash
# Trigger deployment
git push origin main

# Manual rollback via GitHub Actions
gh workflow run deploy-enhanced.yml -f action=rollback -f version=VERSION

# Local rollback
./scripts/rollback-manager.sh rollback VERSION

# Check status
./scripts/rollback-manager.sh status

# List backups
./scripts/rollback-manager.sh list
```

## 📱 Notification Setup

```bash
# Setup all notifications
./scripts/setup-notifications.sh

# Test notifications
./test-notifications.sh
```

## 🔐 Required GitHub Secrets

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY` 
- `AWS_REGION`
- `EC2_INSTANCE_ID`
- `S3_DEPLOYMENT_BUCKET`
- `ENVIRONMENT`

## 📞 Emergency Procedures

```bash
# Emergency rollback
./scripts/rollback-manager.sh rollback --force

# Check service health
curl http://YOUR_EC2_IP/health

# View recent logs
tail -f /opt/agent/logs/agent.log
```

EOF

    success "Created QUICK_REFERENCE.md"
}

# Display summary
show_summary() {
    header "🎉 Setup Complete!"
    echo "=================="
    
    echo ""
    echo "✅ Enhanced CI/CD Pipeline Features:"
    echo "  • Automatic rollback on deployment failure"
    echo "  • AWS SSM deployment (no SSH keys needed)"
    echo "  • Versioning and tagging system"
    echo "  • Comprehensive health checks"
    echo "  • Notification system (Slack/Email/Teams)"
    echo "  • Manual rollback capabilities"
    echo "  • Security best practices"
    echo ""
    
    echo "📋 What's been set up:"
    echo "  • Enhanced GitHub Actions workflow"
    echo "  • GitHub Secrets configuration"
    echo "  • Rollback management system"
    echo "  • Notification channels"
    echo "  • Documentation and guides"
    echo ""
    
    echo "🚀 Next Steps:"
    echo "  1. Test the deployment: git commit -m 'test' && git push origin main"
    echo "  2. Monitor notifications in your configured channels"
    echo "  3. Test rollback: ./scripts/rollback-manager.sh list"
    echo "  4. Review documentation: DEPLOYMENT_GUIDE_ENHANCED.md"
    echo ""
    
    echo "📚 Available Commands:"
    echo "  • ./scripts/rollback-manager.sh --help"
    echo "  • ./scripts/setup-notifications.sh"
    echo "  • ./test-notifications.sh"
    echo ""
    
    echo "🌐 Workflow Files:"
    echo "  • .github/workflows/deploy-enhanced.yml (Enhanced CI/CD)"
    echo "  • .github/workflows/deploy.yml (Original - can be removed)"
    echo ""
    
    success "Your enhanced CI/CD pipeline is ready!"
    info "Push code to 'main' branch to trigger your first enhanced deployment"
}

# Main execution
main() {
    show_banner
    
    log "Starting Enhanced CI/CD Setup..."
    
    # Run setup steps
    check_prerequisites
    setup_github_secrets
    
    if validate_configuration; then
        setup_notifications
        create_documentation
        show_summary
        
        success "Enhanced CI/CD setup completed successfully!"
        
        echo ""
        read -p "Would you like to commit and push these changes now? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Committing and pushing changes..."
            git add .
            git commit -m "🚀 Implement Enhanced CI/CD Pipeline

✨ Features Added:
- Automatic rollback on deployment failure
- AWS SSM deployment (no SSH keys needed)
- Versioning and tagging system
- Slack/Email/Teams notifications
- Comprehensive health checks
- Manual rollback capabilities
- Security best practices

🔧 Components:
- Enhanced GitHub Actions workflow
- Rollback management system
- Notification setup scripts
- Comprehensive documentation
- Security templates and guides

Ready for production deployment with enterprise-grade CI/CD!"
            
            git push origin main
            
            success "Changes committed and pushed!"
            info "Your enhanced deployment will start automatically"
        else
            info "Changes ready to commit. Run 'git add . && git commit && git push' when ready"
        fi
        
    else
        error "Configuration validation failed. Please fix the issues and run again."
        exit 1
    fi
}

# Run main function
main "$@"
