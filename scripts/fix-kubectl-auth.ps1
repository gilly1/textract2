# Fix kubectl authentication issue with EKS
param(
    [string]$AWSRegion = "us-east-1"
)

$ProjectName = "dp714"

Write-Host "Fixing kubectl authentication for EKS cluster..." -ForegroundColor Cyan

# Update kubeconfig
Write-Host "Updating kubeconfig..." -ForegroundColor Yellow
aws eks update-kubeconfig --region $AWSRegion --name "${ProjectName}-cluster"

# Check current authentication
Write-Host "Testing current authentication..." -ForegroundColor Yellow
$TestResult = kubectl cluster-info 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ kubectl authentication is working" -ForegroundColor Green
    exit 0
}

Write-Host "Authentication issue detected, applying fix..." -ForegroundColor Yellow

# Fix the authentication version issue
$KubeconfigFile = "$env:USERPROFILE\.kube\config"
if (Test-Path $KubeconfigFile) {
    Write-Host "Backing up kubeconfig..." -ForegroundColor Yellow
    $BackupFile = "$KubeconfigFile.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $KubeconfigFile $BackupFile -Force
    
    Write-Host "Updating authentication API version..." -ForegroundColor Yellow
    # Replace v1alpha1 with v1beta1
    $Content = Get-Content $KubeconfigFile -Raw
    $UpdatedContent = $Content -replace 'client\.authentication\.k8s\.io/v1alpha1', 'client.authentication.k8s.io/v1beta1'
    $UpdatedContent | Set-Content $KubeconfigFile
    
    # Test the fix
    Write-Host "Testing fixed authentication..." -ForegroundColor Yellow
    $TestResult = kubectl cluster-info 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ kubectl authentication fixed successfully!" -ForegroundColor Green
        Write-Host "Cluster info:" -ForegroundColor Green
        kubectl cluster-info
    } else {
        Write-Host "❌ Fix unsuccessful. Trying alternative approach..." -ForegroundColor Red
        
        # Try updating versions
        Write-Host "The issue might be due to version incompatibility." -ForegroundColor Yellow
        Write-Host "Consider updating:" -ForegroundColor Yellow
        Write-Host "  - AWS CLI: pip install --upgrade awscli" -ForegroundColor Cyan
        Write-Host "  - kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/" -ForegroundColor Cyan
        
        # Restore backup
        Write-Host "Restoring original kubeconfig..." -ForegroundColor Yellow
        Copy-Item $BackupFile $KubeconfigFile -Force
        
        exit 1
    }
} else {
    Write-Host "❌ Kubeconfig file not found at $KubeconfigFile" -ForegroundColor Red
    Write-Host "Run: aws eks update-kubeconfig --region $AWSRegion --name ${ProjectName}-cluster" -ForegroundColor Cyan
    exit 1
}

Write-Host ""
Write-Host "You can now run kubectl commands:" -ForegroundColor Green
Write-Host "  kubectl get pods" -ForegroundColor Cyan
Write-Host "  kubectl get services" -ForegroundColor Cyan
Write-Host "  kubectl get ingress" -ForegroundColor Cyan
