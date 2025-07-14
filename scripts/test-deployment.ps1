# Test Deployment Script
param(
    [string]$AWSRegion = "us-east-1"
)

$ProjectName = "dp714"

Write-Host "Testing $ProjectName deployment..." -ForegroundColor Cyan

# Test 1: Check AWS resources
Write-Host "`n=== Step 1: Verifying AWS Infrastructure ===" -ForegroundColor Yellow

try {
    # Check EKS cluster
    $ClusterStatus = aws eks describe-cluster --name "${ProjectName}-cluster" --region $AWSRegion --query 'cluster.status' --output text 2>$null
    if ($ClusterStatus -eq "ACTIVE") {
        Write-Host "✅ EKS Cluster is ACTIVE" -ForegroundColor Green
    } else {
        Write-Host "❌ EKS Cluster status: $ClusterStatus" -ForegroundColor Red
    }

    # Check S3 bucket
    Write-Host "Checking S3 bucket..." -ForegroundColor Yellow
    # Get the actual bucket name from Terraform
    Push-Location terraform -ErrorAction SilentlyContinue
    $S3Bucket = terraform output -raw s3_bucket_name 2>$null
    Pop-Location -ErrorAction SilentlyContinue
    
    if ($S3Bucket -and (aws s3api head-bucket --bucket $S3Bucket 2>$null; $LASTEXITCODE -eq 0)) {
        Write-Host "✅ S3 Bucket exists and accessible: $S3Bucket" -ForegroundColor Green
    } else {
        Write-Host "❌ S3 Bucket not accessible or not found" -ForegroundColor Red
        if (-not $S3Bucket) {
            Write-Host "   Could not get bucket name from Terraform output" -ForegroundColor Yellow
        }
    }

    # Check DynamoDB table
    $TableStatus = aws dynamodb describe-table --table-name "${ProjectName}-results" --region $AWSRegion --query 'Table.TableStatus' --output text 2>$null
    if ($TableStatus -eq "ACTIVE") {
        Write-Host "✅ DynamoDB Table is ACTIVE" -ForegroundColor Green
    } else {
        Write-Host "❌ DynamoDB Table status: $TableStatus" -ForegroundColor Red
    }

    # Check ECR repository
    $EcrRepo = aws ecr describe-repositories --repository-names "${ProjectName}/document-processor" --region $AWSRegion --query 'repositories[0].repositoryName' --output text 2>$null
    if ($EcrRepo) {
        Write-Host "✅ ECR Repository exists" -ForegroundColor Green
    } else {
        Write-Host "❌ ECR Repository not found" -ForegroundColor Red
    }

} catch {
    Write-Host "Error checking AWS resources: $_" -ForegroundColor Red
}

# Test 2: Check Kubernetes deployment
Write-Host "`n=== Step 2: Verifying Kubernetes Deployment ===" -ForegroundColor Yellow

try {
    # Update kubeconfig
    aws eks update-kubeconfig --region $AWSRegion --name "${ProjectName}-cluster"

    # Check for kubectl authentication issues and fix them
    Write-Host "Checking kubectl authentication..." -ForegroundColor Green
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
                Write-Host "❌ kubectl authentication still failing, trying alternative method..." -ForegroundColor Yellow
                # Restore backup and try recreating config
                Copy-Item "$KubeconfigFile.backup" $KubeconfigFile -Force
                aws eks update-kubeconfig --region $AWSRegion --name "${ProjectName}-cluster" --alias "${ProjectName}-cluster" 2>$null
            }
        }
    }

    # Check pods
    $Pods = kubectl get pods -l app=document-processor -o jsonpath='{.items[*].status.phase}' 2>$null
    $RunningPods = ($Pods -split ' ' | Where-Object { $_ -eq 'Running' }).Count
    
    if ($RunningPods -gt 0) {
        Write-Host "✅ $RunningPods pod(s) running" -ForegroundColor Green
    } else {
        Write-Host "❌ No running pods found" -ForegroundColor Red
        kubectl get pods -l app=document-processor
    }

    # Check service
    $ServiceIP = kubectl get service document-processor-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    if ($ServiceIP) {
        Write-Host "✅ Service has external IP: $ServiceIP" -ForegroundColor Green
    } else {
        Write-Host "⏳ Service external IP pending..." -ForegroundColor Yellow
    }

    # Check ingress
    $IngressIP = kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    if ($IngressIP) {
        Write-Host "✅ Ingress has hostname: $IngressIP" -ForegroundColor Green
        $global:ServiceEndpoint = "http://$IngressIP"
    } else {
        Write-Host "⏳ Ingress hostname pending..." -ForegroundColor Yellow
    }

} catch {
    Write-Host "Error checking Kubernetes resources: $_" -ForegroundColor Red
}

# Test 3: Health check
Write-Host "`n=== Step 3: Application Health Check ===" -ForegroundColor Yellow

if ($global:ServiceEndpoint) {
    try {
        Write-Host "Testing health endpoint: $global:ServiceEndpoint/health" -ForegroundColor Cyan
        $Response = Invoke-RestMethod -Uri "$global:ServiceEndpoint/health" -Method GET -TimeoutSec 30
        
        if ($Response) {
            Write-Host "✅ Health check passed!" -ForegroundColor Green
            Write-Host "Response: $($Response | ConvertTo-Json)" -ForegroundColor White
        }
    } catch {
        Write-Host "❌ Health check failed: $_" -ForegroundColor Red
        Write-Host "This might be normal if the service is still starting up" -ForegroundColor Yellow
    }
} else {
    Write-Host "⏳ Waiting for service endpoint to be available..." -ForegroundColor Yellow
}

Write-Host "`n=== Deployment Test Summary ===" -ForegroundColor Cyan
Write-Host "Check the above results for any issues." -ForegroundColor White
Write-Host "If services are pending, wait a few minutes and run this script again." -ForegroundColor Yellow

if ($global:ServiceEndpoint) {
    Write-Host "`nService Endpoint: $global:ServiceEndpoint" -ForegroundColor Green
    Write-Host "You can now test the API endpoints!" -ForegroundColor Green
}
