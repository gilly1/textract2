# Simplified Docker Build and Push
param(
    [string]$ImageTag = "latest"
)

$ErrorActionPreference = "Stop"

try {
    # Get configuration
    $AccountId = aws sts get-caller-identity --query Account --output text
    $AWSRegion = "us-east-1"
    $ProjectName = "docproc-714499"
    $RepoName = "$ProjectName/document-processor"
    $EcrUri = "$AccountId.dkr.ecr.$AWSRegion.amazonaws.com/$RepoName"
    
    Write-Host "Configuration:" -ForegroundColor Green
    Write-Host "  Account ID: $AccountId" -ForegroundColor White
    Write-Host "  Region: $AWSRegion" -ForegroundColor White
    Write-Host "  Repository: $RepoName" -ForegroundColor White
    Write-Host "  ECR URI: $EcrUri" -ForegroundColor White
    
    # Step 1: Verify ECR repository exists
    Write-Host "`nStep 1: Verifying ECR repository..." -ForegroundColor Yellow
    aws ecr describe-repositories --repository-names $RepoName --region $AWSRegion | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ECR repository $RepoName does not exist"
    }
    Write-Host "✅ ECR repository exists" -ForegroundColor Green
    
    # Step 2: Authenticate with ECR using newer method
    Write-Host "`nStep 2: Authenticating with ECR..." -ForegroundColor Yellow
    $EcrRegistry = "$AccountId.dkr.ecr.$AWSRegion.amazonaws.com"
    
    # Use the newer get-login-password method with PowerShell-compatible approach
    $Password = aws ecr get-login-password --region $AWSRegion
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get ECR login password"
    }
    
    # Use PowerShell to pass password to docker login
    $Password | docker login --username AWS --password-stdin $EcrRegistry
    if ($LASTEXITCODE -ne 0) {
        throw "Docker login to ECR failed"
    }
    Write-Host "✅ ECR authentication successful" -ForegroundColor Green
    
    # Step 3: Build Docker image
    Write-Host "`nStep 3: Building Docker image..." -ForegroundColor Yellow
    docker build -t "${ProjectName}:${ImageTag}" .
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed"
    }
    Write-Host "✅ Docker build successful" -ForegroundColor Green
    
    # Step 4: Tag for ECR
    Write-Host "`nStep 4: Tagging image for ECR..." -ForegroundColor Yellow
    docker tag "${ProjectName}:${ImageTag}" "${EcrUri}:${ImageTag}"
    docker tag "${ProjectName}:${ImageTag}" "${EcrUri}:latest"
    Write-Host "✅ Image tagged successfully" -ForegroundColor Green
    
    # Step 5: Push to ECR
    Write-Host "`nStep 5: Pushing to ECR..." -ForegroundColor Yellow
    docker push "${EcrUri}:${ImageTag}"
    docker push "${EcrUri}:latest"
    if ($LASTEXITCODE -ne 0) {
        throw "Docker push failed"
    }
    Write-Host "✅ Docker push successful" -ForegroundColor Green
    
    Write-Host "`n🎉 Success! Image pushed to: ${EcrUri}:${ImageTag}" -ForegroundColor Green
    
} catch {
    Write-Host "`n❌ Error: $_" -ForegroundColor Red
    exit 1
}
