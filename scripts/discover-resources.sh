#!/bin/bash
# Discover actual deployed resources
set -e

AWS_REGION="${1:-us-east-1}"

echo "Discovering deployed AWS resources..."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Discovering EKS Clusters ===${NC}"
echo "Available EKS clusters:"
aws eks list-clusters --region "$AWS_REGION" --query 'clusters[]' --output table

echo -e "\n${CYAN}=== Discovering S3 Buckets ===${NC}"
echo "S3 buckets containing 'document' or 'dp714':"
aws s3api list-buckets --query 'Buckets[?contains(Name, `document`) || contains(Name, `dp714`)].[Name]' --output table

echo -e "\n${CYAN}=== Discovering DynamoDB Tables ===${NC}"
echo "DynamoDB tables containing 'document' or 'dp714' or 'result':"
aws dynamodb list-tables --region "$AWS_REGION" --query 'TableNames[?contains(@, `document`) || contains(@, `dp714`) || contains(@, `result`)]' --output table

echo -e "\n${CYAN}=== Discovering ECR Repositories ===${NC}"
echo "ECR repositories:"
aws ecr describe-repositories --region "$AWS_REGION" --query 'repositories[].[repositoryName,repositoryUri]' --output table

echo -e "\n${CYAN}=== Checking Terraform State ===${NC}"
if [ -f "terraform/terraform.tfstate" ]; then
    echo "Terraform state file exists. Checking outputs..."
    cd terraform
    
    echo -e "${YELLOW}Terraform outputs:${NC}"
    terraform output 2>/dev/null || echo "No outputs available or terraform not initialized"
    
    echo -e "\n${YELLOW}Resources in state:${NC}"
    terraform state list 2>/dev/null | head -20 || echo "Could not list terraform state"
    
    cd ..
else
    echo "No terraform state file found"
fi

echo -e "\n${CYAN}=== Resource Discovery Complete ===${NC}"
echo "Use the actual resource names found above to update your configuration."
