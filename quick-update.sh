#!/bin/bash

# Quick update script - rebuild and push Docker image
set -e

echo "🔧 Rebuilding Docker image with DynamoDB fix..."

# Configuration
ECR_REPO="105714714499.dkr.ecr.us-east-1.amazonaws.com/document-processor"
AWS_REGION="us-east-1"
CLUSTER_NAME="document-processor-cluster"
SERVICE_NAME="document-processor-service"

# Step 1: Build image
echo "🏗️ Building Docker image..."
docker build -t document-processor:latest .

# Step 2: Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO

# Step 3: Tag and push
echo "🏷️ Tagging and pushing image..."
docker tag document-processor:latest $ECR_REPO:latest
docker push $ECR_REPO:latest

# Step 4: Force new deployment
echo "🔄 Updating ECS service..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --force-new-deployment \
    --region $AWS_REGION \
    --no-cli-pager

echo "✅ Image updated and ECS service redeployed!"
echo ""
echo "⏳ Service will take 2-3 minutes to update. Monitor with:"
echo "aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --query 'services[0].deployments[0].{Status:status,TaskDefinition:taskDefinition}'"
echo ""
echo "🧪 Test again with:"
echo "./test-workflow.sh invoice.pdf"
