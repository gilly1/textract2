# Test script for document processing workflow
# This script simulates the workflow:
# 1. Upload file to S3
# 2. Insert record in DynamoDB  
# 3. Lambda triggers automatically
# 4. Check processing status

param(
    [string]$TestFile = "invoice.pdf"
)

# Configuration
$AWS_REGION = "us-east-1"
$ErrorActionPreference = "Stop"

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

function Get-TerraformOutput {
    param([string]$OutputName)
    
    Push-Location infra
    try {
        $output = terraform output -raw $OutputName 2>$null
        return $output
    }
    finally {
        Pop-Location
    }
}

# Initialize
Write-Log "Starting document processing workflow test..."

# Get infrastructure details
Write-Log "Getting infrastructure details from Terraform..."
$BUCKET_NAME = Get-TerraformOutput "s3_bucket_name"
$DYNAMODB_TABLE = Get-TerraformOutput "dynamodb_table_name"
$ALB_URL = Get-TerraformOutput "load_balancer_url"

if (-not $BUCKET_NAME -or -not $DYNAMODB_TABLE -or -not $ALB_URL) {
    Write-Error-Log "Failed to get infrastructure details. Make sure Terraform has been applied."
}

Write-Log "Using S3 bucket: $BUCKET_NAME"
Write-Log "Using DynamoDB table: $DYNAMODB_TABLE"
Write-Log "Using ALB URL: $ALB_URL"

# Check if test file exists
if (-not (Test-Path $TestFile)) {
    Write-Error-Log "Test file '$TestFile' not found. Please provide a valid file path."
}

# Generate unique document ID
$DOCUMENT_ID = "test-doc-$(Get-Date -UFormat '%s')"
$S3_KEY = "documents/$DOCUMENT_ID/$(Split-Path $TestFile -Leaf)"

Write-Log "Generated document ID: $DOCUMENT_ID"

# Step 1: Upload file to S3
Write-Log "Step 1: Uploading file to S3..."
try {
    aws s3 cp $TestFile "s3://$BUCKET_NAME/$S3_KEY" --region $AWS_REGION
    Write-Log "File uploaded successfully to s3://$BUCKET_NAME/$S3_KEY"
}
catch {
    Write-Error-Log "Failed to upload file to S3: $_"
}

# Step 2: Insert record in DynamoDB
Write-Log "Step 2: Inserting record in DynamoDB..."
$FILE_EXT = [System.IO.Path]::GetExtension($TestFile).ToLower().TrimStart('.')
$FILE_TYPE = switch ($FILE_EXT) {
    "pdf" { "pdf" }
    { $_ -in @("jpg", "jpeg", "png", "bmp", "tiff") } { "image" }
    default { "unknown" }
}

$UPLOAD_DATE = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$DynamoDBItem = @{
    id = @{ S = $DOCUMENT_ID }
    bucket = @{ S = $BUCKET_NAME }
    key = @{ S = $S3_KEY }
    status = @{ S = "pending" }
    file_type = @{ S = $FILE_TYPE }
    upload_date = @{ S = $UPLOAD_DATE }
} | ConvertTo-Json -Depth 3

try {
    aws dynamodb put-item --region $AWS_REGION --table-name $DYNAMODB_TABLE --item $DynamoDBItem
    Write-Log "DynamoDB record inserted successfully"
}
catch {
    Write-Error-Log "Failed to insert record in DynamoDB: $_"
}

# Step 3: Wait for Lambda to trigger and processing to start
Write-Log "Step 3: Waiting for Lambda to trigger processing..."
Write-Log "Lambda should automatically trigger and call the /process endpoint"
Start-Sleep -Seconds 5

# Step 4: Check processing status
Write-Log "Step 4: Checking processing status..."
for ($i = 1; $i -le 12; $i++) {
    Write-Log "Checking status (attempt $i/12)..."
    
    try {
        $KeyJson = @{ id = @{ S = $DOCUMENT_ID } } | ConvertTo-Json -Depth 2
        $RESPONSE = aws dynamodb get-item --region $AWS_REGION --table-name $DYNAMODB_TABLE --key $KeyJson --output json | ConvertFrom-Json
        
        $STATUS = $RESPONSE.Item.status.S
        $CURRENT_STEP = $RESPONSE.Item.current_step.S
        
        Write-Log "Current status: $STATUS"
        if ($CURRENT_STEP) {
            Write-Log "Current step: $CURRENT_STEP"
        }
        
        switch ($STATUS) {
            "completed" {
                Write-Log "✅ Processing completed successfully!"
                
                $VALIDATION_SCORE = $RESPONSE.Item.validation_score.N
                Write-Log "Validation score: $VALIDATION_SCORE"
                
                $PROCESSED_DATE = $RESPONSE.Item.processed_date.S
                Write-Log "Processed date: $PROCESSED_DATE"
                
                $QR_COUNT = if ($RESPONSE.Item.qr_codes.L) { $RESPONSE.Item.qr_codes.L.Count } else { 0 }
                Write-Log "QR codes found: $QR_COUNT"
                
                Write-Log "✅ Test completed successfully!"
                break
            }
            "failed" {
                Write-Warning-Log "❌ Processing failed"
                $ERROR_MSG = if ($RESPONSE.Item.error.S) { $RESPONSE.Item.error.S } else { "No error message" }
                Write-Warning-Log "Error: $ERROR_MSG"
                break
            }
            "processing" {
                Write-Log "🔄 Still processing..."
            }
            "pending" {
                if ($i -le 3) {
                    Write-Log "⏳ Still pending (Lambda may be starting up)..."
                } else {
                    Write-Warning-Log "⚠️  Still pending after $($i*10) seconds. Lambda may not have triggered."
                }
            }
            default {
                Write-Warning-Log "Unknown status: $STATUS"
            }
        }
    }
    catch {
        Write-Warning-Log "Failed to get status from DynamoDB: $_"
    }
    
    if ($i -lt 12) {
        Start-Sleep -Seconds 10
    }
}

# Step 5: Test API endpoint directly
Write-Log "Step 5: Testing API health endpoint..."
try {
    $HEALTH_RESPONSE = Invoke-RestMethod -Uri "$ALB_URL/health" -Method Get -TimeoutSec 10
    Write-Log "✅ API health check passed"
    Write-Log "Health response: $($HEALTH_RESPONSE | ConvertTo-Json)"
}
catch {
    Write-Warning-Log "❌ API health check failed: $_"
}

# Summary
Write-Log "Test Summary:"
Write-Log "- Document ID: $DOCUMENT_ID"
Write-Log "- S3 Location: s3://$BUCKET_NAME/$S3_KEY"
Write-Log "- DynamoDB Table: $DYNAMODB_TABLE"
Write-Log "- ALB URL: $ALB_URL"
Write-Log ""
Write-Log "You can check the processing result using:"
Write-Log "Invoke-RestMethod -Uri '$ALB_URL/status/$DOCUMENT_ID'"
Write-Log ""
Write-Log "Check Lambda logs with:"
Write-Log "aws logs tail /aws/lambda/document-processor-dynamodb-trigger --follow"
