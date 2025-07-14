#!/bin/bash

# Script to check Lambda functions and deploy
echo "Checking AWS Lambda functions..."

# Check AWS credentials and region
echo "AWS Region: $(aws configure get region)"
echo "AWS Account: $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'Unable to get account ID')"

# List all Lambda functions
echo ""
echo "Available Lambda functions:"
aws lambda list-functions --query 'Functions[].[FunctionName, Runtime, LastModified]' --output table

echo ""
echo "Looking for document processor related functions..."
aws lambda list-functions --query 'Functions[?contains(FunctionName, `document`) || contains(FunctionName, `processor`) || contains(FunctionName, `dynamodb`)].FunctionName' --output text

echo ""
echo "If you see your Lambda function above, you can manually deploy with:"
echo "aws lambda update-function-code --function-name YOUR_FUNCTION_NAME --zip-file fileb://lambda_function.zip"
