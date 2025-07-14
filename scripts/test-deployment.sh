#!/bin/bash
# Test Deployment Script
set -e

AWS_REGION="${1:-us-east-1}"
PROJECT_NAME="dp714"

echo "Testing $PROJECT_NAME deployment..."

# Test 1: Check AWS resources
echo ""
echo "=== Step 1: Verifying AWS Infrastructure ==="

# Check EKS cluster
echo "Checking EKS cluster..."
CLUSTER_STATUS=$(aws eks describe-cluster --name "${PROJECT_NAME}-cluster" --region "$AWS_REGION" --query 'cluster.status' --output text 2>/dev/null || echo "ERROR")
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
    echo "✅ EKS Cluster is ACTIVE"
else
    echo "❌ EKS Cluster status: $CLUSTER_STATUS"
fi

# Check S3 bucket
echo "Checking S3 bucket..."
S3_BUCKET="${PROJECT_NAME}-documents-$(shuf -i 100000-999999 -n 1)"
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
    echo "✅ S3 Bucket exists and accessible"
else
    echo "❌ S3 Bucket not accessible"
fi

# Check DynamoDB table
echo "Checking DynamoDB table..."
TABLE_STATUS=$(aws dynamodb describe-table --table-name "${PROJECT_NAME}-results" --region "$AWS_REGION" --query 'Table.TableStatus' --output text 2>/dev/null || echo "ERROR")
if [ "$TABLE_STATUS" = "ACTIVE" ]; then
    echo "✅ DynamoDB Table is ACTIVE"
else
    echo "❌ DynamoDB Table status: $TABLE_STATUS"
fi

# Check ECR repository
echo "Checking ECR repository..."
ECR_REPO=$(aws ecr describe-repositories --repository-names "${PROJECT_NAME}/document-processor" --region "$AWS_REGION" --query 'repositories[0].repositoryName' --output text 2>/dev/null || echo "ERROR")
if [ "$ECR_REPO" != "ERROR" ]; then
    echo "✅ ECR Repository exists"
else
    echo "❌ ECR Repository not found"
fi

# Test 2: Check Kubernetes deployment
echo ""
echo "=== Step 2: Verifying Kubernetes Deployment ==="

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "${PROJECT_NAME}-cluster"

# Check for kubectl authentication issues and fix them
echo "Checking kubectl authentication..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Detected kubectl authentication issue, attempting to fix..."
    
    # Try to fix the apiVersion issue
    KUBECONFIG_FILE="$HOME/.kube/config"
    if [ -f "$KUBECONFIG_FILE" ]; then
        # Backup the config
        cp "$KUBECONFIG_FILE" "$KUBECONFIG_FILE.backup"
        
        # Replace v1alpha1 with v1beta1 if it exists
        sed -i 's/client\.authentication\.k8s\.io\/v1alpha1/client.authentication.k8s.io\/v1beta1/g' "$KUBECONFIG_FILE"
        
        echo "Updated kubectl config authentication version"
        
        # Test connection again
        if kubectl cluster-info >/dev/null 2>&1; then
            echo "✅ kubectl authentication fixed"
        else
            echo "❌ kubectl authentication still failing, trying alternative method..."
            # Restore backup and try recreating config
            cp "$KUBECONFIG_FILE.backup" "$KUBECONFIG_FILE"
            aws eks update-kubeconfig --region "$AWS_REGION" --name "${PROJECT_NAME}-cluster" --alias "${PROJECT_NAME}-cluster"
        fi
    fi
fi

# Check pods
echo "Checking pods..."
RUNNING_PODS=$(kubectl get pods -l app=document-processor -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Running" | wc -l)
if [ "$RUNNING_PODS" -gt 0 ]; then
    echo "✅ $RUNNING_PODS pod(s) running"
else
    echo "❌ No running pods found"
    kubectl get pods -l app=document-processor || true
fi

# Check service
echo "Checking service..."
SERVICE_IP=$(kubectl get service document-processor-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$SERVICE_IP" ]; then
    echo "✅ Service has external IP: $SERVICE_IP"
else
    echo "⏳ Service external IP pending..."
fi

# Check ingress
echo "Checking ingress..."
INGRESS_IP=$(kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$INGRESS_IP" ]; then
    echo "✅ Ingress has hostname: $INGRESS_IP"
    SERVICE_ENDPOINT="http://$INGRESS_IP"
else
    echo "⏳ Ingress hostname pending..."
fi

# Test 3: Health check
echo ""
echo "=== Step 3: Application Health Check ==="

if [ -n "$SERVICE_ENDPOINT" ]; then
    echo "Testing health endpoint: $SERVICE_ENDPOINT/health"
    if HEALTH_RESPONSE=$(curl -s -f "$SERVICE_ENDPOINT/health" 2>/dev/null); then
        echo "✅ Health check passed!"
        echo "Response: $HEALTH_RESPONSE"
    else
        echo "❌ Health check failed"
        echo "This might be normal if the service is still starting up"
    fi
else
    echo "⏳ Waiting for service endpoint to be available..."
fi

echo ""
echo "=== Deployment Test Summary ==="
echo "Check the above results for any issues."
echo "If services are pending, wait a few minutes and run this script again."

if [ -n "$SERVICE_ENDPOINT" ]; then
    echo ""
    echo "Service Endpoint: $SERVICE_ENDPOINT"
    echo "You can now test the API endpoints!"
fi
