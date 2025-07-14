# Simple Load Test Script
param(
    [string]$ServiceEndpoint,
    [int]$Requests = 10,
    [int]$Concurrent = 3
)

if (-not $ServiceEndpoint) {
    $IngressIP = kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    $ServiceEndpoint = "http://$IngressIP"
}

Write-Host "Running load test against: $ServiceEndpoint" -ForegroundColor Cyan
Write-Host "Requests: $Requests, Concurrent: $Concurrent" -ForegroundColor Yellow

$jobs = @()
$results = @()

# Function to make request
$scriptBlock = {
    param($endpoint, $requestId)
    try {
        $start = Get-Date
        $response = Invoke-RestMethod -Uri "$endpoint/health" -Method GET -TimeoutSec 10
        $end = Get-Date
        $duration = ($end - $start).TotalMilliseconds
        
        return @{
            RequestId = $requestId
            Success = $true
            Duration = $duration
            Response = $response
        }
    } catch {
        return @{
            RequestId = $requestId
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

Write-Host "Starting load test..." -ForegroundColor Green

# Start concurrent requests
for ($i = 1; $i -le $Requests; $i++) {
    # Limit concurrent jobs
    while ((Get-Job -State Running).Count -ge $Concurrent) {
        Start-Sleep -Milliseconds 100
    }
    
    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $ServiceEndpoint, $i
    $jobs += $job
    Write-Host "Started request $i" -ForegroundColor Gray
}

# Wait for all jobs to complete
Write-Host "Waiting for all requests to complete..." -ForegroundColor Yellow
$jobs | Wait-Job | Out-Null

# Collect results
foreach ($job in $jobs) {
    $result = Receive-Job -Job $job
    $results += $result
    Remove-Job -Job $job
}

# Analyze results
$successful = $results | Where-Object { $_.Success -eq $true }
$failed = $results | Where-Object { $_.Success -eq $false }

Write-Host "`n=== Load Test Results ===" -ForegroundColor Cyan
Write-Host "Total Requests: $Requests" -ForegroundColor White
Write-Host "Successful: $($successful.Count)" -ForegroundColor Green
Write-Host "Failed: $($failed.Count)" -ForegroundColor Red

if ($successful.Count -gt 0) {
    $avgDuration = ($successful | Measure-Object -Property Duration -Average).Average
    $minDuration = ($successful | Measure-Object -Property Duration -Minimum).Minimum
    $maxDuration = ($successful | Measure-Object -Property Duration -Maximum).Maximum
    
    Write-Host "Average Response Time: $([math]::Round($avgDuration, 2))ms" -ForegroundColor White
    Write-Host "Min Response Time: $([math]::Round($minDuration, 2))ms" -ForegroundColor White
    Write-Host "Max Response Time: $([math]::Round($maxDuration, 2))ms" -ForegroundColor White
}

if ($failed.Count -gt 0) {
    Write-Host "`nErrors:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  Request $($_.RequestId): $($_.Error)" -ForegroundColor Red }
}
