#!/bin/bash

set -e  # Exit on error
set -o pipefail

# ---- Config ----
APP_NAME="document-processor"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME"
TAG="latest"

# ---- Step 1: Build Docker Image ----
echo "🔧 Building Docker image..."
docker build -t $APP_NAME .

# ---- Step 2: Authenticate with ECR ----
echo "🔐 Logging into Amazon ECR..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REPO

# ---- Step 3: Tag Docker Image ----
echo "🏷️ Tagging image as $ECR_REPO:$TAG..."
docker tag $APP_NAME:latest $ECR_REPO:$TAG

# ---- Step 4: Push to ECR ----
echo "📤 Pushing image to ECR..."
docker push $ECR_REPO:$TAG

# ---- Step 5: (Optional) Terraform apply ----
read -p "Do you want to apply Terraform to deploy infrastructure? (y/n): " APPLY_TF

if [[ "$APPLY_TF" == "y" ]]; then
    echo "📦 Running Terraform apply..."
    terraform init
    terraform apply -auto-approve
else
    echo "⏭️ Skipping Terraform apply."
fi

echo "✅ Done!"
