#!/bin/bash
# Fix kubectl authentication issue with EKS
set -e

PROJECT_NAME="document-processor"
AWS_REGION="${1:-us-east-1}"

echo "Fixing kubectl authentication for EKS cluster..."

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "${PROJECT_NAME}-cluster"

# Check current authentication
echo "Testing current authentication..."
if kubectl cluster-info >/dev/null 2>&1; then
    echo "✅ kubectl authentication is working"
    exit 0
fi

echo "Authentication issue detected, applying fix..."

# Fix the authentication version issue
KUBECONFIG_FILE="$HOME/.kube/config"
if [ -f "$KUBECONFIG_FILE" ]; then
    echo "Backing up kubeconfig..."
    cp "$KUBECONFIG_FILE" "$KUBECONFIG_FILE.backup.$(date +%s)"
    
    echo "Updating authentication API version..."
    # Replace v1alpha1 with v1beta1
    sed -i 's/client\.authentication\.k8s\.io\/v1alpha1/client.authentication.k8s.io\/v1beta1/g' "$KUBECONFIG_FILE"
    
    # Test the fix
    echo "Testing fixed authentication..."
    if kubectl cluster-info >/dev/null 2>&1; then
        echo "✅ kubectl authentication fixed successfully!"
        echo "Cluster info:"
        kubectl cluster-info
    else
        echo "❌ Fix unsuccessful. Trying alternative approach..."
        
        # Try updating AWS CLI and kubectl versions
        echo "The issue might be due to version incompatibility."
        echo "Consider updating:"
        echo "  - AWS CLI: pip install --upgrade awscli"
        echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
        
        # Restore backup
        echo "Restoring original kubeconfig..."
        if [ -f "$KUBECONFIG_FILE.backup.$(date +%s)" ]; then
            cp "$KUBECONFIG_FILE.backup.$(date +%s)" "$KUBECONFIG_FILE"
        fi
        
        exit 1
    fi
else
    echo "❌ Kubeconfig file not found at $KUBECONFIG_FILE"
    echo "Run: aws eks update-kubeconfig --region $AWS_REGION --name ${PROJECT_NAME}-cluster"
    exit 1
fi

echo ""
echo "You can now run kubectl commands:"
echo "  kubectl get pods"
echo "  kubectl get services"
echo "  kubectl get ingress"
