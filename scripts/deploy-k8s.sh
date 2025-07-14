#!/bin/bash

# Build Docker Image for Document Processor
set -e

# Default values
IMAGE_TAG="${1:-latest}"
AWS_REGION="${2:-us-east-1}"

# Configuration
PROJECT_NAME="dp714"

echo "Building Document Processor Docker Image..."

# Get AWS account ID
if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    echo "Error: Failed to get AWS account ID. Make sure AWS CLI is configured."
    exit 1
fi

# ECR repository URL
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$PROJECT_NAME/document-processor"

echo "ECR Repository: $ECR_REPO"

# Check if ECR repository exists
echo "Checking if ECR repository exists..."
if aws ecr describe-repositories --repository-names "$PROJECT_NAME/document-processor" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "ECR repository exists"
else
    echo "ECR repository does not exist. Please run 'terraform apply' first to create the infrastructure."
    exit 1
fi

# Authenticate Docker to ECR
echo "Authenticating Docker to ECR..."
if ! aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"; then
    echo "Error: Failed to authenticate with ECR"
    exit 1
fi

# Build the Docker image
echo "Building Docker image..."
if ! docker build -t "$PROJECT_NAME:$IMAGE_TAG" .; then
    echo "Error: Failed to build Docker image"
    exit 1
fi

# Tag the image for ECR
echo "Tagging image for ECR..."
docker tag "$PROJECT_NAME:$IMAGE_TAG" "$ECR_REPO:$IMAGE_TAG"

# Push the image to ECR
echo "Pushing image to ECR..."
if ! docker push "$ECR_REPO:$IMAGE_TAG"; then
    echo "Error: Failed to push image to ECR"
    exit 1
fi

echo "✅ Docker image built and pushed successfully!"
echo "Image: $ECR_REPO:$IMAGE_TAG"