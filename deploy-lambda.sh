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

# Step 2: Get Lambda function name
echo "Step 2: Finding Lambda function name..."

# Try to get from Terraform first
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_function_name 2>/dev/null | grep -v "Warning" | grep -v "│" | tr -d '\n')

# If that fails, try to find it by listing Lambda functions
if [ -z "$LAMBDA_FUNCTION_NAME" ] || [ "$LAMBDA_FUNCTION_NAME" = "" ]; then
    echo "Terraform output not available. Searching for Lambda function..."
    
    # Look for Lambda functions that match our naming pattern
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `document-processor`) || contains(FunctionName, `dynamodb-trigger`)].FunctionName' --output text)
    
    if [ ! -z "$LAMBDA_FUNCTIONS" ]; then
        # Take the first matching function
        LAMBDA_FUNCTION_NAME=$(echo "$LAMBDA_FUNCTIONS" | awk '{print $1}')
        echo "Found Lambda function: $LAMBDA_FUNCTION_NAME"
    else
        echo "Error: Could not find Lambda function. Please check if it exists:"
        echo "Available Lambda functions:"
        aws lambda list-functions --query 'Functions[].FunctionName' --output table
        exit 1
    fi
else
    echo "Got Lambda function name from Terraform: $LAMBDA_FUNCTION_NAME"
fi

# Step 3: Deploy Lambda function
echo "Step 3: Deploying Lambda function to AWS..."
echo "Function name: $LAMBDA_FUNCTION_NAME"

# Check if function exists first
echo "Verifying function exists..."
if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
    echo "Error: Lambda function '$LAMBDA_FUNCTION_NAME' not found."
    echo "Available functions:"
    aws lambda list-functions --query 'Functions[].FunctionName' --output table
    exit 1
fi

# Check AWS region
AWS_REGION=$(aws configure get region)
echo "Using AWS region: ${AWS_REGION:-default}"

# Deploy the function
echo "Updating function code..."
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
