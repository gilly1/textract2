#!/bin/bash

# Quick script to update the ECS service with the new Docker image
set -e

echo "🚀 Updating ECS service with new Docker image..."

# Configuration
ECR_REPO="105714714499.dkr.ecr.us-east-1.amazonaws.com/document-processor"
AWS_REGION="us-east-1"
CLUSTER_NAME="document-processor-cluster"
SERVICE_NAME="document-processor-service"

# Step 1: Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO

# Step 2: Tag the image
echo "🏷️ Tagging image..."
docker tag document-processor:latest $ECR_REPO:latest

# Step 3: Push to ECR
echo "📤 Pushing to ECR..."
docker push $ECR_REPO:latest

# Step 4: Force new deployment
echo "🔄 Forcing ECS service update..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --force-new-deployment \
    --region $AWS_REGION

echo "⏳ Waiting for deployment to complete..."
aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION

echo "✅ ECS service updated successfully!"
echo ""
echo "📊 Service status:"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION \
    --query 'services[0].{Status:status,RunningCount:runningCount,PendingCount:pendingCount,DesiredCount:desiredCount}' \
    --output table

echo ""
echo "🔗 Test the health endpoint:"
ALB_URL=$(terraform output -raw load_balancer_url)
echo "curl $ALB_URL/health"
