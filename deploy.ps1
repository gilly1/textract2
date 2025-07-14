# ECS Deployment Script for Document Processor
# PowerShell version for Windows

param(
    [switch]$SkipTerraform = $false
)

$ErrorActionPreference = "Stop"

# Configuration
$APP_NAME = "document-processor"
$AWS_REGION = "us-east-1"

function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Green
}

function Write-Error-Log {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Write-Warning-Log {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

# Get AWS Account ID
try {
    $ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
    if ($LASTEXITCODE -ne 0) { throw "Failed to get AWS account ID" }
}
catch {
    Write-Error-Log "Failed to get AWS account ID. Make sure AWS CLI is configured."
}

$ECR_REPO = "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME"

Write-Log "🚀 Starting ECS deployment for Document Processor..."
Write-Log "Account ID: $ACCOUNT_ID"
Write-Log "ECR Repository: $ECR_REPO"

# Step 0: Build Lambda Package
Write-Log "📦 Building Lambda deployment package..."
try {
    .\build-lambda.ps1
}
catch {
    Write-Error-Log "Failed to build Lambda package: $_"
}

# Step 1: Deploy Infrastructure
if (-not $SkipTerraform) {
    Write-Log "📦 Deploying infrastructure with Terraform..."
    Push-Location infra
    
    try {
        terraform init
        terraform plan
        
        $apply = Read-Host "Do you want to apply the Terraform plan? (y/n)"
        
        if ($apply -eq "y") {
            terraform apply -auto-approve
            Write-Log "✅ Infrastructure deployed successfully!"
        }
        else {
            Write-Log "⏭️ Skipping Terraform apply."
            Pop-Location
            exit 0
        }
        
        # Get outputs
        $ECR_REPO_URL = terraform output -raw ecr_repository_url
        $S3_BUCKET = terraform output -raw s3_bucket_name
        $DYNAMODB_TABLE = terraform output -raw dynamodb_table_name
        $ALB_URL = terraform output -raw load_balancer_url
    }
    finally {
        Pop-Location
    }
    
    Write-Log ""
    Write-Log "📋 Infrastructure Details:"
    Write-Log "- ECR Repository: $ECR_REPO_URL"
    Write-Log "- S3 Bucket: $S3_BUCKET"
    Write-Log "- DynamoDB Table: $DYNAMODB_TABLE"
    Write-Log "- ALB URL: $ALB_URL"
    Write-Log ""
}
else {
    Write-Log "⏭️ Skipping Terraform deployment."
    $ECR_REPO_URL = $ECR_REPO
}

# Step 2: Build Docker Image
Write-Log "🔧 Building Docker image..."
try {
    docker build -t $APP_NAME .
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }
}
catch {
    Write-Error-Log "Failed to build Docker image: $_"
}

# Step 3: Authenticate with ECR
Write-Log "🔐 Logging into Amazon ECR..."
try {
    $loginCommand = aws ecr get-login-password --region $AWS_REGION
    if ($LASTEXITCODE -ne 0) { throw "Failed to get ECR login token" }
    
    $loginCommand | docker login --username AWS --password-stdin $ECR_REPO_URL
    if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }
}
catch {
    Write-Error-Log "Failed to authenticate with ECR: $_"
}

# Step 4: Tag Docker Image
Write-Log "🏷️ Tagging image as ${ECR_REPO_URL}:latest..."
try {
    docker tag "${APP_NAME}:latest" "${ECR_REPO_URL}:latest"
    if ($LASTEXITCODE -ne 0) { throw "Docker tag failed" }
}
catch {
    Write-Error-Log "Failed to tag Docker image: $_"
}

# Step 5: Push to ECR
Write-Log "📤 Pushing image to ECR..."
try {
    docker push "${ECR_REPO_URL}:latest"
    if ($LASTEXITCODE -ne 0) { throw "Docker push failed" }
}
catch {
    Write-Error-Log "Failed to push image to ECR: $_"
}

# Step 6: Wait for ECS Service to Update
Write-Log "⏳ Waiting for ECS service to update with new image..."
Start-Sleep -Seconds 30

# Check ECS service status
Write-Log "📊 Checking ECS service status..."
try {
    aws ecs describe-services --cluster "$APP_NAME-cluster" --services "$APP_NAME-service" --query 'services[0].{Status:status,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}' --output table
}
catch {
    Write-Warning-Log "Could not get ECS service status: $_"
}

# Step 7: Test Health Endpoint
if (-not $SkipTerraform -and $ALB_URL) {
    Write-Log "🏥 Testing health endpoint..."
    $healthCheckPassed = $false
    
    for ($i = 1; $i -le 12; $i++) {
        Write-Log "Health check attempt $i/12..."
        
        try {
            $response = Invoke-RestMethod -Uri "$ALB_URL/health" -Method Get -TimeoutSec 10
            Write-Log "✅ Health check passed!"
            $healthCheckPassed = $true
            break
        }
        catch {
            Write-Log "⏳ Health check failed, retrying in 15 seconds..."
            Start-Sleep -Seconds 15
        }
    }
    
    if (-not $healthCheckPassed) {
        Write-Warning-Log "❌ Health check failed after 12 attempts"
        Write-Warning-Log "Check ECS service logs for issues"
    }
}

Write-Log ""
Write-Log "✅ Deployment completed!"
Write-Log ""

if (-not $SkipTerraform -and $ALB_URL) {
    Write-Log "🔗 Service URLs:"
    Write-Log "- Health Check: $ALB_URL/health"
    Write-Log "- API Docs: $ALB_URL/docs"
    Write-Log ""
    Write-Log "📋 Test the workflow:"
    Write-Log "- Run: .\test-workflow.ps1 -TestFile 'invoice.pdf'"
    Write-Log ""
}

Write-Log "📊 Monitor with:"
Write-Log "- Lambda logs: aws logs tail /aws/lambda/$APP_NAME-dynamodb-trigger --follow"
Write-Log "- ECS logs: aws logs tail /ecs/$APP_NAME --follow"
