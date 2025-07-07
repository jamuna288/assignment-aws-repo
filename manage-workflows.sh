#!/bin/bash

echo "🔧 GitHub Actions Workflow Management"
echo "===================================="

echo ""
echo "Current workflows:"
echo "1. deploy.yml - Basic deployment workflow"
echo "2. deploy-enhanced.yml - Enhanced deployment with rollback & notifications"

echo ""
echo "Options:"
echo "1. Use only Enhanced workflow (disable basic)"
echo "2. Use only Basic workflow (disable enhanced)"
echo "3. Keep both workflows (current state)"
echo "4. Delete basic workflow completely"

echo ""
read -p "Choose option (1-4): " choice

case $choice in
    1)
        echo "✅ Disabling basic workflow..."
        # Already done above
        echo "Basic workflow disabled. Only enhanced workflow will run."
        ;;
    2)
        echo "✅ Disabling enhanced workflow..."
        sed -i.bak 's/^on:/# on:/' .github/workflows/deploy-enhanced.yml
        sed -i.bak '/^# on:/a\
on:\
  workflow_dispatch:' .github/workflows/deploy-enhanced.yml
        echo "Enhanced workflow disabled. Only basic workflow will run."
        ;;
    3)
        echo "✅ Keeping both workflows active."
        echo "⚠️  Note: Both will run on every push to main branch."
        ;;
    4)
        echo "✅ Deleting basic workflow..."
        rm .github/workflows/deploy.yml
        echo "Basic workflow deleted. Only enhanced workflow remains."
        ;;
    *)
        echo "❌ Invalid option. No changes made."
        exit 1
        ;;
esac

echo ""
echo "🚀 Current active workflows:"
ls -la .github/workflows/

echo ""
echo "💡 Recommendation: Use option 1 (Enhanced workflow only) for best features."
