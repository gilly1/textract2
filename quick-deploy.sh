#!/bin/bash

# Quick deployment script
echo "Rebuilding and deploying Lambda function..."

# Create package
cd lambda
zip -r ../lambda_function.zip . -x "*.pyc" "__pycache__/*"
cd ..

# Deploy to the known function name
echo "Deploying to: document-processor-dynamodb-trigger"
aws lambda update-function-code \
    --function-name document-processor-dynamodb-trigger \
    --zip-file fileb://lambda_function.zip

if [ $? -eq 0 ]; then
    echo "✅ Lambda function deployed successfully!"
    echo "The function now properly formats records for ECS processing."
    echo ""
    echo "You can now test with: ./test-workflow.sh invoice.pdf"
else
    echo "❌ Deployment failed"
    exit 1
fi
