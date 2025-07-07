#!/bin/bash

echo "🔍 GitHub Secrets Status Check"
echo "============================="

# Check if GitHub CLI is available
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI not found. Install with: brew install gh"
    echo ""
    echo "📋 Required secrets for the workflow:"
    echo "- AWS_ACCESS_KEY_ID"
    echo "- AWS_SECRET_ACCESS_KEY" 
    echo "- AWS_REGION (now hardcoded to us-east-1)"
    echo "- EC2_INSTANCE_ID"
    echo "- S3_DEPLOYMENT_BUCKET"
    echo "- ENVIRONMENT"
    echo ""
    echo "🌐 Add secrets at: https://github.com/jamuna288/assignment-aws-repo/settings/secrets/actions"
    exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub. Run: gh auth login"
    exit 1
fi

echo "✅ GitHub CLI authenticated"
echo ""

# List repository secrets (this won't show values, just names)
echo "🔑 Checking repository secrets..."
echo ""

# Get repository info
REPO=$(gh repo view --json nameWithOwner --jq -r '.nameWithOwner')
echo "Repository: $REPO"

echo ""
echo "📋 Required secrets status:"

# Required secrets
REQUIRED_SECRETS=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "EC2_INSTANCE_ID"
    "S3_DEPLOYMENT_BUCKET"
    "ENVIRONMENT"
)

# Note: GitHub CLI doesn't provide a direct way to list secrets
# So we'll provide instructions instead

echo ""
echo "⚠️  Note: GitHub doesn't allow listing secret names via CLI for security."
echo "   Please manually verify these secrets exist in your repository:"
echo ""

for secret in "${REQUIRED_SECRETS[@]}"; do
    echo "   □ $secret"
done

echo ""
echo "🌐 Check/Add secrets at:"
echo "   https://github.com/$REPO/settings/secrets/actions"

echo ""
echo "🚀 Recent workflow runs:"
gh run list --limit 3

echo ""
echo "💡 To create AWS credentials automatically:"
echo "   ./setup-github-credentials.sh"
