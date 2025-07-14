# API Testing Script
param(
    [string]$ServiceEndpoint = "",
    [string]$TestFile = ""
)

if (-not $ServiceEndpoint) {
    Write-Host "Getting service endpoint..." -ForegroundColor Yellow
    $IngressIP = kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    if ($IngressIP) {
        $ServiceEndpoint = "http://$IngressIP"
    } else {
        Write-Host "❌ Could not get service endpoint. Please provide it manually:" -ForegroundColor Red
        Write-Host "Usage: .\test-api.ps1 -ServiceEndpoint 'http://your-endpoint'" -ForegroundColor Yellow
        exit 1
    }
}

# Default to invoice.pdf if no test file provided
if (-not $TestFile) {
    $PossiblePaths = @("invoice.pdf", "samples\invoice.pdf", "..\invoice.pdf")
    foreach ($Path in $PossiblePaths) {
        if (Test-Path $Path) {
            $TestFile = $Path
            Write-Host "Using default test file: $TestFile" -ForegroundColor Cyan
            break
        }
    }
}

Write-Host "Testing API at: $ServiceEndpoint" -ForegroundColor Cyan

# Test 1: Health Check
Write-Host "`n=== Test 1: Health Check ===" -ForegroundColor Yellow
try {
    $Health = Invoke-RestMethod -Uri "$ServiceEndpoint/health" -Method GET
    Write-Host "✅ Health Check: $($Health | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "❌ Health Check Failed: $_" -ForegroundColor Red
}

# Test 2: Root endpoint
Write-Host "`n=== Test 2: Root Endpoint ===" -ForegroundColor Yellow
try {
    $Root = Invoke-RestMethod -Uri "$ServiceEndpoint/" -Method GET
    Write-Host "✅ Root Endpoint: $($Root | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "❌ Root Endpoint Failed: $_" -ForegroundColor Red
}

# Test 3: Document Upload (if test file provided)
if ($TestFile -and (Test-Path $TestFile)) {
    Write-Host "`n=== Test 3: Document Upload ===" -ForegroundColor Yellow
    try {
        # Create multipart form
        $boundary = [System.Guid]::NewGuid().ToString()
        $fileBytes = [System.IO.File]::ReadAllBytes($TestFile)
        $fileName = [System.IO.Path]::GetFileName($TestFile)
        
        $bodyLines = @(
            "--$boundary",
            "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"",
            "Content-Type: application/octet-stream",
            "",
            [System.Text.Encoding]::Default.GetString($fileBytes),
            "--$boundary--"
        )
        $body = $bodyLines -join "`r`n"
        
        $headers = @{
            "Content-Type" = "multipart/form-data; boundary=$boundary"
        }
        
        Write-Host "Uploading file: $fileName" -ForegroundColor Cyan
        $Response = Invoke-RestMethod -Uri "$ServiceEndpoint/process" -Method POST -Body $body -Headers $headers -TimeoutSec 120
        
        Write-Host "✅ Upload successful!" -ForegroundColor Green
        Write-Host "Processing ID: $($Response.processing_id)" -ForegroundColor White
        
        # Check status
        if ($Response.processing_id) {
            Start-Sleep -Seconds 2
            Write-Host "Checking processing status..." -ForegroundColor Cyan
            $Status = Invoke-RestMethod -Uri "$ServiceEndpoint/status/$($Response.processing_id)" -Method GET
            Write-Host "Status: $($Status | ConvertTo-Json -Depth 3)" -ForegroundColor White
        }
        
    } catch {
        Write-Host "❌ Document Upload Failed: $_" -ForegroundColor Red
    }
} else {
    Write-Host "`n=== Test 3: Document Upload ===" -ForegroundColor Yellow
    Write-Host "⏭️  Skipped - No test file found" -ForegroundColor Yellow
    Write-Host "To test file upload with invoice.pdf, make sure invoice.pdf exists in:" -ForegroundColor Cyan
    Write-Host "  - Current directory" -ForegroundColor Cyan
    Write-Host "  - samples\ directory" -ForegroundColor Cyan
    Write-Host "  - Parent directory" -ForegroundColor Cyan
    Write-Host "Or run: .\test-api.ps1 -ServiceEndpoint '$ServiceEndpoint' -TestFile 'path\to\invoice.pdf'" -ForegroundColor Cyan
}

# Test 4: List recent results
Write-Host "`n=== Test 4: List Results ===" -ForegroundColor Yellow
try {
    $Results = Invoke-RestMethod -Uri "$ServiceEndpoint/results" -Method GET
    Write-Host "✅ Results retrieved: $($Results.results.Count) items" -ForegroundColor Green
    if ($Results.results.Count -gt 0) {
        Write-Host "Latest result: $($Results.results[0] | ConvertTo-Json -Depth 2)" -ForegroundColor White
    }
} catch {
    Write-Host "❌ List Results Failed: $_" -ForegroundColor Red
}

Write-Host "`n=== API Testing Complete ===" -ForegroundColor Cyan
Write-Host "Service Endpoint: $ServiceEndpoint" -ForegroundColor Green
