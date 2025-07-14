# Deploy Infrastructure and Application
param(
    [switch]$PlanOnly,
    [string]$AWSRegion = "us-east-1",
    [string]$ImageTag = "latest"
)

# Configuration
$ProjectName = "document-processor"

Write-Host "Starting deployment of $ProjectName..." -ForegroundColor Green

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check AWS CLI
try {
    aws --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI not found" }
} catch {
    Write-Host "Error: AWS CLI is required but not installed." -ForegroundColor Red
    exit 1
}

# Check Terraform
try {
    terraform --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Terraform not found" }
} catch {
    Write-Host "Error: Terraform is required but not installed." -ForegroundColor Red
    exit 1
}

# Check kubectl
try {
    kubectl version --client | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "kubectl not found" }
} catch {
    Write-Host "Error: kubectl is required but not installed." -ForegroundColor Red
    exit 1
}

# Check Docker
try {
    docker --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Docker not found" }
} catch {
    Write-Host "Error: Docker is required but not installed." -ForegroundColor Red
    exit 1
}

# Check AWS credentials
try {
    $AccountId = aws sts get-caller-identity --query Account --output text
    if ($LASTEXITCODE -ne 0) {
        throw "AWS credentials not configured"
    }
    Write-Host "AWS Account ID: $AccountId" -ForegroundColor Green
} catch {
    Write-Host "Error: AWS credentials not configured. Run 'aws configure'." -ForegroundColor Red
    exit 1
}

# Step 1: Initialize and Deploy Infrastructure
Write-Host "`n=== Step 1: Deploying Infrastructure ===" -ForegroundColor Cyan

Push-Location terraform

# Check if terraform.tfvars exists
if (-not (Test-Path "terraform.tfvars")) {
    Write-Host "Creating terraform.tfvars from example..." -ForegroundColor Yellow
    Copy-Item "terraform.tfvars.example" "terraform.tfvars"
    Write-Host "Please edit terraform.tfvars with your specific values and run the script again." -ForegroundColor Yellow
    Pop-Location
    exit 1
}

# Initialize Terraform
Write-Host "Initializing Terraform..." -ForegroundColor Green
terraform init

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Terraform initialization failed" -ForegroundColor Red
    Pop-Location
    exit 1
}

# Plan infrastructure
Write-Host "Planning infrastructure..." -ForegroundColor Green
terraform plan -out=tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Terraform planning failed" -ForegroundColor Red
    Pop-Location
    exit 1
}

if ($PlanOnly) {
    Write-Host "Plan-only mode enabled. Exiting..." -ForegroundColor Yellow
    Pop-Location
    exit 0
}

# Apply infrastructure
Write-Host "Applying infrastructure..." -ForegroundColor Green
terraform apply tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Terraform apply failed" -ForegroundColor Red
    Pop-Location
    exit 1
}

Pop-Location

Write-Host "✅ Infrastructure deployed successfully!" -ForegroundColor Green

# Step 2: Build and Push Docker Image
Write-Host "`n=== Step 2: Building and Pushing Docker Image ===" -ForegroundColor Cyan

try {
    & .\scripts\build-docker.ps1 -ImageTag $ImageTag -AWSRegion $AWSRegion
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed"
    }
} catch {
    Write-Host "Error: Failed to build and push Docker image" -ForegroundColor Red
    exit 1
}

# Step 3: Deploy to EKS
Write-Host "`n=== Step 3: Deploying to EKS ===" -ForegroundColor Cyan

# Wait a moment for EKS cluster to be fully ready
Write-Host "Waiting for EKS cluster to be fully ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

try {
    & .\scripts\deploy-k8s.ps1 -ImageTag $ImageTag -AWSRegion $AWSRegion
    if ($LASTEXITCODE -ne 0) {
        throw "EKS deployment failed"
    }
} catch {
    Write-Host "Error: Failed to deploy to EKS" -ForegroundColor Red
    exit 1
}

