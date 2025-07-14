#!/bin/bash

# Deploy Infrastructure and Application
set -e  # Exit on any error

# Default values
PLAN_ONLY=false
AWS_REGION="us-east-1"
IMAGE_TAG="latest"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --plan-only)
            PLAN_ONLY=true
            shift
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --plan-only     Only run terraform plan"
            echo "  --region REGION AWS region (default: us-east-1)"
            echo "  --tag TAG       Docker image tag (default: latest)"
            echo "  -h, --help      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Configuration
PROJECT_NAME="docproc-714499"

echo "Starting deployment of $PROJECT_NAME..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is required but not installed.${NC}"
    exit 1
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is required but not installed.${NC}"
    exit 1
fi

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is required but not installed.${NC}"
    exit 1
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is required but not installed.${NC}"
    exit 1
fi

# Check AWS credentials
if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    echo -e "${RED}Error: AWS credentials not configured. Run 'aws configure'.${NC}"
    exit 1
fi

echo -e "${GREEN}AWS Account ID: $ACCOUNT_ID${NC}"

# Step 1: Initialize and Deploy Infrastructure
echo -e "\n${CYAN}=== Step 1: Deploying Infrastructure ===${NC}"

cd terraform

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}Creating terraform.tfvars from example...${NC}"
    cp terraform.tfvars.example terraform.tfvars
    echo -e "${YELLOW}Please edit terraform.tfvars with your specific values and run the script again.${NC}"
    exit 1
fi

# Initialize Terraform
echo -e "${GREEN}Initializing Terraform...${NC}"
if ! terraform init; then
    echo -e "${RED}Error: Terraform initialization failed${NC}"
    exit 1
fi

# Plan infrastructure
echo -e "${GREEN}Planning infrastructure...${NC}"
if ! terraform plan -out=tfplan; then
    echo -e "${RED}Error: Terraform planning failed${NC}"
    exit 1
fi

if [ "$PLAN_ONLY" = true ]; then
    echo -e "${YELLOW}Plan-only mode enabled. Exiting...${NC}"
    exit 0
fi

# Apply infrastructure
echo -e "${GREEN}Applying infrastructure...${NC}"
if ! terraform apply tfplan; then
    echo -e "${RED}Error: Terraform apply failed${NC}"
    exit 1
fi

cd ..

echo -e "${GREEN}✅ Infrastructure deployed successfully!${NC}"

# Step 2: Build and Push Docker Image
echo -e "\n${CYAN}=== Step 2: Building and Pushing Docker Image ===${NC}"

if ! ./scripts/build-docker.sh "$IMAGE_TAG" "$AWS_REGION"; then
    echo -e "${RED}Error: Failed to build and push Docker image${NC}"
    exit 1
fi

# Step 3: Deploy to EKS
echo -e "\n${CYAN}=== Step 3: Deploying to EKS ===${NC}"

# Wait a moment for EKS cluster to be fully ready
echo -e "${YELLOW}Waiting for EKS cluster to be fully ready...${NC}"
sleep 30

if ! ./scripts/deploy-k8s.sh "$IMAGE_TAG" "$AWS_REGION"; then
    echo -e "${RED}Error: Failed to deploy to EKS${NC}"
    exit 1
fi

# Step 4: Test Deployment
echo -e "\n${CYAN}=== Step 4: Testing Deployment ===${NC}"

echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 60

# Get deployment information
echo -e "\n${CYAN}=== Deployment Information ===${NC}"

cd terraform

echo -e "${GREEN}Cluster Information:${NC}"
CLUSTER_NAME=$(terraform output -raw cluster_name)
CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
DYNAMO_TABLE=$(terraform output -raw dynamodb_table_name)
ECR_REPO=$(terraform output -raw ecr_repository_url)

echo -e "  ${WHITE}Cluster Name: $CLUSTER_NAME${NC}"
echo -e "  ${WHITE}Cluster Endpoint: $CLUSTER_ENDPOINT${NC}"
echo -e "  ${WHITE}S3 Bucket: $S3_BUCKET${NC}"
echo -e "  ${WHITE}DynamoDB Table: $DYNAMO_TABLE${NC}"
echo -e "  ${WHITE}ECR Repository: $ECR_REPO${NC}"

echo -e "\n${GREEN}Kubectl Configuration:${NC}"
KUBECTL_COMMAND=$(terraform output -raw configure_kubectl)
echo -e "  ${WHITE}$KUBECTL_COMMAND${NC}"

cd ..

# Get service URL
echo -e "\n${GREEN}Service Information:${NC}"
if INGRESS_HOSTNAME=$(kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) && [ -n "$INGRESS_HOSTNAME" ]; then
    echo -e "  ${WHITE}External URL: http://$INGRESS_HOSTNAME${NC}"
    echo -e "  ${WHITE}Health Check: http://$INGRESS_HOSTNAME/health${NC}"
else
    echo -e "  ${YELLOW}External URL: Pending (check in a few minutes)${NC}"
    echo -e "  ${YELLOW}Use 'kubectl get ingress' to check status${NC}"
fi

echo -e "\n${CYAN}=== Next Steps ===${NC}"
echo -e "${WHITE}1. Wait for the load balancer to be ready (5-10 minutes)${NC}"
echo -e "${WHITE}2. Test the service:${NC}"
echo -e "   ${GRAY}kubectl get ingress document-processor-ingress${NC}"
echo -e "${WHITE}3. Check logs:${NC}"
echo -e "   ${GRAY}kubectl logs -l app=document-processor -f${NC}"
echo -e "${WHITE}4. Upload test documents to S3 bucket: $S3_BUCKET${NC}"
echo -e "${WHITE}5. Monitor results in DynamoDB table: $DYNAMO_TABLE${NC}"

echo -e "\n${GREEN}✅ Deployment completed successfully!${NC}"
echo -e "${GREEN}The document processor service is now running on EKS!${NC}"