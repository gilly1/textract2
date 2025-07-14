#!/bin/bash

# Build Docker Image for Document Processor
set -e

# Configuration
PROJECT_NAME="document-processor"
IMAGE_TAG=${1:-"latest"}
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Document Processor Docker Image...${NC}"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to get AWS account ID. Make sure AWS CLI is configured.${NC}"
    exit 1
fi

# ECR repository URL
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}/document-processor"

echo -e "${YELLOW}ECR Repository: ${ECR_REPO}${NC}"

# Authenticate Docker to ECR
echo -e "${GREEN}Authenticating Docker to ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPO}

# Build the Docker image
echo -e "${GREEN}Building Docker image...${NC}"
docker build -t ${PROJECT_NAME}:${IMAGE_TAG} .

# Tag the image for ECR
echo -e "${GREEN}Tagging image for ECR...${NC}"
docker tag ${PROJECT_NAME}:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}
docker tag ${PROJECT_NAME}:${IMAGE_TAG} ${ECR_REPO}:latest

# Push to ECR
echo -e "${GREEN}Pushing image to ECR...${NC}"
docker push ${ECR_REPO}:${IMAGE_TAG}
docker push ${ECR_REPO}:latest

echo -e "${GREEN}✅ Docker image built and pushed successfully!${NC}"
echo -e "${YELLOW}Image URL: ${ECR_REPO}:${IMAGE_TAG}${NC}"
