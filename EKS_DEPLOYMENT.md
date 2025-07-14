# EKS Deployment Guide

This document provides detailed instructions for deploying the Document Processor service to Amazon EKS.

## Prerequisites

Before deploying, ensure you have the following tools installed:

### Required Tools

1. **AWS CLI v2** - For AWS authentication and resource management
   ```bash
   # Install on Windows (PowerShell)
   msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
   
   # Configure
   aws configure
   ```

2. **Terraform v1.0+** - For infrastructure provisioning
   ```bash
   # Install on Windows
   choco install terraform
   
   # Or download from https://www.terraform.io/downloads.html
   ```

3. **kubectl** - For Kubernetes cluster management
   ```bash
   # Install on Windows
   choco install kubernetes-cli
   
   # Or download from https://kubernetes.io/docs/tasks/tools/install-kubectl/
   ```

4. **Docker** - For container building
   ```bash
   # Install Docker Desktop for Windows
   # Download from https://www.docker.com/products/docker-desktop
   ```

### AWS Prerequisites

1. **AWS Account** with appropriate permissions
2. **IAM User** with the following permissions:
   - EKS Full Access
   - EC2 Full Access
   - VPC Full Access
   - S3 Full Access
   - DynamoDB Full Access
   - ECR Full Access
   - IAM permissions to create roles and policies

3. **AWS CLI configured** with your credentials
   ```bash
   aws configure
   # Enter your Access Key ID, Secret Access Key, and region
   ```

## Quick Deployment (Automated)

### Option 1: Windows PowerShell

```powershell
# Navigate to project directory
cd c:\laragon\www\python\my_textract_3

# Run automated deployment
.\scripts\deploy.ps1
```

### Option 2: Linux/macOS

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run automated deployment
./scripts/deploy.sh
```

## Manual Deployment Steps

### Step 1: Configure Terraform Variables

1. Copy the example variables file:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your specific values:
   ```hcl
   aws_region = "us-east-1"
   project_name = "document-processor"
   environment = "prod"
   
   # Optional: Add your EC2 key pair for node access
   key_pair_name = "your-key-pair-name"
   
   # Optional: Add additional IAM users for cluster access
   aws_auth_users = [
     {
       userarn  = "arn:aws:iam::123456789012:user/your-username"
       username = "your-username"
       groups   = ["system:masters"]
     }
   ]
   ```

### Step 2: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

This will create:
- EKS cluster with managed node groups
- VPC with public/private subnets
- S3 bucket for document storage
- DynamoDB table for results
- ECR repository for container images
- IAM roles and policies

### Step 3: Build and Push Docker Image

```bash
# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build the image
docker build -t document-processor:latest .

# Tag for ECR
docker tag document-processor:latest $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/document-processor/document-processor:latest

# Push to ECR
docker push $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/document-processor/document-processor:latest
```

### Step 4: Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name document-processor-cluster

# Verify connection
kubectl cluster-info
```

### Step 5: Deploy Application to EKS

1. Update the RBAC configuration with your AWS account ID:
   ```bash
   # Edit k8s/rbac.yaml and replace ACCOUNT_ID with your actual account ID
   sed -i 's/ACCOUNT_ID/123456789012/g' k8s/rbac.yaml
   ```

2. Apply Kubernetes manifests:
   ```bash
   # Apply RBAC
   kubectl apply -f k8s/rbac.yaml
   
   # Apply deployment
   kubectl apply -f k8s/deployment.yaml
   
   # Apply HPA
   kubectl apply -f k8s/hpa.yaml
   ```

3. Wait for deployment to be ready:
   ```bash
   kubectl rollout status deployment/document-processor
   ```

## Verification

### Check Deployment Status

```bash
# Check pods
kubectl get pods -l app=document-processor

# Check services
kubectl get services

# Check ingress
kubectl get ingress

# Check HPA
kubectl get hpa
```

### Get External URL

```bash
# Wait for load balancer to be ready (5-10 minutes)
kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Test the Service

```bash
# Health check
curl http://YOUR-ALB-HOSTNAME/health