# Step 4: Test Deployment
Write-Host "`n=== Step 4: Testing Deployment ===" -ForegroundColor Cyan

Write-Host "Waiting for services to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

# Get deployment information
Write-Host "`n=== Deployment Information ===" -ForegroundColor Cyan

Push-Location terraform

Write-Host "Cluster Information:" -ForegroundColor Green
$ClusterName = terraform output -raw cluster_name
$ClusterEndpoint = terraform output -raw cluster_endpoint
$S3Bucket = terraform output -raw s3_bucket_name
$DynamoTable = terraform output -raw dynamodb_table_name
$EcrRepo = terraform output -raw ecr_repository_url

Write-Host "  Cluster Name: $ClusterName" -ForegroundColor White
Write-Host "  Cluster Endpoint: $ClusterEndpoint" -ForegroundColor White
Write-Host "  S3 Bucket: $S3Bucket" -ForegroundColor White
Write-Host "  DynamoDB Table: $DynamoTable" -ForegroundColor White
Write-Host "  ECR Repository: $EcrRepo" -ForegroundColor White

Write-Host "`nKubectl Configuration:" -ForegroundColor Green
$KubectlCommand = terraform output -raw configure_kubectl
Write-Host "  $KubectlCommand" -ForegroundColor White

# Execute kubectl configuration
Write-Host "Configuring kubectl..." -ForegroundColor Yellow
Invoke-Expression $KubectlCommand

# Check for kubectl authentication issues and fix them
Write-Host "Checking kubectl authentication..." -ForegroundColor Yellow
$TestConnection = kubectl cluster-info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Detected kubectl authentication issue, attempting to fix..." -ForegroundColor Yellow
    
    # Try to fix the apiVersion issue
    $KubeconfigFile = "$env:USERPROFILE\.kube\config"
    if (Test-Path $KubeconfigFile) {
        # Backup the config
        Copy-Item $KubeconfigFile "$KubeconfigFile.backup" -Force
        
        # Replace v1alpha1 with v1beta1
        $Content = Get-Content $KubeconfigFile -Raw
        $UpdatedContent = $Content -replace 'client\.authentication\.k8s\.io/v1alpha1', 'client.authentication.k8s.io/v1beta1'
        $UpdatedContent | Set-Content $KubeconfigFile
        
        Write-Host "Updated kubectl config authentication version" -ForegroundColor Green
        
        # Test connection again
        $TestConnection = kubectl cluster-info 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ kubectl authentication fixed" -ForegroundColor Green
        } else {
            Write-Host "❌ kubectl authentication still failing, restoring backup..." -ForegroundColor Yellow
            # Restore backup
            Copy-Item "$KubeconfigFile.backup" $KubeconfigFile -Force
        }
    }
}

Pop-Location

# Get service URL
Write-Host "`nService Information:" -ForegroundColor Green
$IngressHostname = kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
if ($IngressHostname) {
    Write-Host "  External URL: http://$IngressHostname" -ForegroundColor White
    Write-Host "  Health Check: http://$IngressHostname/health" -ForegroundColor White
} else {
    Write-Host "  External URL: Pending (check in a few minutes)" -ForegroundColor Yellow
    Write-Host "  Use 'kubectl get ingress' to check status" -ForegroundColor Yellow
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Wait for the load balancer to be ready (5-10 minutes)" -ForegroundColor White
Write-Host "2. Test the service:" -ForegroundColor White
Write-Host "   kubectl get ingress document-processor-ingress" -ForegroundColor Gray
Write-Host "3. Check logs:" -ForegroundColor White
Write-Host "   kubectl logs -l app=document-processor -f" -ForegroundColor Gray
Write-Host "4. Upload test documents to S3 bucket: $S3Bucket" -ForegroundColor White
Write-Host "5. Monitor results in DynamoDB table: $DynamoTable" -ForegroundColor White

Write-Host "`n✅ Deployment completed successfully!" -ForegroundColor Green
Write-Host "The document processor service is now running on EKS!" -ForegroundColor Green
