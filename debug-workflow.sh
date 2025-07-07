#!/bin/bash

echo "🔍 GitHub Actions Workflow Diagnostics"
echo "======================================"

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install gh
    else
        echo "Please install GitHub CLI: https://cli.github.com/"
        exit 1
    fi
fi

# Check authentication
echo "🔐 Checking GitHub authentication..."
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated. Please run: gh auth login"
    exit 1
fi

echo "✅ GitHub CLI authenticated"

# List recent workflow runs
echo ""
echo "📋 Recent workflow runs:"
gh run list --limit 5

# Get the latest run details
echo ""
echo "🔍 Latest workflow run details:"
LATEST_RUN=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')

if [ -n "$LATEST_RUN" ]; then
    echo "Run ID: $LATEST_RUN"
    gh run view $LATEST_RUN
    
    echo ""
    echo "📝 Would you like to see the full logs? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        gh run view $LATEST_RUN --log
    fi
else
    echo "❌ No workflow runs found"
fi

# Check repository secrets (this will show if secrets exist, not their values)
echo ""
echo "🔑 Checking repository configuration..."
echo "Repository: $(gh repo view --json nameWithOwner --jq '.nameWithOwner')"

# Check if workflow files exist
echo ""
echo "📁 Checking workflow files..."
if [ -f ".github/workflows/deploy-enhanced.yml" ]; then
    echo "✅ Enhanced deployment workflow found"
elif [ -f ".github/workflows/deploy.yml" ]; then
    echo "✅ Basic deployment workflow found"
else
    echo "❌ No deployment workflow found"
fi

echo ""
echo "💡 Common issues to check:"
echo "1. GitHub Secrets: Go to Settings → Secrets and variables → Actions"
echo "2. Required secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, EC2_INSTANCE_ID, S3_DEPLOYMENT_BUCKET"
echo "3. AWS permissions: Ensure GitHub Actions IAM user has proper permissions"
echo "4. EC2 instance: Ensure instance is running and accessible"
echo "5. S3 bucket: Ensure deployment bucket exists and is accessible"

echo ""
echo "🌐 Quick links:"
echo "- GitHub Actions: https://github.com/$(gh repo view --json nameWithOwner --jq -r '.nameWithOwner')/actions"
echo "- Repository Settings: https://github.com/$(gh repo view --json nameWithOwner --jq -r '.nameWithOwner')/settings"
echo "- Secrets: https://github.com/$(gh repo view --json nameWithOwner --jq -r '.nameWithOwner')/settings/secrets/actions"
