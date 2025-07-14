#!/bin/bash

echo "🔧 Fixing Lambda 422 error - updating request format..."

# Rebuild Lambda package
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
    echo "🧪 Test the workflow again:"
    echo "   ./test-workflow.sh invoice.pdf"
    echo ""
    echo "📋 Monitor logs in real-time:"
    echo "   ./view-ecs-logs.sh (choose option 4)"
    echo ""
    echo "🔍 Lambda logs:"
    echo "   aws logs tail /aws/lambda/document-processor-dynamodb-trigger --follow"
else
    echo "❌ Failed to deploy Lambda function"
    exit 1
fi
