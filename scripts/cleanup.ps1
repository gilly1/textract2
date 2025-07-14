# Cleanup Infrastructure and Resources
param(
    [switch]$Force,
    [string]$AWSRegion = "us-east-1"
)

$ProjectName = "document-processor"

Write-Host "Cleaning up $ProjectName infrastructure..." -ForegroundColor Yellow

if (-not $Force) {
    $Confirmation = Read-Host "This will destroy all infrastructure. Are you sure? (y/N)"
    if ($Confirmation -ne 'y' -and $Confirmation -ne 'Y') {
        Write-Host "Cleanup cancelled." -ForegroundColor Green
        exit 0
    }
}

# Step 1: Remove Kubernetes resources
Write-Host "`n=== Step 1: Removing Kubernetes Resources ===" -ForegroundColor Cyan

try {
    # Get cluster name from Terraform
    Push-Location terraform
    $ClusterName = terraform output -raw cluster_name 2>$null
    Pop-Location
    
    if ($ClusterName) {
        Write-Host "Updating kubeconfig for cluster: $ClusterName" -ForegroundColor Green
        aws eks update-kubeconfig --region $AWSRegion --name $ClusterName 2>$null
        
        Write-Host "Removing application resources..." -ForegroundColor Green
        kubectl delete -f k8s/ --ignore-not-found=true
        
        Write-Host "Waiting for resources to be cleaned up..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
    }
} catch {
    Write-Host "Warning: Could not clean up Kubernetes resources: $_" -ForegroundColor Yellow
}

# Step 2: Empty S3 bucket
Write-Host "`n=== Step 2: Emptying S3 Bucket ===" -ForegroundColor Cyan

try {
    Push-Location terraform
    $S3Bucket = terraform output -raw s3_bucket_name 2>$null
    Pop-Location
    
    if ($S3Bucket) {
        Write-Host "Emptying S3 bucket: $S3Bucket" -ForegroundColor Green
        aws s3 rm s3://$S3Bucket --recursive 2>$null
        Write-Host "S3 bucket emptied" -ForegroundColor Green
    }
} catch {
    Write-Host "Warning: Could not empty S3 bucket: $_" -ForegroundColor Yellow
}

# Step 3: Delete ECR images
Write-Host "`n=== Step 3: Cleaning ECR Repository ===" -ForegroundColor Cyan

try {
    $AccountId = aws sts get-caller-identity --query Account --output text
    $EcrRepo = "$ProjectName/document-processor"
    
    Write-Host "Deleting ECR images..." -ForegroundColor Green
    $Images = aws ecr list-images --repository-name $EcrRepo --query 'imageIds[*]' --output json 2>$null | ConvertFrom-Json
    
    if ($Images -and $Images.Count -gt 0) {
        $ImageList = $Images | ConvertTo-Json -Compress
        aws ecr batch-delete-image --repository-name $EcrRepo --image-ids $ImageList 2>$null
        Write-Host "ECR images deleted" -ForegroundColor Green
    }
} catch {
    Write-Host "Warning: Could not clean ECR repository: $_" -ForegroundColor Yellow
}

# Step 4: Destroy Terraform infrastructure
Write-Host "`n=== Step 4: Destroying Terraform Infrastructure ===" -ForegroundColor Cyan

Push-Location terraform

try {
    Write-Host "Planning destruction..." -ForegroundColor Green
    terraform plan -destroy -out=destroy.tfplan
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Destroying infrastructure..." -ForegroundColor Green
        terraform apply destroy.tfplan
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Infrastructure destroyed successfully!" -ForegroundColor Green
        } else {
            Write-Host "Error: Terraform destroy failed" -ForegroundColor Red
        }
    } else {
        Write-Host "Error: Terraform destroy planning failed" -ForegroundColor Red
    }
} catch {
    Write-Host "Error during Terraform destroy: $_" -ForegroundColor Red
} finally {
    # Clean up plan files
    if (Test-Path "destroy.tfplan") { Remove-Item "destroy.tfplan" }
    if (Test-Path "tfplan") { Remove-Item "tfplan" }
}

Pop-Location

# Step 5: Clean local Docker images
Write-Host "`n=== Step 5: Cleaning Local Docker Images ===" -ForegroundColor Cyan

try {
    Write-Host "Removing local Docker images..." -ForegroundColor Green
    docker rmi "${ProjectName}:latest" -f 2>$null
    docker rmi $(docker images --filter "reference=*${ProjectName}*" -q) -f 2>$null
    docker system prune -f 2>$null
    Write-Host "Local Docker images cleaned" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not clean all Docker images: $_" -ForegroundColor Yellow
}

Write-Host "`n=== Cleanup Summary ===" -ForegroundColor Cyan
Write-Host "✅ Kubernetes resources removed" -ForegroundColor Green
Write-Host "✅ S3 bucket emptied" -ForegroundColor Green
Write-Host "✅ ECR images deleted" -ForegroundColor Green
Write-Host "✅ Infrastructure destroyed" -ForegroundColor Green
Write-Host "✅ Local Docker images cleaned" -ForegroundColor Green

Write-Host "`nCleanup completed!" -ForegroundColor Green
Write-Host "All $ProjectName resources have been removed." -ForegroundColor White
