#!/bin/bash

set -e  # Exit on error
set -o pipefail

# ---- Config ----
APP_NAME="document-processor"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME"
TAG="latest"

echo "🚀 Starting ECS deployment for Document Processor..."
echo "Account ID: $ACCOUNT_ID"
echo "ECR Repository: $ECR_REPO"

# ---- Step 1: Deploy Infrastructure ----
echo "📦 Deploying infrastructure with Terraform..."
cd infra
terraform init
terraform plan
echo ""
read -p "Do you want to apply the Terraform plan? (y/n): " APPLY_TF

if [[ "$APPLY_TF" == "y" ]]; then
    terraform apply -auto-approve
    echo "✅ Infrastructure deployed successfully!"
else
    echo "⏭️ Skipping Terraform apply."
    cd ..
    exit 0
fi

# Get outputs
ECR_REPO_URL=$(terraform output -raw ecr_repository_url)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name)
ALB_URL=$(terraform output -raw load_balancer_url)

cd ..

echo ""
echo "📋 Infrastructure Details:"
echo "- ECR Repository: $ECR_REPO_URL"
echo "- S3 Bucket: $S3_BUCKET"
echo "- DynamoDB Table: $DYNAMODB_TABLE"
echo "- ALB URL: $ALB_URL"
echo ""

# ---- Step 2: Build Docker Image ----
echo "🔧 Building Docker image..."
docker build -t $APP_NAME .

# ---- Step 3: Authenticate with ECR ----
echo "🔐 Logging into Amazon ECR..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REPO_URL

# ---- Step 4: Tag Docker Image ----
echo "🏷️ Tagging image as $ECR_REPO_URL:$TAG..."
docker tag $APP_NAME:latest $ECR_REPO_URL:$TAG

# ---- Step 5: Push to ECR ----
echo "📤 Pushing image to ECR..."
docker push $ECR_REPO_URL:$TAG

# ---- Step 6: Wait for ECS Service to Update ----
echo "⏳ Waiting for ECS service to update with new image..."
sleep 30

# Check ECS service status
echo "📊 Checking ECS service status..."
aws ecs describe-services \
    --cluster "$APP_NAME-cluster" \
    --services "$APP_NAME-service" \
    --query 'services[0].{Status:status,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}' \
    --output table

# ---- Step 7: Test Health Endpoint ----
echo "🏥 Testing health endpoint..."
for i in {1..12}; do
    echo "Health check attempt $i/12..."
    
    if curl -s "$ALB_URL/health" > /dev/null; then
        echo "✅ Health check passed!"
        break
    else
        echo "⏳ Health check failed, retrying in 15 seconds..."
        sleep 15
    fi
    
    if [[ $i -eq 12 ]]; then
        echo "❌ Health check failed after 12 attempts"
        echo "Check ECS service logs for issues"
    fi
done

echo ""
echo "✅ Deployment completed!"
echo ""
echo "🔗 Service URLs:"
echo "- Health Check: $ALB_URL/health"
echo "- API Docs: $ALB_URL/docs"
echo ""
echo "📋 Test the workflow:"
echo "- Run: ./test-workflow.sh invoice.pdf"
echo "- Or: .\test-workflow.ps1 -TestFile 'invoice.pdf'"
echo ""
echo "📊 Monitor with:"
echo "- Lambda logs: aws logs tail /aws/lambda/$APP_NAME-dynamodb-trigger --follow"
echo "- ECS logs: aws logs tail /ecs/$APP_NAME --follow"
