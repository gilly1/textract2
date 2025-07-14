# Document Processor Service - EKS Deployment

A FastAPI-based document processing service that extracts text and QR codes from PDFs and images using OCR technology. Deployed on AWS EKS with full cloud infrastructure automation.

## Features

- **Document Processing**: Extract text and QR codes from PDF and image files
- **OCR Technology**: Uses Tesseract for high-quality text extraction
- **QR Code Detection**: Automatic QR code scanning and data extraction
- **Cloud Storage**: S3 integration for document storage
- **Database**: DynamoDB for processing results and status tracking
- **Kubernetes**: Scalable deployment on AWS EKS
- **IRSA Security**: IAM Roles for Service Accounts for secure AWS access

## Architecture

```
├── FastAPI Application (main.py)
├── AWS EKS Cluster
├── S3 Bucket (document-processor-documents)
├── DynamoDB Table (document-processor-results)
├── ECR Repository (document-processor/document-processor)
└── ALB Ingress Controller
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- Docker installed
- kubectl installed
- Terraform >= 1.0
- jq (optional, for JSON parsing in scripts)

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd my_textract_3
```

### 2. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates:
- EKS cluster with managed node groups
- VPC with public/private subnets
- S3 bucket for documents
- DynamoDB table for results
- ECR repository
- IAM roles with IRSA configuration

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name document-processor-cluster
```

### 4. Deploy Application

```bash
# Build and push Docker image
docker build -t document-processor:latest .
docker tag document-processor:latest 105714714499.dkr.ecr.us-east-1.amazonaws.com/document-processor/document-processor:latest

# Login to ECR and push
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 105714714499.dkr.ecr.us-east-1.amazonaws.com
docker push 105714714499.dkr.ecr.us-east-1.amazonaws.com/document-processor/document-processor:latest

# Deploy to Kubernetes
kubectl apply -f k8s/
```

### 5. Test the Service

```bash
# Run comprehensive tests
chmod +x scripts/test-processor.sh
./scripts/test-processor.sh
```

## Testing

1. **Get deployment outputs:**
   ```bash
   cd terraform
   terraform output
   ```

2. **Upload a test PDF:**
   ```bash
   aws s3 cp your-document.pdf s3://YOUR-BUCKET-NAME/uploads/
   ```

3. **Monitor processing:**
   - Check Step Functions console for execution status
   - View results in DynamoDB table

## Detailed Deployment Guide

### Infrastructure Components

#### EKS Cluster Configuration
- **Cluster Name**: `document-processor-cluster`
- **Kubernetes Version**: 1.28
- **Node Groups**: Managed with auto-scaling
- **IRSA Enabled**: For secure AWS service access

#### Storage Resources
- **S3 Bucket**: `document-processor-documents`
- **DynamoDB Table**: `document-processor-results`
  - Primary Key: `id` (String)
  - Global Secondary Index: `status-index`

#### Container Registry
- **ECR Repository**: `document-processor/document-processor`
- **Image Scanning**: Enabled
- **Lifecycle Policy**: Configured for image cleanup

### Application Configuration

#### Environment Variables
```yaml
AWS_DEFAULT_REGION: "us-east-1"
DYNAMODB_TABLE_NAME: "document-processor-results"
S3_BUCKET_NAME: "document-processor-documents"
```

#### Health Checks
- **Liveness Probe**: `/health` endpoint
- **Readiness Probe**: `/health` endpoint
- **Port**: 8080

### Security Configuration

#### IAM Roles and IRSA
```bash
# Service Account with IAM Role
kubectl annotate serviceaccount document-processor-sa \
  eks.amazonaws.com/role-arn=arn:aws:iam::105714714499:role/document-processor-pod-role \
  --overwrite
```

#### DynamoDB Permissions
- GetItem, PutItem, UpdateItem, Query
- Access to `document-processor-results` table

#### S3 Permissions
- GetObject, PutObject
- Access to `document-processor-documents` bucket

## API Endpoints

### Health Check
```bash
GET /health
```
Returns service health status.

### Process Document
```bash
POST /process
Content-Type: application/json

