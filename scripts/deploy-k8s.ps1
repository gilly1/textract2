# Deploy to EKS
param(
    [string]$ImageTag = "latest",
    [string]$AWSRegion = "us-east-1"
)

# Configuration
$ProjectName = "docproc-714499"

Write-Host "Deploying Document Processor to EKS..." -ForegroundColor Green

# Get cluster name from Terraform output
try {
    Push-Location terraform
    $ClusterName = terraform output -raw cluster_name
    if ($LASTEXITCODE -ne 0) {
        $ClusterName = "$ProjectName-cluster"
    }
    Pop-Location
} catch {
    $ClusterName = "$ProjectName-cluster"
}

$AccountId = aws sts get-caller-identity --query Account --output text
$EcrRepo = "$AccountId.dkr.ecr.$AWSRegion.amazonaws.com/$ProjectName/document-processor"

Write-Host "Cluster: $ClusterName" -ForegroundColor Yellow
Write-Host "Image: ${EcrRepo}:$ImageTag" -ForegroundColor Yellow

# Update kubeconfig
Write-Host "Updating kubeconfig..." -ForegroundColor Green
aws eks update-kubeconfig --region $AWSRegion --name $ClusterName

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to update kubeconfig" -ForegroundColor Red
    exit 1
}

# Check cluster connectivity
Write-Host "Checking cluster connectivity..." -ForegroundColor Green
kubectl cluster-info

# Get IAM role ARN for service account
try {
    Push-Location terraform
    $RoleArn = terraform output -raw document_processor_role_arn
    Pop-Location
} catch {
    $RoleArn = "arn:aws:iam::${AccountId}:role/DocumentProcessorRole"
}

# Update RBAC with correct role ARN
Write-Host "Updating RBAC configuration..." -ForegroundColor Green
(Get-Content k8s\rbac.yaml) -replace 'ACCOUNT_ID', $AccountId | kubectl apply -f -

# Update deployment with correct image
Write-Host "Updating deployment with latest image..." -ForegroundColor Green
(Get-Content k8s\deployment.yaml) -replace 'image: document-processor:latest', "image: ${EcrRepo}:$ImageTag" | kubectl apply -f -

# Apply HPA
Write-Host "Applying Horizontal Pod Autoscaler..." -ForegroundColor Green
kubectl apply -f k8s\hpa.yaml

# Wait for deployment to be ready
Write-Host "Waiting for deployment to be ready..." -ForegroundColor Green
kubectl rollout status deployment/document-processor --timeout=300s

if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Deployment may not be fully ready" -ForegroundColor Yellow
}

# Get service information
Write-Host "Getting service information..." -ForegroundColor Green
kubectl get services document-processor-service
kubectl get ingress document-processor-ingress

# Check pod status
Write-Host "Pod status:" -ForegroundColor Green
kubectl get pods -l app=document-processor

Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green

# Show how to get the external URL
Write-Host "To get the external URL, wait a few minutes and run:" -ForegroundColor Yellow
Write-Host "kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"

Write-Host "To check logs:" -ForegroundColor Yellow
Write-Host "kubectl logs -l app=document-processor -f"
