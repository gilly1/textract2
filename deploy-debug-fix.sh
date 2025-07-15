#!/bin/bash

echo "🔧 Deploying Lambda and ECS fixes for 422 error debugging..."

# Step 1: Update Lambda function
echo "📦 Step 1: Rebuilding and deploying Lambda function..."
cd lambda
zip -r ../lambda_function.zip . -x "*.pyc" "__pycache__/*"
cd ..

aws lambda update-function-code \
    --function-name document-processor-dynamodb-trigger \
    --zip-file fileb://lambda_function.zip

if [ $? -eq 0 ]; then
    echo "✅ Lambda function updated successfully!"
else
    echo "❌ Failed to update Lambda function"
    exit 1
fi

# Step 2: Update ECS service with new debug endpoint
echo ""
echo "🐳 Step 2: Updating ECS service..."

# Get ECR repository URL
cd infra
ECR_REPO=$(terraform output -raw ecr_repository_url)
cd ..

# Build and push new Docker image
echo "🔨 Building Docker image with debug endpoint..."
docker build -t document-processor .
docker tag document-processor:latest $ECR_REPO:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPO

# Push image
echo "📤 Pushing image to ECR..."
docker push $ECR_REPO:latest

# Force ECS service update
echo "🔄 Forcing ECS service update..."
aws ecs update-service \
    --cluster document-processor-cluster \
    --service document-processor-service \
    --force-new-deployment

echo ""
echo "✅ Deployment complete!"
echo ""
echo "🧪 Testing steps:"
echo "1. Wait 2-3 minutes for ECS service to update"
echo "2. Test the workflow: ./test-workflow.sh invoice.pdf"
echo "3. Check detailed Lambda logs: ./debug-lambda-422.sh"
echo "4. Test debug endpoint directly:"
echo "   curl -X POST http://\$(cd infra && terraform output -raw load_balancer_url)/debug-process \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"record\": {\"fileId\": \"test\", \"uploadedBy\": \"user\", \"fileName\": \"test.pdf\", \"fileType\": \"application/pdf\", \"s3Key\": \"test-key\", \"status\": \"pending\"}}'"
