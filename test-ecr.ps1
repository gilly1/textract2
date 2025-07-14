# Test ECR Authentication
$AccountId = aws sts get-caller-identity --query Account --output text
$AWSRegion = "us-east-1"
$ProjectName = "docproc-714499"

Write-Host "Account ID: $AccountId" -ForegroundColor Green
Write-Host "Project Name: $ProjectName" -ForegroundColor Green
Write-Host "AWS Region: $AWSRegion" -ForegroundColor Green

# Test ECR repository exists
Write-Host "`nTesting ECR repository..." -ForegroundColor Yellow
try {
    $RepoInfo = aws ecr describe-repositories --repository-names "$ProjectName/document-processor" --region $AWSRegion --output json | ConvertFrom-Json
    Write-Host "✅ ECR Repository exists:" -ForegroundColor Green
    Write-Host "   Repository URI: $($RepoInfo.repositories[0].repositoryUri)" -ForegroundColor White
} catch {
    Write-Host "❌ ECR Repository does not exist" -ForegroundColor Red
    exit 1
}

# Test ECR authentication
Write-Host "`nTesting ECR authentication..." -ForegroundColor Yellow
try {
    $LoginPassword = aws ecr get-login-password --region $AWSRegion
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ ECR login password obtained" -ForegroundColor Green
        
        # Test Docker login
        $LoginPassword | docker login --username AWS --password-stdin "$AccountId.dkr.ecr.$AWSRegion.amazonaws.com"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Docker authentication successful" -ForegroundColor Green
        } else {
            Write-Host "❌ Docker authentication failed" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ Failed to get ECR login password" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ ECR authentication failed: $_" -ForegroundColor Red
}
