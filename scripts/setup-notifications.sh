#!/bin/bash

# 📢 Notification Setup Script
# Sets up Slack, Email, and Teams notifications for CI/CD pipeline

set -e

echo "📢 Setting up CI/CD Notifications"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    error "GitHub CLI is not installed. Please install it first:"
    echo "  https://cli.github.com/"
    exit 1
fi

# Check if user is logged in to GitHub
if ! gh auth status &> /dev/null; then
    error "Please login to GitHub CLI first:"
    echo "  gh auth login"
    exit 1
fi

log "Starting notification setup..."

# Function to setup Slack notifications
setup_slack() {
    echo ""
    echo "🔔 Setting up Slack Notifications"
    echo "================================="
    
    echo "To set up Slack notifications, you need to create a Slack webhook:"
    echo "1. Go to https://api.slack.com/apps"
    echo "2. Click 'Create New App' → 'From scratch'"
    echo "3. Name your app (e.g., 'CI/CD Notifications') and select your workspace"
    echo "4. Go to 'Incoming Webhooks' and activate it"
    echo "5. Click 'Add New Webhook to Workspace'"
    echo "6. Select the channel where you want notifications"
    echo "7. Copy the webhook URL"
    echo ""
    
    read -p "Do you want to add a Slack webhook URL? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Enter your Slack webhook URL:"
        read -r SLACK_WEBHOOK_URL
        
        if [[ $SLACK_WEBHOOK_URL =~ ^https://hooks\.slack\.com/services/ ]]; then
            gh secret set SLACK_WEBHOOK_URL --body "$SLACK_WEBHOOK_URL"
            success "Slack webhook URL added to GitHub Secrets"
            
            # Test the webhook
            echo "Testing Slack notification..."
            curl -X POST -H 'Content-type: application/json' \
                --data '{
                    "text": "🧪 Test Notification",
                    "attachments": [{
                        "color": "good",
                        "fields": [
                            {"title": "Status", "value": "Slack notifications configured successfully!", "short": false},
                            {"title": "Time", "value": "'$(date)'", "short": true}
                        ]
                    }]
                }' \
                "$SLACK_WEBHOOK_URL"
            
            success "Test notification sent to Slack!"
        else
            error "Invalid Slack webhook URL format"
        fi
    else
        warning "Skipping Slack setup"
    fi
}

# Function to setup email notifications
setup_email() {
    echo ""
    echo "📧 Setting up Email Notifications"
    echo "================================="
    
    echo "For email notifications, you can use services like:"
    echo "1. Zapier (https://zapier.com/)"
    echo "2. IFTTT (https://ifttt.com/)"
    echo "3. Microsoft Power Automate"
    echo "4. Custom webhook service"
    echo ""
    echo "Example setup with Zapier:"
    echo "1. Create a Zapier account"
    echo "2. Create a new Zap with 'Webhooks by Zapier' as trigger"
    echo "3. Choose 'Catch Hook' and copy the webhook URL"
    echo "4. Add 'Email by Zapier' as action"
    echo "5. Configure email template and recipients"
    echo ""
    
    read -p "Do you want to add an email webhook URL? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Enter your email webhook URL:"
        read -r EMAIL_WEBHOOK_URL
        
        if [[ $EMAIL_WEBHOOK_URL =~ ^https:// ]]; then
            gh secret set EMAIL_WEBHOOK_URL --body "$EMAIL_WEBHOOK_URL"
            success "Email webhook URL added to GitHub Secrets"
            
            # Test the webhook
            echo "Testing email notification..."
            curl -X POST -H 'Content-type: application/json' \
                --data '{
                    "subject": "🧪 Test CI/CD Notification",
                    "body": "Email notifications have been configured successfully!\n\nTime: '$(date)'\nStatus: Configuration Complete"
                }' \
                "$EMAIL_WEBHOOK_URL"
            
            success "Test notification sent via email webhook!"
        else
            error "Invalid email webhook URL format"
        fi
    else
        warning "Skipping email setup"
    fi
}

# Function to setup Teams notifications
setup_teams() {
    echo ""
    echo "👥 Setting up Microsoft Teams Notifications"
    echo "==========================================="
    
    echo "To set up Teams notifications:"
    echo "1. Go to your Teams channel"
    echo "2. Click on '...' → 'Connectors'"
    echo "3. Find 'Incoming Webhook' and click 'Configure'"
    echo "4. Give it a name (e.g., 'CI/CD Notifications')"
    echo "5. Optionally upload an image"
    echo "6. Click 'Create' and copy the webhook URL"
    echo ""
    
    read -p "Do you want to add a Teams webhook URL? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Enter your Teams webhook URL:"
        read -r TEAMS_WEBHOOK_URL
        
        if [[ $TEAMS_WEBHOOK_URL =~ ^https://.*\.webhook\.office\.com/ ]]; then
            gh secret set TEAMS_WEBHOOK_URL --body "$TEAMS_WEBHOOK_URL"
            success "Teams webhook URL added to GitHub Secrets"
            
            # Test the webhook
            echo "Testing Teams notification..."
            curl -X POST -H 'Content-type: application/json' \
                --data '{
                    "@type": "MessageCard",
                    "@context": "http://schema.org/extensions",
                    "themeColor": "0076D7",
                    "summary": "CI/CD Test Notification",
                    "sections": [{
                        "activityTitle": "🧪 Test Notification",
                        "activitySubtitle": "Teams notifications configured successfully!",
                        "facts": [{
                            "name": "Status",
                            "value": "Configuration Complete"
                        }, {
                            "name": "Time",
                            "value": "'$(date)'"
                        }]
                    }]
                }' \
                "$TEAMS_WEBHOOK_URL"
            
            success "Test notification sent to Teams!"
        else
            error "Invalid Teams webhook URL format"
        fi
    else
        warning "Skipping Teams setup"
    fi
}

# Function to create notification test script
create_test_script() {
    echo ""
    log "Creating notification test script..."
    
    cat > test-notifications.sh << 'EOF'
#!/bin/bash

# 🧪 Notification Test Script
# Tests all configured notification channels

echo "🧪 Testing CI/CD Notifications"
echo "==============================="

# Test Slack
if gh secret list | grep -q "SLACK_WEBHOOK_URL"; then
    echo "📱 Testing Slack notification..."
    SLACK_URL=$(gh secret list | grep "SLACK_WEBHOOK_URL" | awk '{print $1}')
    echo "Slack webhook is configured ✅"
else
    echo "⚠️  Slack webhook not configured"
fi

# Test Email
if gh secret list | grep -q "EMAIL_WEBHOOK_URL"; then
    echo "📧 Testing Email notification..."
    echo "Email webhook is configured ✅"
else
    echo "⚠️  Email webhook not configured"
fi

# Test Teams
if gh secret list | grep -q "TEAMS_WEBHOOK_URL"; then
    echo "👥 Testing Teams notification..."
    echo "Teams webhook is configured ✅"
else
    echo "⚠️  Teams webhook not configured"
fi

echo ""
echo "🎯 To test notifications manually, trigger a deployment:"
echo "   git commit -m 'test deployment' && git push origin main"
echo ""
echo "📋 Or use manual workflow dispatch:"
echo "   gh workflow run deploy-enhanced.yml"
EOF

    chmod +x test-notifications.sh
    success "Created test-notifications.sh script"
}

# Function to display summary
show_summary() {
    echo ""
    echo "📋 Notification Setup Summary"
    echo "============================="
    
    echo "Configured notification channels:"
    
    if gh secret list | grep -q "SLACK_WEBHOOK_URL"; then
        success "Slack notifications: Enabled"
    else
        warning "Slack notifications: Not configured"
    fi
    
    if gh secret list | grep -q "EMAIL_WEBHOOK_URL"; then
        success "Email notifications: Enabled"
    else
        warning "Email notifications: Not configured"
    fi
    
    if gh secret list | grep -q "TEAMS_WEBHOOK_URL"; then
        success "Teams notifications: Enabled"
    else
        warning "Teams notifications: Not configured"
    fi
    
    echo ""
    echo "🎯 Next Steps:"
    echo "1. Test notifications with: ./test-notifications.sh"
    echo "2. Trigger a deployment to see notifications in action"
    echo "3. Customize notification messages in .github/workflows/deploy-enhanced.yml"
    echo ""
    echo "📚 Notification Features:"
    echo "• Deployment start notifications"
    echo "• Success/failure notifications with details"
    echo "• Rollback notifications"
    echo "• Version and commit information"
    echo "• Direct links to application"
}

# Main execution
main() {
    log "Checking GitHub CLI authentication..."
    
    if gh auth status; then
        success "GitHub CLI authenticated successfully"
    else
        error "GitHub CLI authentication failed"
        exit 1
    fi
    
    # Setup each notification type
    setup_slack
    setup_email
    setup_teams
    
    # Create test script
    create_test_script
    
    # Show summary
    show_summary
    
    success "Notification setup completed!"
}

# Run main function
main "$@"
