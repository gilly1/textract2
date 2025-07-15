#!/bin/bash

echo "🔧 Deploying Lambda fix for 422 error..."

# Rebuild Lambda package with improved data handling
cd lambda
echo "📦 Rebuilding Lambda package..."
zip -r ../lambda_function.zip . -x "*.pyc" "__pycache__/*"
cd ..

# Deploy Lambda function
echo "🚀 Deploying updated Lambda function..."
aws lambda update-function-code \
    --function-name document-processor-dynamodb-trigger \
    --zip-file fileb://lambda_function.zip

if [ $? -eq 0 ]; then
    echo "✅ Lambda function updated successfully!"
    echo ""
    echo "🧪 Test sequence:"
    echo "1. Run: ./test-workflow.sh invoice.pdf"
    echo "2. Check Lambda logs: ./debug-lambda-422.sh"
    echo "3. Monitor ECS logs: ./view-ecs-logs.sh (option 4)"
    echo ""
    echo "📋 The Lambda now:"
    echo "- Handles None values properly"
    echo "- Only includes optional fields if they have values"
    echo "- Provides detailed error logging"
else
    echo "❌ Failed to deploy Lambda function"
    exit 1
fi
