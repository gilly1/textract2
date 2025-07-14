#!/bin/bash

# Script to rebuild and deploy Lambda function with updated code
echo "Rebuilding and deploying Lambda function..."

# Check if we're in the right directory
if [ ! -f "lambda/dynamodb_trigger.py" ]; then
    echo "Error: lambda/dynamodb_trigger.py not found. Please run from project root."
    exit 1
fi

# Step 1: Rebuild Lambda package
echo "Step 1: Creating Lambda deployment package..."
cd lambda
zip -r ../lambda_function.zip . -x "*.pyc" "__pycache__/*"
cd ..

if [ ! -f "lambda_function.zip" ]; then
    echo "Error: Failed to create lambda_function.zip"
    exit 1
fi

echo "Lambda package created: $(ls -lh lambda_function.zip | awk '{print $5}')"

# Step 2: Get Lambda function name from Terraform
echo "Step 2: Getting Lambda function name from Terraform..."
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_function_name 2>/dev/null)

if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
    echo "Warning: Could not get Lambda function name from Terraform. Using default name..."
    LAMBDA_FUNCTION_NAME="document-processor-lambda"
fi

echo "Lambda function name: $LAMBDA_FUNCTION_NAME"

# Step 3: Deploy Lambda function
echo "Step 3: Deploying Lambda function to AWS..."
aws lambda update-function-code \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --zip-file fileb://lambda_function.zip

if [ $? -eq 0 ]; then
    echo "✅ Lambda function deployed successfully!"
    
    # Wait a moment for deployment to complete
    echo "Waiting for deployment to complete..."
    sleep 5
    
    # Get function status
    echo "Checking function status..."
    aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --query 'Configuration.State' --output text
    
else
    echo "❌ Failed to deploy Lambda function"
    exit 1
fi

echo "Deployment complete. The Lambda function now supports both old and new DynamoDB schemas."
