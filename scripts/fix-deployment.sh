#!/bin/bash
# Fix deployment issues and rebuild with correct naming
set -e

PROJECT_NAME="dp714"
AWS_REGION="${1:-us-east-1}"

echo "Fixing deployment issues for $PROJECT_NAME..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Step 1: Cleaning up old Docker images ===${NC}"

# Remove old Docker images with wrong names
echo "Removing old Docker images..."
docker rmi document-processor:latest 2>/dev/null || true
docker rmi document-processor/document-processor:latest 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OLD_ECR="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/document-processor/document-processor"
NEW_ECR="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$PROJECT_NAME/document-processor"

# Remove old ECR tagged images
docker rmi "$OLD_ECR:latest" 2>/dev/null || true
docker rmi "$OLD_ECR:v1.0.0" 2>/dev/null || true

echo -e "${GREEN}✅ Old images cleaned up${NC}"

echo -e "${CYAN}=== Step 2: Verifying ECR repository ===${NC}"

# Check if correct ECR repository exists
if aws ecr describe-repositories --repository-names "$PROJECT_NAME/document-processor" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Correct ECR repository exists: $PROJECT_NAME/document-processor${NC}"
else
    echo -e "${YELLOW}ECR repository doesn't exist yet. This is normal if Terraform hasn't been applied.${NC}"
    echo -e "${YELLOW}Make sure to run terraform apply first.${NC}"
fi

echo -e "${CYAN}=== Step 3: Rebuilding Docker image with correct naming ===${NC}"

# Build with correct project name
echo "Building Docker image..."
docker build -t "$PROJECT_NAME:latest" .

# Tag for ECR if repository exists
if aws ecr describe-repositories --repository-names "$PROJECT_NAME/document-processor" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Tagging and pushing to ECR..."
    
    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    
    # Tag and push
    docker tag "$PROJECT_NAME:latest" "$NEW_ECR:latest"
    docker push "$NEW_ECR:latest"
    
    echo -e "${GREEN}✅ Docker image built and pushed successfully!${NC}"
    echo -e "${YELLOW}Image URL: $NEW_ECR:latest${NC}"
else
    echo -e "${YELLOW}⚠️  ECR repository not found. Image built locally only.${NC}"
    echo -e "${YELLOW}Run 'terraform apply' first to create the ECR repository.${NC}"
fi

echo -e "${CYAN}=== Step 4: Checking Kubernetes deployment ===${NC}"

# Check if kubectl is working
if kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${GREEN}✅ kubectl is working${NC}"
    
    # Apply Kubernetes manifests
    echo "Applying Kubernetes manifests..."
    kubectl apply -f k8s/
    
    echo -e "${GREEN}✅ Kubernetes resources applied${NC}"
    
    # Check pod status
    echo "Checking pod status..."
    kubectl get pods -l app=document-processor
    
else
    echo -e "${YELLOW}⚠️  kubectl authentication issue detected${NC}"
    echo -e "${YELLOW}Run the kubectl auth fix script first:${NC}"
    echo -e "${CYAN}  ./scripts/fix-kubectl-auth.sh${NC}"
fi

echo -e "${GREEN}=== Fix Complete ===${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. If Terraform hasn't been applied: cd terraform && terraform apply"
echo -e "  2. If kubectl auth issues: ./scripts/fix-kubectl-auth.sh"
echo -e "  3. Run tests: ./scripts/test-deployment.sh"
