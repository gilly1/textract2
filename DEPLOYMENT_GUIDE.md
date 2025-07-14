# DEPLOYMENT_GUIDE.md

# Complete Deployment Guide for Document Processor EKS Service

This guide will walk you through deploying the Document Processor service to Amazon EKS.

## 📋 Prerequisites Checklist

Before starting, ensure you have:

### 1. Required Tools Installed
- [ ] **AWS CLI v2** - [Download here](https://awscli.amazonaws.com/AWSCLIV2.msi)
- [ ] **Terraform v1.0+** - [Download here](https://www.terraform.io/downloads.html)
- [ ] **kubectl** - [Download here](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/)
- [ ] **Docker Desktop** - [Download here](https://www.docker.com/products/docker-desktop)

### 2. AWS Account Setup
- [ ] AWS Account with administrative access
- [ ] AWS CLI configured (`aws configure`)
- [ ] Sufficient AWS service limits (EKS, EC2, VPC)

### 3. Verify Prerequisites
```powershell
# Test AWS access
aws sts get-caller-identity

# Test other tools
terraform --version
kubectl version --client
docker --version
```

## 🚀 Quick Start (Automated Deployment)

### Option 1: One-Command Deployment
```powershell
# Navigate to project directory
cd c:\laragon\www\python\my_textract_3

# Run the complete deployment
.\scripts\deploy.ps1
```

### Option 2: Plan-Only Mode (Review Changes First)
```powershell
# See what will be created without deploying
.\scripts\deploy.ps1 -PlanOnly
```

## 📝 Manual Step-by-Step Deployment

If you prefer manual control or need to troubleshoot:

### Step 1: Configure Terraform Variables
```powershell
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your settings:
# - aws_region
# - project_name
# - environment
# - key_pair_name (optional)
```

### Step 2: Deploy Infrastructure
```powershell
cd terraform

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply
```

### Step 3: Build and Push Container
```powershell
# Build and push Docker image to ECR
.\scripts\build-docker.ps1
```

### Step 4: Deploy to Kubernetes
```powershell
# Deploy application to EKS
.\scripts\deploy-k8s.ps1
```

### Step 5: Test Deployment
```powershell
# Test the deployed service
.\scripts\test-processor.sh
```

## 🔍 What Gets Created

### AWS Infrastructure
- **EKS Cluster** with managed node groups
- **VPC** with public/private subnets across 3 AZs
- **S3 Bucket** for document storage
- **DynamoDB Table** for processing results
- **ECR Repository** for container images
- **IAM Roles** with least-privilege permissions
- **Application Load Balancer** for external access

### Kubernetes Resources
- **Deployment** with 3 replicas
- **Service** (ClusterIP)
- **Ingress** (ALB)
- **HorizontalPodAutoscaler** (2-10 replicas)
- **ServiceAccount** with IRSA
- **RBAC** configurations

## 📊 Monitoring Your Deployment

### Check Deployment Status
```powershell
# Get cluster info
kubectl cluster-info

# Check pods
kubectl get pods -l app=document-processor

# Check services
kubectl get services

# Check ingress (wait 5-10 minutes for ALB)
kubectl get ingress

# View logs
kubectl logs -l app=document-processor -f
```

### Get Service URL
```powershell
# Get the external URL (wait for ALB to be ready)
kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Test Health Check
```powershell
# Once you have the URL
$SERVICE_URL = "http://YOUR-ALB-HOSTNAME"
curl "$SERVICE_URL/health"
```

## 🧪 Testing the Service

### 1. Health Check
```powershell
curl http://YOUR-ALB-HOSTNAME/health
```

### 2. Upload Test Document to S3
```powershell
# Get S3 bucket name from Terraform
cd terraform
$BUCKET_NAME = terraform output -raw s3_bucket_name

# Upload a test PDF
aws s3 cp your-test-document.pdf "s3://$BUCKET_NAME/uploads/"
```

### 3. Process Document
```powershell
# Send processing request
$payload = @{
    record = @{
        document_id = "test-doc-$(Get-Date -Format 'yyyyMMddHHmmss')"
        bucket = $BUCKET_NAME
        key = "uploads/your-test-document.pdf"
        status = "pending"
        file_type = "pdf"
        upload_date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source = "manual-test"
    }
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "http://YOUR-ALB-HOSTNAME/process" -Method POST -Body $payload -ContentType "application/json"
```

### 4. Check Processing Status
```powershell
# Check status (use document_id from previous response)
curl "http://YOUR-ALB-HOSTNAME/status/YOUR-DOCUMENT-ID"
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Pods Stuck in Pending
```powershell
kubectl describe pod POD-NAME
# Look for resource constraints or node capacity issues
```

#### 2. Image Pull Errors
```powershell
# Check ECR repository
aws ecr describe-repositories --repository-names document-processor/document-processor

# Verify image exists
aws ecr list-images --repository-name document-processor/document-processor
```

#### 3. ALB Not Ready
```powershell
# Check ALB controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

#### 4. Application Errors
```powershell
# Check application logs
kubectl logs -l app=document-processor --tail=100
```

### Debug Commands
```powershell
# Port forward for local testing
kubectl port-forward service/document-processor-service 8080:80

# Execute commands in pod
kubectl exec -it POD-NAME -- /bin/bash

# Check resource usage
kubectl top pods
kubectl top nodes

# View events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## 📈 Scaling

### Manual Scaling
```powershell
# Scale pods
kubectl scale deployment document-processor --replicas=5

# Scale nodes (if needed)
aws eks update-nodegroup-config --cluster-name document-processor-cluster --nodegroup-name document-processor-workers --scaling-config minSize=3,maxSize=20,desiredSize=5
```

### Auto-scaling
The HPA automatically scales based on:
- CPU utilization (70% threshold)
- Memory utilization (80% threshold)
- Min: 2 replicas, Max: 10 replicas

## 💰 Cost Considerations

### Estimated Monthly Costs (us-east-1)
- **EKS Cluster**: ~$72/month
- **EC2 Worker Nodes** (3x t3.medium): ~$95/month
- **Application Load Balancer**: ~$22/month
- **DynamoDB** (on-demand): Variable
- **S3 Storage**: Variable
- **Data Transfer**: Variable

**Total Base Cost**: ~$190/month

### Cost Optimization Tips
1. Use Spot instances for worker nodes
2. Configure cluster autoscaler
3. Set appropriate resource requests/limits
4. Use S3 Intelligent Tiering
5. Configure DynamoDB on-demand billing

## 🔐 Security Features

### Implemented Security
- **Network**: Private subnets, security groups, NACLs
- **IAM**: Least privilege roles, IRSA for pods
- **Container**: Non-root user, resource limits
- **Data**: S3/DynamoDB encryption at rest
- **Access**: ALB with SSL termination (optional)

## 🧹 Cleanup

### Complete Cleanup
```powershell
# Remove everything
.\scripts\cleanup.ps1
```

### Manual Cleanup
```powershell
# Remove Kubernetes resources
kubectl delete -f k8s/ --ignore-not-found=true

# Destroy infrastructure
cd terraform
terraform destroy
```

**⚠️ Warning**: This permanently deletes all data and resources!

## 📞 Support

### Getting Help
1. Check this troubleshooting guide
2. Review CloudWatch logs
3. Check Kubernetes events: `kubectl get events`
4. Verify AWS service quotas

### Useful Resources
- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🎯 Next Steps

After successful deployment:

1. **Configure monitoring** with CloudWatch/Prometheus
2. **Set up CI/CD pipeline** for automated deployments
3. **Add SSL certificate** for HTTPS
4. **Configure backup strategy** for S3 and DynamoDB
5. **Implement log aggregation** with ELK or CloudWatch
6. **Add metrics collection** and alerting
7. **Scale testing** with load testing tools

## 📋 Environment Outputs

After deployment, you'll have:
```powershell
cd terraform

# Get all important information
terraform output
```

Key outputs:
- `cluster_name`: EKS cluster name
- `s3_bucket_name`: S3 bucket for documents
- `dynamodb_table_name`: DynamoDB table for results
- `ecr_repository_url`: ECR repository URL
- `configure_kubectl`: Command to configure kubectl

Save these values for future reference!
