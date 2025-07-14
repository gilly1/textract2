#!/bin/bash

# Deploy to EKS
set -e

# Configuration
PROJECT_NAME="document-processor"
AWS_REGION=${AWS_REGION:-"us-east-1"}
IMAGE_TAG=${1:-"latest"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Deploying Document Processor to EKS...${NC}"

# Get cluster name from Terraform output
CLUSTER_NAME=$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "${PROJECT_NAME}-cluster")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}/document-processor"

echo -e "${YELLOW}Cluster: ${CLUSTER_NAME}${NC}"
echo -e "${YELLOW}Image: ${ECR_REPO}:${IMAGE_TAG}${NC}"

# Update kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

# Check cluster connectivity
echo -e "${GREEN}Checking cluster connectivity...${NC}"
kubectl cluster-info

# Get IAM role ARN for service account
ROLE_ARN=$(cd terraform && terraform output -raw document_processor_role_arn 2>/dev/null || echo "arn:aws:iam::${ACCOUNT_ID}:role/DocumentProcessorRole")

# Update RBAC with correct role ARN
echo -e "${GREEN}Updating RBAC configuration...${NC}"
sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" k8s/rbac.yaml | kubectl apply -f -

# Update deployment with correct image
echo -e "${GREEN}Updating deployment with latest image...${NC}"
sed "s|image: document-processor:latest|image: ${ECR_REPO}:${IMAGE_TAG}|g" k8s/deployment.yaml | kubectl apply -f -

# Apply HPA
echo -e "${GREEN}Applying Horizontal Pod Autoscaler...${NC}"
kubectl apply -f k8s/hpa.yaml

# Wait for deployment to be ready
echo -e "${GREEN}Waiting for deployment to be ready...${NC}"
kubectl rollout status deployment/document-processor --timeout=300s

# Get service information
echo -e "${GREEN}Getting service information...${NC}"
kubectl get services document-processor-service
kubectl get ingress document-processor-ingress

# Check pod status
echo -e "${GREEN}Pod status:${NC}"
kubectl get pods -l app=document-processor

echo -e "${GREEN}✅ Deployment completed successfully!${NC}"

# Show how to get the external URL
echo -e "${YELLOW}To get the external URL, wait a few minutes and run:${NC}"
echo "kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"

echo -e "${YELLOW}To check logs:${NC}"
echo "kubectl logs -l app=document-processor -f"
