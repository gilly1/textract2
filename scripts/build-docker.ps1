# Build Docker Image for Document Processor
param(
    [string]$ImageTag = "latest",
    [string]$AWSRegion = "us-east-1"
)

# Configuration
$ProjectName = "docproc-714499"

Write-Host "Building Document Processor Docker Image..." -ForegroundColor Green

# Get AWS account ID
try {
    $AccountId = aws sts get-caller-identity --query Account --output text
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get AWS account ID"
    }
} catch {
    Write-Host "Error: Failed to get AWS account ID. Make sure AWS CLI is configured." -ForegroundColor Red
    exit 1
}

# ECR repository URL
$EcrRepo = "$AccountId.dkr.ecr.$AWSRegion.amazonaws.com/$ProjectName/document-processor"

Write-Host "ECR Repository: $EcrRepo" -ForegroundColor Yellow

# Check if ECR repository exists
Write-Host "Checking if ECR repository exists..." -ForegroundColor Green
try {
    aws ecr describe-repositories --repository-names "$ProjectName/document-processor" --region $AWSRegion | Out-Null
    Write-Host "ECR repository exists" -ForegroundColor Green
} catch {
    Write-Host "ECR repository does not exist. Please run 'terraform apply' first to create the infrastructure." -ForegroundColor Red
    exit 1
}

# Authenticate Docker to ECR
Write-Host "Authenticating Docker to ECR..." -ForegroundColor Green

# Get the login password first
$LoginPassword = aws ecr get-login-password --region $AWSRegion
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to get ECR login password" -ForegroundColor Red
    exit 1
}

# Authenticate using the password
$LoginPassword | docker login --username AWS --password-stdin "$AccountId.dkr.ecr.$AWSRegion.amazonaws.com"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to authenticate with ECR" -ForegroundColor Red
    Write-Host "ECR Registry: $AccountId.dkr.ecr.$AWSRegion.amazonaws.com" -ForegroundColor Yellow
    exit 1
}

# Build the Docker image
Write-Host "Building Docker image..." -ForegroundColor Green
docker build -t "${ProjectName}:$ImageTag" .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to build Docker image" -ForegroundColor Red
    exit 1
}

# Tag the image for ECR
Write-Host "Tagging image for ECR..." -ForegroundColor Green
docker tag "${ProjectName}:$ImageTag" "${EcrRepo}:$ImageTag"
docker tag "${ProjectName}:$ImageTag" "${EcrRepo}:latest"

# Push to ECR
Write-Host "Pushing image to ECR..." -ForegroundColor Green
docker push "${EcrRepo}:$ImageTag"
docker push "${EcrRepo}:latest"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to push image to ECR" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Docker image built and pushed successfully!" -ForegroundColor Green
Write-Host "Image URL: ${EcrRepo}:$ImageTag" -ForegroundColor Yellow
