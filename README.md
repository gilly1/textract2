# Document Processor Service - ECS Deployment

A FastAPI-based document processing service that extracts text and QR codes from PDFs and images using OCR technology. Deployed on AWS ECS with full cloud infrastructure automation and Lambda-triggered processing.

## Features

- **Document Processing**: Extract text and QR codes from PDF and image files
- **OCR Technology**: Uses Tesseract for high-quality text extraction
- **QR Code Detection**: Automatic QR code scanning and data extraction
- **Cloud Storage**: S3 integration for document storage
- **Database**: DynamoDB for processing results and status tracking
- **Container Service**: Scalable deployment on AWS ECS Fargate
- **Event-Driven**: Lambda function triggered by DynamoDB streams
- **Automated Processing**: Documents are processed automatically when inserted into DynamoDB

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  File Upload    │    │   DynamoDB      │    │   Lambda        │
│  to S3          │───▶│   Record        │───▶│   Trigger       │
│                 │    │   Insert        │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  DynamoDB       │◀───│   FastAPI       │◀───│   HTTP POST     │
│  Status Update  │    │   /process      │    │   Request       │
│                 │    │   Endpoint      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Components:
- **FastAPI Application**: Document processing service running on ECS
- **AWS ECS Fargate**: Serverless container hosting
- **Application Load Balancer**: HTTP traffic routing
- **S3 Bucket**: Document storage (document-processor-documents)
- **DynamoDB Table**: Processing results with stream enabled
- **Lambda Function**: Triggers processing on new document inserts
- **ECR Repository**: Container image storage

## Prerequisites

- AWS CLI configured with appropriate permissions
- Docker installed
- Terraform >= 1.0
- Python 3.11+ (for Lambda function)

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd my_textract_3
```

### 2. One-Command Deployment

**Windows (PowerShell):**
```powershell
.\deploy.ps1
```

**Linux/macOS (Bash):**
```bash
chmod +x deploy.sh
./deploy.sh
```

This will:
- Deploy all AWS infrastructure via Terraform
- Build and push Docker image to ECR
- Deploy the ECS service
- Test the health endpoint
- Show service URLs and monitoring commands

### 3. Test the Complete Workflow

**Windows:**
```powershell
.\test-workflow.ps1 -TestFile "invoice.pdf"
```

**Linux/macOS:**
```bash
./test-workflow.sh invoice.pdf
```

This will:
- Upload a document to S3
- Insert a record in DynamoDB with status "pending"
- Lambda automatically triggers processing
- Monitor processing status until completion
- Display results

## Workflow

### Automated Processing Flow

1. **Upload Document**: Upload a PDF or image file to the S3 bucket
2. **Create Record**: Insert a record in DynamoDB with status "pending"
3. **Lambda Trigger**: DynamoDB stream automatically triggers the Lambda function
4. **API Call**: Lambda calls the FastAPI `/process` endpoint
5. **Processing**: FastAPI downloads file from S3, processes it with OCR
6. **Results**: Processing results are stored back in DynamoDB

### Manual Testing

You can test the entire workflow using the provided scripts:

#### Windows (PowerShell):
```powershell
.\test-workflow.ps1 -TestFile "invoice.pdf"
```

#### Linux/macOS (Bash):
```bash
chmod +x test-workflow.sh
./test-workflow.sh invoice.pdf
```

### Testing Steps

1. **Get deployment outputs:**
   ```bash
   cd infra
   terraform output
   ```

2. **Test complete workflow:**
   The test scripts will:
   - Upload your document to S3
   - Insert a "pending" record in DynamoDB
   - Wait for Lambda to trigger processing
   - Monitor the processing status
   - Display final results

3. **Manual API testing:**
   ```bash
   # Get ALB URL from Terraform output
   ALB_URL=$(cd infra && terraform output -raw load_balancer_url)
   
   # Test health endpoint
   curl $ALB_URL/health
   
   # Check document status
   curl $ALB_URL/status/YOUR_DOCUMENT_ID
   ```

3. **Monitor processing:**
   - Check Step Functions console for execution status
## Lambda Function

### Purpose
The Lambda function (`dynamodb_trigger.py`) automatically triggers document processing when new records are inserted into DynamoDB with status "pending".

### Configuration
- **Runtime**: Python 3.11
- **Timeout**: 60 seconds
- **Memory**: 128 MB (default)
- **Environment Variables**:
  - `ECS_SERVICE_URL`: ALB URL for the ECS service
  - `AWS_REGION`: Automatically provided by Lambda (us-east-1)

### Event Source
- **DynamoDB Stream**: Triggered on INSERT events only
- **Filter**: Only processes records with status "pending"
- **Starting Position**: LATEST

### Function Flow
1. Receives DynamoDB stream event
2. Filters for INSERT events with status "pending"
3. Converts DynamoDB format to API format
4. Calls FastAPI `/process` endpoint
5. Logs results and errors

### Monitoring Lambda
```bash
# View Lambda logs
aws logs tail /aws/lambda/document-processor-dynamodb-trigger --follow