{
  "record": {
    "document_id": "unique-doc-id",
    "bucket": "document-processor-documents",
    "key": "document.pdf",
    "status": "pending",
    "file_type": "pdf",
    "source": "api"
  }
}
```

### Get Status
```bash
GET /status/{document_id}
```
Returns processing status and results.

## Testing

### Upload Test Document
```bash
# Upload sample document to S3
aws s3 cp invoice.pdf s3://document-processor-documents/test-document.pdf
```

### Run Tests
```bash
# Comprehensive service test
./scripts/test-processor.sh

# Check DynamoDB records
aws dynamodb scan --table-name document-processor-results --max-items 5
```

### Verify Deployment
```bash
# Check pod status
kubectl get pods -l app=document-processor

# Check service
kubectl get service document-processor-service

# Check ingress
kubectl get ingress document-processor-ingress

# View logs
kubectl logs -l app=document-processor -f
```

## Troubleshooting

### Common Issues and Solutions

#### 1. DynamoDB Schema Errors
**Issue**: "The provided key element does not match the schema"
**Solution**: Ensure using `id` as primary key, not `document_id`

#### 2. Float Type Errors
**Issue**: "Float types are not supported. Use Decimal types instead"
**Solution**: Use `convert_float_to_decimal()` function for DynamoDB operations

#### 3. Reserved Keyword Errors
**Issue**: "Attribute name is a reserved keyword: status"
**Solution**: Use `ExpressionAttributeNames` with `#status`

#### 4. IRSA Authentication Issues
**Issue**: AWS access denied from pods
**Solution**: Verify service account annotation points to correct IAM role

#### 5. ECR Repository Access
**Issue**: Image pull errors
**Solution**: Ensure ECR repository name matches deployment configuration

### Debug Commands
```bash
# Check pod logs for errors
kubectl logs -l app=document-processor --tail=100

# Describe pod for events
kubectl describe pod <pod-name>

# Check service account
kubectl get serviceaccount document-processor-sa -o yaml

# Verify IRSA configuration
kubectl describe serviceaccount document-processor-sa

# Test DynamoDB access
aws dynamodb describe-table --table-name document-processor-results

# Test S3 access
aws s3 ls s3://document-processor-documents/
```

## Automated Deployment Scripts

### Cross-Platform Deployment

**Windows PowerShell:**
```powershell
# Navigate to project directory
cd c:\laragon\www\python\my_textract_3

# Run automated deployment
.\scripts\deploy.ps1
```

**Linux/macOS:**
```bash
# Navigate to project directory
cd /path/to/my_textract_3

# Make scripts executable
chmod +x scripts/*.sh

# Run automated deployment
./scripts/deploy.sh
```

### Available Scripts

- `scripts/deploy.sh` / `scripts/deploy.ps1` - Complete deployment automation
- `scripts/test-processor.sh` - Service testing
- `scripts/update-deployment.sh` - Update existing deployment
- `scripts/fix-deployment.sh` - Fix deployment issues

### Script Options

**Plan-Only Mode:**
```bash
# Linux/macOS
./scripts/deploy.sh --plan-only

# Windows
.\scripts\deploy.ps1 -PlanOnly
```

## Cleanup

### Remove Application
```bash
kubectl delete -f k8s/
```

### Destroy Infrastructure
```bash
cd terraform
terraform destroy
```

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review pod logs: `kubectl logs -l app=document-processor`
3. Verify AWS resource configurations
4. Test individual components (S3, DynamoDB, ECR)

## License

This project is licensed under the MIT License.

4. **Automated testing:**
   ```bash
   python scripts/test_pipeline.py BUCKET_NAME STEP_FUNCTION_ARN TABLE_NAME path/to/test.pdf
   ```
