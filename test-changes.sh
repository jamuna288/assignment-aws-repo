#!/bin/bash

echo "🧪 Testing CI/CD Workflow Changes Locally"
echo "========================================"

cd Sample_Agent

echo "📦 Installing dependencies..."
pip3 install -r requirements.txt > /dev/null 2>&1

echo "🧪 Running unit tests..."
python3 -m pytest tests/ -v

echo ""
echo "🚀 Starting FastAPI server for quick test..."
echo "   (Will run for 10 seconds then stop)"

# Start the server in background
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 &
SERVER_PID=$!

# Wait for server to start
sleep 3

echo ""
echo "🔍 Testing endpoints..."

# Test root endpoint
echo "📍 Testing root endpoint:"
curl -s http://localhost:8000/ | python3 -m json.tool

echo ""
echo "📋 Testing version endpoint:"
curl -s http://localhost:8000/version | python3 -m json.tool

echo ""
echo "🏥 Testing health endpoint:"
curl -s http://localhost:8000/health | python3 -m json.tool

echo ""
echo "🤖 Testing recommendation endpoint:"
curl -s -X POST http://localhost:8000/recommendation \
  -H "Content-Type: application/json" \
  -d '{"input_text": "My flight is delayed by 2 hours"}' | python3 -m json.tool

# Stop the server
kill $SERVER_PID 2>/dev/null

echo ""
echo "✅ Local testing complete!"
echo ""
echo "🚀 Ready to commit and test CI/CD workflow:"
echo "   git add ."
echo "   git commit -m 'test: CI/CD workflow validation with dummy changes'"
echo "   git push origin main"
