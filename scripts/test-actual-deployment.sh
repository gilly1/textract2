#!/bin/bash
# Test Deployment Script with Correct Resource Names
set -e

AWS_REGION="${1:-us-east-1}"

echo "Testing document-processor deployment with actual resource names..."

# Test 1: Check AWS resources using actual names from Terraform output
echo ""
echo "=== Step 1: Verifying AWS Infrastructure ==="

# Check EKS cluster
echo "Checking EKS cluster..."
CLUSTER_STATUS=$(aws eks describe-cluster --name "document-processor-cluster" --region "$AWS_REGION" --query 'cluster.status' --output text 2>/dev/null || echo "ERROR")
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
    echo "✅ EKS Cluster is ACTIVE"
else
    echo "❌ EKS Cluster status: $CLUSTER_STATUS"
fi

# Check S3 bucket
echo "Checking S3 bucket..."
S3_BUCKET="document-processor-documents"
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
    echo "✅ S3 Bucket exists and accessible: $S3_BUCKET"
else
    echo "❌ S3 Bucket not accessible: $S3_BUCKET"
fi

# Check DynamoDB table
echo "Checking DynamoDB table..."
TABLE_STATUS=$(aws dynamodb describe-table --table-name "document-processor-results" --region "$AWS_REGION" --query 'Table.TableStatus' --output text 2>/dev/null || echo "ERROR")
if [ "$TABLE_STATUS" = "ACTIVE" ]; then
    echo "✅ DynamoDB Table is ACTIVE: document-processor-results"
else
    echo "❌ DynamoDB Table status: $TABLE_STATUS"
fi

# Check ECR repository
echo "Checking ECR repository..."
ECR_REPO=$(aws ecr describe-repositories --repository-names "document-processor/document-processor" --region "$AWS_REGION" --query 'repositories[0].repositoryName' --output text 2>/dev/null || echo "ERROR")
if [ "$ECR_REPO" != "ERROR" ]; then
    echo "✅ ECR Repository exists: $ECR_REPO"
else
    echo "❌ ECR Repository not found"
fi

# Test 2: Check Kubernetes deployment
echo ""
echo "=== Step 2: Verifying Kubernetes Deployment ==="

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "document-processor-cluster"

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
            aws eks update-kubeconfig --region "$AWS_REGION" --name "document-processor-cluster" --alias "document-processor-cluster"
        fi
    fi
else
    echo "✅ kubectl authentication working"
fi

# Check pods
echo "Checking pods..."
RUNNING_PODS=$(kubectl get pods -l app=document-processor -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Running" | wc -l)
if [ "$RUNNING_PODS" -gt 0 ]; then
    echo "✅ $RUNNING_PODS pod(s) running"
    kubectl get pods -l app=document-processor
else
    echo "❌ No running pods found"
    echo "Checking all pods:"
    kubectl get pods -l app=document-processor || true
    echo "Checking deployments:"
    kubectl get deployments || true
fi

# Check service
echo "Checking service..."
SERVICE_IP=$(kubectl get service document-processor-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$SERVICE_IP" ]; then
    echo "✅ Service has external IP: $SERVICE_IP"
else
    echo "⏳ Service external IP pending..."
    kubectl get service document-processor-service || true
fi

# Check ingress
echo "Checking ingress..."
INGRESS_IP=$(kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$INGRESS_IP" ]; then
    echo "✅ Ingress has hostname: $INGRESS_IP"
    SERVICE_ENDPOINT="http://$INGRESS_IP"
else
    echo "⏳ Ingress hostname pending..."
    kubectl get ingress document-processor-ingress || true
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

# Test 4: Check if Kubernetes resources were deployed
echo ""
echo "=== Step 4: Kubernetes Resources Status ==="
echo "Checking if Kubernetes manifests have been applied..."

if kubectl get deployment document-processor >/dev/null 2>&1; then
    echo "✅ Deployment exists"
    kubectl get deployment document-processor
else
    echo "❌ Deployment not found. Kubernetes manifests may not have been applied."
    echo "To deploy Kubernetes resources, run:"
    echo "  kubectl apply -f k8s/"
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

echo ""
echo "Next steps:"
echo "1. If Kubernetes resources are missing: kubectl apply -f k8s/"
echo "2. If services are pending: wait 5-10 minutes for AWS load balancer provisioning"
echo "3. Test API: ./scripts/test-api.sh"
