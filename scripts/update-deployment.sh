#!/bin/bash

# Update Deployment with Fixed ECR Repository Name
set -e

# Configuration
PROJECT_NAME="document-processor"
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Updating Deployment with Fixed ECR Repository ===${NC}"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
NEW_ECR="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/document-processor/document-processor"

echo -e "${YELLOW}Building and pushing updated image...${NC}"

# Build the image
docker build -t document-processor:latest .

# Tag for ECR
docker tag document-processor:latest "$NEW_ECR:latest"

# Push to ECR
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
docker push "$NEW_ECR:latest"

echo -e "${YELLOW}Restarting deployment...${NC}"

# Restart deployment to pull new image
kubectl rollout restart deployment document-processor

# Wait for rollout to complete
kubectl rollout status deployment document-processor --timeout=300s

echo -e "${GREEN}✅ Deployment updated successfully!${NC}"

# Show pod status
echo -e "${YELLOW}Pod status:${NC}"
kubectl get pods -l app=document-processor

echo -e "${GREEN}✅ Update completed!${NC}"
