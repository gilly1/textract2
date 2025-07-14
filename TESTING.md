# Testing Guide

This guide covers how to test your EKS deployment using the provided testing scripts for both Windows and Linux/macOS environments.

## Prerequisites

- AWS CLI configured with appropriate permissions
- kubectl installed and configured
- curl (for Linux/macOS) or PowerShell (for Windows)
- A test PDF file named `invoice.pdf` (or use the sample creation script)

## Testing Scripts Overview

### Windows PowerShell Scripts
- `test-deployment.ps1` - Infrastructure verification
- `test-api.ps1` - API functionality testing
- `load-test.ps1` - Load testing
- `create-sample-invoice.ps1` - Creates sample invoice.pdf

### Linux/macOS Shell Scripts
- `test-deployment.sh` - Infrastructure verification
- `test-api.sh` - API functionality testing  
- `load-test.sh` - Load testing
- `create-sample-invoice.sh` - Creates sample invoice.pdf

## Step-by-Step Testing Process

### Step 1: Create Sample Invoice (Optional)

If you don't have an `invoice.pdf` file, create one:

**Windows:**
```powershell
.\scripts\create-sample-invoice.ps1
```

**Linux/macOS:**
```bash
./scripts/create-sample-invoice.sh
```

This creates a sample invoice PDF with:
- Company header and billing information
- Invoice details and line items
- QR code placeholder for testing
- Various text elements for OCR testing

### Step 2: Verify Infrastructure

**Windows:**
```powershell
.\scripts\test-deployment.ps1
```

**Linux/macOS:**
```bash
./scripts/test-deployment.sh
```

This script checks:
- ✅ EKS cluster status (should be ACTIVE)
- ✅ S3 bucket accessibility
- ✅ DynamoDB table status (should be ACTIVE)
- ✅ ECR repository existence
- ✅ Kubernetes pods (should be Running)
- ✅ Service external IP assignment
- ✅ Ingress hostname availability
- ✅ Application health check

### Step 3: Test API Functionality

**Windows:**
```powershell
# Basic API test (automatically finds invoice.pdf)
.\scripts\test-api.ps1

# Test with specific file
.\scripts\test-api.ps1 -TestFile "path\to\your\document.pdf"

# Test with specific endpoint
.\scripts\test-api.ps1 -ServiceEndpoint "http://your-endpoint"
```

**Linux/macOS:**
```bash
# Basic API test (automatically finds invoice.pdf)
./scripts/test-api.sh

# Test with specific file
./scripts/test-api.sh "http://your-endpoint" "path/to/your/document.pdf"

# Test with auto-detected endpoint and specific file
./scripts/test-api.sh "" "invoice.pdf"
```

This script tests:
- ✅ Health endpoint (`/health`)
- ✅ Root endpoint (`/`)
- ✅ Document upload (`/process`)
- ✅ Processing status check (`/status/{id}`)
- ✅ Results listing (`/results`)

### Step 4: Load Testing (Optional)

**Windows:**
```powershell
# Basic load test (10 requests, 3 concurrent)
.\scripts\load-test.ps1

# Custom load test
.\scripts\load-test.ps1 -Requests 50 -Concurrent 10
```

**Linux/macOS:**
```bash
# Basic load test (10 requests, 3 concurrent)
./scripts/load-test.sh

# Custom load test
./scripts/load-test.sh "http://your-endpoint" 50 10
```

This tests:
- Response times under load
- Concurrent request handling
- Service reliability
- Auto-scaling behavior

## Expected Results

### Successful Deployment Indicators

**Infrastructure:**
- EKS cluster: `ACTIVE`
- DynamoDB table: `ACTIVE`  
- S3 bucket: Accessible
- ECR repository: Exists
- Pods: All `Running`
- Service: External IP assigned
- Ingress: Hostname available

**API Tests:**
- Health check: Returns `{"status": "healthy"}`
- Root endpoint: Returns service information
- Document upload: Returns processing ID
- Status check: Shows processing progress
- Results: Lists stored results

**Load Tests:**
- All requests successful
- Response times under 2000ms
- No failed requests
- Consistent performance

### Troubleshooting Common Issues

**Pods Not Running:**
```bash
kubectl get pods -l app=document-processor
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

**Service Not Accessible:**
```bash
kubectl get service document-processor-service
kubectl get ingress document-processor-ingress
```

**Health Check Failing:**
- Wait 2-3 minutes for pods to fully start
- Check if all required environment variables are set
- Verify AWS permissions (S3, DynamoDB access)

**File Upload Failing:**
- Check S3 bucket permissions
- Verify ECR image was pushed correctly
- Check application logs for errors

## Manual Testing with Browser/Postman

Once you get the service endpoint from the test scripts:

1. **Swagger UI**: Visit `http://your-endpoint/docs`
2. **Health Check**: `GET http://your-endpoint/health`
3. **Upload Document**: 
   - `POST http://your-endpoint/process`
   - Form data with `file` field
   - Use `invoice.pdf` as test file

## Performance Expectations

**Processing Times:**
- Small PDF (1-2 pages): 5-15 seconds
- Medium PDF (3-10 pages): 15-45 seconds
- Large PDF (10+ pages): 45+ seconds

**Scaling:**
- HPA will scale pods based on CPU usage
- Target: 50% CPU utilization
- Min replicas: 3, Max replicas: 10

## Sample Test Results

```
=== Infrastructure Test ===
✅ EKS Cluster is ACTIVE
✅ S3 Bucket exists and accessible  
✅ DynamoDB Table is ACTIVE
✅ ECR Repository exists
✅ 3 pod(s) running
✅ Service has external IP: a1b2c3d4-123456789.us-east-1.elb.amazonaws.com
✅ Ingress has hostname: k8s-default-docproc-a1b2c3d4-123456789.us-east-1.elb.amazonaws.com

=== API Test ===
✅ Health Check: {"status":"healthy"}
✅ Root Endpoint: {"message":"Document Processing Service","version":"1.0.0"}
✅ Upload successful! Processing ID: abc123-def456-ghi789
✅ Status: {"processing_id":"abc123-def456-ghi789","status":"completed","extracted_text":"ACME Corporation..."}
✅ Results retrieved: 1 items

=== Load Test ===
Total Requests: 20
Successful: 20
Failed: 0
Average Response Time: 145ms
Min Response Time: 89ms  
Max Response Time: 234ms
```

## File Locations

The test scripts will automatically look for `invoice.pdf` in these locations:
1. Current directory (`./invoice.pdf`)
2. Samples directory (`./samples/invoice.pdf`)
3. Parent directory (`../invoice.pdf`)

If not found, you'll be prompted to create one or specify the path manually.

## Next Steps

After successful testing:
1. Monitor the application in production
2. Set up CloudWatch alerts for key metrics
3. Configure log aggregation (CloudWatch Logs)
4. Set up backup procedures for S3 and DynamoDB
5. Plan for disaster recovery scenarios

For cleanup when done testing, use the cleanup scripts:
- Windows: `.\scripts\cleanup.ps1`
- Linux/macOS: `./scripts/cleanup.sh`
