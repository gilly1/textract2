#!/bin/bash
# Comprehensive kubectl authentication fix
set -e

AWS_REGION="${1:-us-east-1}"
CLUSTER_NAME="document-processor-cluster"

echo "Comprehensive kubectl authentication fix..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 1: Check current versions${NC}"
echo "AWS CLI version:"
aws --version
echo "kubectl version:"
kubectl version --client --short 2>/dev/null || echo "kubectl version check failed"

echo -e "\n${YELLOW}Step 2: Clean existing kubeconfig${NC}"
KUBECONFIG_FILE="$HOME/.kube/config"
if [ -f "$KUBECONFIG_FILE" ]; then
    echo "Backing up existing kubeconfig..."
    cp "$KUBECONFIG_FILE" "$KUBECONFIG_FILE.backup.$(date +%s)"
    
    echo "Removing cluster context from kubeconfig..."
    kubectl config delete-context "arn:aws:eks:$AWS_REGION:*:cluster/$CLUSTER_NAME" 2>/dev/null || true
    kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
    kubectl config delete-cluster "arn:aws:eks:$AWS_REGION:*:cluster/$CLUSTER_NAME" 2>/dev/null || true
    kubectl config delete-user "arn:aws:eks:$AWS_REGION:*:cluster/$CLUSTER_NAME" 2>/dev/null || true
fi

echo -e "\n${YELLOW}Step 3: Try different authentication methods${NC}"

# Method 1: Standard update-kubeconfig
echo "Method 1: Standard update-kubeconfig..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" --alias "$CLUSTER_NAME"

# Test method 1
if kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Method 1 successful!${NC}"
    kubectl cluster-info
    exit 0
fi

# Method 2: Force v1beta1 API version
echo "Method 2: Force v1beta1 API version..."
if [ -f "$KUBECONFIG_FILE" ]; then
    # More aggressive replacement
    sed -i 's/client\.authentication\.k8s\.io\/v1alpha1/client.authentication.k8s.io\/v1beta1/g' "$KUBECONFIG_FILE"
    sed -i 's/apiVersion: client\.authentication\.k8s\.io\/v1alpha1/apiVersion: client.authentication.k8s.io\/v1beta1/g' "$KUBECONFIG_FILE"
    
    # Test method 2
    if kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Method 2 successful!${NC}"
        kubectl cluster-info
        exit 0
    fi
fi

# Method 3: Try with older API version (v1)
echo "Method 3: Try v1 API version..."
if [ -f "$KUBECONFIG_FILE" ]; then
    sed -i 's/client\.authentication\.k8s\.io\/v1beta1/client.authentication.k8s.io\/v1/g' "$KUBECONFIG_FILE"
    sed -i 's/apiVersion: client\.authentication\.k8s\.io\/v1beta1/apiVersion: client.authentication.k8s.io\/v1/g' "$KUBECONFIG_FILE"
    
    # Test method 3
    if kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Method 3 successful!${NC}"
        kubectl cluster-info
        exit 0
    fi
fi

# Method 4: Manual kubeconfig creation
echo "Method 4: Manual kubeconfig creation..."

# Get cluster info
CLUSTER_ENDPOINT=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.endpoint' --output text)
CLUSTER_CA=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.certificateAuthority.data' --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create manual kubeconfig
cat > "$KUBECONFIG_FILE" << EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_CA
    server: $CLUSTER_ENDPOINT
  name: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
contexts:
- context:
    cluster: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
    user: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
  name: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
current-context: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
kind: Config
preferences: {}
users:
- name: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - eks
        - get-token
        - --cluster-name
        - $CLUSTER_NAME
        - --region
        - $AWS_REGION
EOF

# Test method 4
if kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Method 4 successful!${NC}"
    kubectl cluster-info
    exit 0
fi

# Method 5: Try with aws-iam-authenticator
echo "Method 5: Try with aws-iam-authenticator..."

# Check if aws-iam-authenticator exists
if command -v aws-iam-authenticator >/dev/null 2>&1; then
    # Create kubeconfig with aws-iam-authenticator
    cat > "$KUBECONFIG_FILE" << EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_CA
    server: $CLUSTER_ENDPOINT
  name: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
contexts:
- context:
    cluster: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
    user: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
  name: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
current-context: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
kind: Config
preferences: {}
users:
- name: arn:aws:eks:$AWS_REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - token
        - -i
        - $CLUSTER_NAME
EOF

    # Test method 5
    if kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Method 5 successful!${NC}"
        kubectl cluster-info
        exit 0
    fi
else
    echo "aws-iam-authenticator not found, skipping method 5"
fi

echo -e "${RED}❌ All authentication methods failed${NC}"
echo -e "${YELLOW}Manual steps to try:${NC}"
echo "1. Update AWS CLI: curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install --update"
echo "2. Update kubectl: curl -LO 'https://storage.googleapis.com/kubernetes-release/release/\$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl' && chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
echo "3. Install aws-iam-authenticator: curl -o aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.28.3/2023-11-14/bin/linux/amd64/aws-iam-authenticator && chmod +x aws-iam-authenticator && sudo mv aws-iam-authenticator /usr/local/bin/"

exit 1