# Process a document (requires S3 upload first)
curl -X POST http://YOUR-ALB-HOSTNAME/process \
  -H "Content-Type: application/json" \
  -d '{
    "record": {
      "document_id": "test-doc-123",
      "bucket": "your-s3-bucket",
      "key": "test-document.pdf",
      "status": "pending",
      "file_type": "pdf"
    }
  }'
```

## Monitoring and Logging

### View Application Logs

```bash
# View logs from all pods
kubectl logs -l app=document-processor -f

# View logs from specific pod
kubectl logs document-processor-xxxxxxxxx-xxxxx -f
```

### CloudWatch Logs

The EKS cluster automatically sends logs to CloudWatch under:
- Log Group: `/aws/eks/document-processor-cluster/cluster`

### Metrics and Monitoring

1. **Kubernetes Dashboard** (optional):
   ```bash
   # Install dashboard
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
   
   # Create admin user and get token
   kubectl create serviceaccount admin-user -n kubernetes-dashboard
   kubectl create clusterrolebinding admin-user --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:admin-user
   kubectl get secret $(kubectl get serviceaccount admin-user -n kubernetes-dashboard -o jsonpath='{.secrets[0].name}') -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
   ```

2. **Prometheus/Grafana** (optional):
   ```bash
   # Install using Helm
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm install prometheus prometheus-community/kube-prometheus-stack
   ```

## Scaling

### Manual Scaling

```bash
# Scale deployment
kubectl scale deployment document-processor --replicas=5

# Scale node group (if needed)
aws eks update-nodegroup-config --cluster-name document-processor-cluster --nodegroup-name document-processor-workers --scaling-config minSize=3,maxSize=20,desiredSize=5
```

### Auto-scaling

The HPA (Horizontal Pod Autoscaler) is configured to automatically scale based on:
- CPU utilization (70% threshold)
- Memory utilization (80% threshold)
- Min replicas: 2
- Max replicas: 10

## Troubleshooting

### Common Issues

1. **Pod stuck in Pending state**:
   ```bash
   kubectl describe pod POD_NAME
   # Check for resource constraints or node capacity
   ```

2. **Image pull errors**:
   ```bash
   # Verify ECR permissions and image existence
   aws ecr describe-repositories
   aws ecr list-images --repository-name document-processor/document-processor
   ```

3. **Load balancer not ready**:
   ```bash
   # Check ALB controller logs
   kubectl logs -n kube-system deployment/aws-load-balancer-controller
   ```

4. **Application errors**:
   ```bash
   # Check application logs
   kubectl logs -l app=document-processor --tail=100
   ```

### Debug Commands

```bash
# Get detailed pod information
kubectl describe pod POD_NAME

# Execute commands in pod
kubectl exec -it POD_NAME -- /bin/bash

# Port forward for local testing
kubectl port-forward service/document-processor-service 8080:80

# Check resource usage
kubectl top pods
kubectl top nodes
```

## Security Considerations

1. **Network Security**:
   - Private subnets for worker nodes
   - Security groups with minimal required access
   - NACLs for additional network layer security

2. **IAM Security**:
   - Least privilege IAM roles
   - IRSA (IAM Roles for Service Accounts) for pod-level permissions
   - No long-term AWS credentials in containers

3. **Container Security**:
   - Non-root user in containers
   - Read-only root filesystem where possible
   - Resource limits and requests defined

4. **Data Security**:
   - S3 bucket encryption at rest
   - DynamoDB encryption at rest
   - Secrets management via Kubernetes secrets

## Cost Optimization

1. **Use Spot Instances** for worker nodes (modify Terraform):
   ```hcl
   capacity_type = "SPOT"
   ```

2. **Configure cluster autoscaler** for automatic node scaling

3. **Set appropriate resource requests/limits** to optimize bin packing

4. **Use S3 Intelligent Tiering** for document storage

5. **Configure DynamoDB on-demand billing** for variable workloads

## Cleanup

To remove all resources:

```bash
# Using the cleanup script
.\scripts\cleanup.ps1

# Or manually
cd terraform
terraform destroy
```

**Warning**: This will permanently delete all data and resources!

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review CloudWatch logs
3. Check Kubernetes events: `kubectl get events`
4. Verify AWS service quotas and limits