# Check Lambda metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=document-processor-dynamodb-trigger \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 3600 \
    --statistics Sum
```

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
        "document_id": "unique-id",
        "bucket": "bucket-name",
        "key": "path/to/file.pdf",
        "status": "pending",
        "file_type": "pdf"
    }
}
```

### Get Processing Status
```bash
GET /status/{document_id}
```
Returns processing status and results for a document.

## Detailed Deployment Guide

### Infrastructure Components

#### ECS Configuration
- **Cluster Name**: `document-processor-cluster`
- **Service Type**: Fargate
- **Task Definition**: 256 CPU, 512 MB memory
- **Desired Count**: 1 (auto-scalable)
- **Load Balancer**: Application Load Balancer

#### Storage Resources
- **S3 Bucket**: `document-processor-documents`
  - Private access only
  - Used for document storage
- **DynamoDB Table**: `document-processor-results`
  - Primary Key: `id` (String)
  - Stream Enabled: NEW_AND_OLD_IMAGES
  - Billing Mode: PAY_PER_REQUEST

#### Container Registry
- **ECR Repository**: `document-processor`
- **Image Scanning**: Enabled
- **Latest Tag**: Always used for deployments

### Application Configuration

#### Environment Variables
```yaml
AWS_DEFAULT_REGION: "us-east-1"
DYNAMODB_TABLE_NAME: "document-processor-results"
```

#### Health Checks
- **Target Group Health Check**: `/health` endpoint
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Healthy Threshold**: 2
- **Unhealthy Threshold**: 2

### Security Configuration

#### IAM Roles
- **ECS Task Role**: Permissions for DynamoDB and S3 access
- **Lambda Role**: DynamoDB stream read permissions
- **ECS Execution Role**: ECR and CloudWatch permissions

#### S3 Permissions
- GetObject, PutObject
- Access to `document-processor-documents` bucket

## Testing

### Upload Test Document
```bash
# Upload sample document to S3
aws s3 cp invoice.pdf s3://document-processor-documents/test-document.pdf
```

### Run Tests
```bash
# Comprehensive service test
./test-workflow.sh invoice.pdf

# Check DynamoDB records
aws dynamodb scan --table-name document-processor-results --max-items 5
```

### Verify Deployment
```bash
# Check ECS service status
aws ecs describe-services --cluster document-processor-cluster --services document-processor-service

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names document-processor-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

# View ECS task logs
aws logs tail /ecs/document-processor --follow

# Test health endpoint
ALB_URL=$(cd infra && terraform output -raw load_balancer_url)
curl $ALB_URL/health
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Lambda Not Triggering
**Issue**: Lambda function doesn't trigger after DynamoDB insert
**Solutions**:
- Check DynamoDB stream is enabled: `aws dynamodb describe-table --table-name document-processor-results`
- Verify Lambda event source mapping: `aws lambda list-event-source-mappings`
- Check Lambda logs: `aws logs tail /aws/lambda/document-processor-dynamodb-trigger --follow`

#### 2. ECS Service Not Responding
**Issue**: ALB health checks failing
**Solutions**:
- Check ECS service status: `aws ecs describe-services --cluster document-processor-cluster --services document-processor-service`
- View ECS task logs: `aws logs tail /ecs/document-processor --follow`
- Verify security groups allow ALB to reach ECS tasks on port 8080

#### 3. Lambda API Call Failures
**Issue**: Lambda can't reach ECS service
**Solutions**:
- Verify ALB URL in Lambda environment variables
- Check ALB security group allows incoming traffic on port 80
- Test ALB URL manually: `curl http://ALB-URL/health`

#### 4. DynamoDB Access Errors
**Issue**: ECS tasks can't access DynamoDB
**Solutions**:
- Verify ECS task role has DynamoDB permissions
- Check task role policy includes UpdateItem, GetItem, PutItem actions
- Test DynamoDB access from ECS task

#### 5. ECR Image Pull Errors
**Issue**: ECS can't pull container image
**Solutions**:
- Verify ECR repository exists and has images
- Check ECS execution role has ECR permissions
- Re-push latest image to ECR

### Debug Commands

#### Lambda Function
```bash
# Check Lambda function configuration
aws lambda get-function --function-name document-processor-dynamodb-trigger

# View Lambda logs
aws logs tail /aws/lambda/document-processor-dynamodb-trigger --follow

# Test Lambda function manually
aws lambda invoke --function-name document-processor-dynamodb-trigger \
    --payload '{"Records":[{"eventName":"INSERT","dynamodb":{"NewImage":{"id":{"S":"test"},"status":{"S":"pending"},"bucket":{"S":"test-bucket"},"key":{"S":"test.pdf"},"file_type":{"S":"pdf"}}}}]}' \
    response.json
```

#### ECS Service
```bash
# Check ECS service status
aws ecs describe-services --cluster document-processor-cluster --services document-processor-service

# View ECS task logs
aws logs tail /ecs/document-processor --follow

# Check running tasks
aws ecs list-tasks --cluster document-processor-cluster --service-name document-processor-service

# Describe task for details
aws ecs describe-tasks --cluster document-processor-cluster --tasks TASK-ARN
```

#### DynamoDB Stream
```bash
# Check stream status
aws dynamodb describe-table --table-name document-processor-results | jq '.Table.StreamSpecification'

# List event source mappings
aws lambda list-event-source-mappings --function-name document-processor-dynamodb-trigger

# Check stream records
aws dynamodbstreams describe-stream --stream-arn STREAM-ARN
```

#### Load Balancer
```bash
# Check ALB status
aws elbv2 describe-load-balancers --names document-processor-alb

# Check target group health
aws elbv2 describe-target-health --target-group-arn TARGET-GROUP-ARN

# Test ALB endpoint
curl -v http://ALB-DNS-NAME/health
```

### Monitoring and Logging

#### CloudWatch Metrics
- **Lambda**: Invocations, Duration, Errors
- **ECS**: CPU/Memory utilization, Task count
- **ALB**: Request count, Response time, HTTP errors
- **DynamoDB**: Read/Write capacity, Throttled requests

#### Log Groups
- `/aws/lambda/document-processor-dynamodb-trigger`
- `/ecs/document-processor`
- `/aws/ecs/containerinsights/document-processor-cluster/performance`

## Automated Deployment Scripts

### Cross-Platform Testing

**Windows PowerShell:**
```powershell
# Test complete workflow
.\test-workflow.ps1 -TestFile "invoice.pdf"
```

**Linux/macOS Bash:**
```bash
# Test complete workflow
chmod +x test-workflow.sh
./test-workflow.sh invoice.pdf
```

### Deployment Automation

**Infrastructure Deployment:**
```bash
# Navigate to project directory
cd /path/to/my_textract_3

# Make scripts executable
chmod +x *.sh

# Run automated deployment
./deploy.sh
```

### Available Scripts

- `deploy.sh` / `deploy.ps1` - Complete deployment automation
- `test-workflow.sh` / `test-workflow.ps1` - End-to-end workflow testing

### Script Options

**Plan-Only Mode:**
```bash
# Linux/macOS
./deploy.sh

# Windows
.\deploy.ps1
```

## Cleanup

### Stop ECS Service
```bash
# Scale down ECS service
aws ecs update-service --cluster document-processor-cluster --service document-processor-service --desired-count 0

# Delete ECS service (optional)
aws ecs delete-service --cluster document-processor-cluster --service document-processor-service --force
```

### Destroy Infrastructure
```bash
cd infra
terraform destroy
```

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review ECS task logs: `aws logs tail /ecs/document-processor --follow`
3. Verify AWS resource configurations
4. Test individual components (S3, DynamoDB, ECR, ALB)

## License

This project is licensed under the MIT License.
