#!/bin/bash

# Test script for document processing workflow
# This script simulates the workflow:
# 1. Upload file to S3
# 2. Insert record in DynamoDB
# 3. Lambda triggers automatically
# 4. Check processing status

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="us-east-1"
BUCKET_NAME=""
DYNAMODB_TABLE=""
TEST_FILE="${1:-invoice.pdf}"  # Default to invoice.pdf

# Function to get Terraform outputs
get_terraform_output() {
    cd infra
    terraform output -raw $1 2>/dev/null
    cd ..
}

# Function to log with timestamp
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Initialize
log "Starting document processing workflow test..."

# Get infrastructure details
log "Getting infrastructure details from Terraform..."
BUCKET_NAME=$(get_terraform_output "s3_bucket_name")
DYNAMODB_TABLE=$(get_terraform_output "dynamodb_table_name")
ALB_URL=$(get_terraform_output "load_balancer_url")

if [[ -z "$BUCKET_NAME" || -z "$DYNAMODB_TABLE" || -z "$ALB_URL" ]]; then
    error "Failed to get infrastructure details. Make sure Terraform has been applied."
fi

log "Using S3 bucket: $BUCKET_NAME"
log "Using DynamoDB table: $DYNAMODB_TABLE"
log "Using ALB URL: $ALB_URL"

# Check if test file exists
if [[ ! -f "$TEST_FILE" ]]; then
    error "Test file '$TEST_FILE' not found. Please provide a valid file path."
fi

# Generate unique document ID
DOCUMENT_ID="test-doc-$(date +%s)"
S3_KEY="documents/$DOCUMENT_ID/$(basename "$TEST_FILE")"

log "Generated document ID: $DOCUMENT_ID"

# Step 1: Upload file to S3
log "Step 1: Uploading file to S3..."
aws s3 cp "$TEST_FILE" "s3://$BUCKET_NAME/$S3_KEY" --region $AWS_REGION
if [[ $? -eq 0 ]]; then
    log "File uploaded successfully to s3://$BUCKET_NAME/$S3_KEY"
else
    error "Failed to upload file to S3"
fi

# Step 2: Insert record in DynamoDB
log "Step 2: Inserting record in DynamoDB..."
FILE_EXT="${TEST_FILE##*.}"
FILE_TYPE=""
case $FILE_EXT in
    pdf) FILE_TYPE="pdf" ;;
    jpg|jpeg|png|bmp|tiff) FILE_TYPE="image" ;;
    *) FILE_TYPE="unknown" ;;
esac

aws dynamodb put-item \
    --region $AWS_REGION \
    --table-name "$DYNAMODB_TABLE" \
    --item "{
        \"id\": {\"S\": \"$DOCUMENT_ID\"},
        \"bucket\": {\"S\": \"$BUCKET_NAME\"},
        \"key\": {\"S\": \"$S3_KEY\"},
        \"status\": {\"S\": \"pending\"},
        \"file_type\": {\"S\": \"$FILE_TYPE\"},
        \"upload_date\": {\"S\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}
    }"

if [[ $? -eq 0 ]]; then
    log "DynamoDB record inserted successfully"
else
    error "Failed to insert record in DynamoDB"
fi

# Step 3: Wait for Lambda to trigger and processing to start
log "Step 3: Waiting for Lambda to trigger processing..."
log "Lambda should automatically trigger and call the /process endpoint"

sleep 5

# Step 4: Check processing status
log "Step 4: Checking processing status..."
for i in {1..12}; do
    log "Checking status (attempt $i/12)..."
    
    # Get status from DynamoDB
    RESPONSE=$(aws dynamodb get-item \
        --region $AWS_REGION \
        --table-name "$DYNAMODB_TABLE" \
        --key "{\"id\": {\"S\": \"$DOCUMENT_ID\"}}" \
        --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        STATUS=$(echo "$RESPONSE" | jq -r '.Item.status.S // "unknown"')
        CURRENT_STEP=$(echo "$RESPONSE" | jq -r '.Item.current_step.S // "not set"')
        
        log "Current status: $STATUS"
        if [[ "$CURRENT_STEP" != "not set" ]]; then
            log "Current step: $CURRENT_STEP"
        fi
        
        case $STATUS in
            "completed")
                log "✅ Processing completed successfully!"
                
                # Show results
                VALIDATION_SCORE=$(echo "$RESPONSE" | jq -r '.Item.validation_score.N // "unknown"')
                log "Validation score: $VALIDATION_SCORE"
                
                # Get processed date
                PROCESSED_DATE=$(echo "$RESPONSE" | jq -r '.Item.processed_date.S // "unknown"')
                log "Processed date: $PROCESSED_DATE"
                
                # Check if there are QR codes
                QR_COUNT=$(echo "$RESPONSE" | jq -r '.Item.qr_codes.L | length // 0')
                log "QR codes found: $QR_COUNT"
                
                log "✅ Test completed successfully!"
                break
                ;;
            "failed")
                warn "❌ Processing failed"
                ERROR_MSG=$(echo "$RESPONSE" | jq -r '.Item.error.S // "No error message"')
                warn "Error: $ERROR_MSG"
                break
                ;;
            "processing")
                log "🔄 Still processing..."
                ;;
            "pending")
                if [[ $i -le 3 ]]; then
                    log "⏳ Still pending (Lambda may be starting up)..."
                else
                    warn "⚠️  Still pending after $((i*10)) seconds. Lambda may not have triggered."
                fi
                ;;
            *)
                warn "Unknown status: $STATUS"
                ;;
        esac
    else
        warn "Failed to get status from DynamoDB"
    fi
    
    if [[ $i -lt 12 ]]; then
        sleep 10
    fi
done

# Step 5: Test API endpoint directly
log "Step 5: Testing API health endpoint..."
HEALTH_RESPONSE=$(curl -s "$ALB_URL/health" -w "HTTP_STATUS:%{http_code}")
HTTP_STATUS=$(echo "$HEALTH_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)

if [[ "$HTTP_STATUS" == "200" ]]; then
    log "✅ API health check passed"
    HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')
    log "Health response: $HEALTH_BODY"
else
    warn "❌ API health check failed (HTTP $HTTP_STATUS)"
fi

# Summary
log "Test Summary:"
log "- Document ID: $DOCUMENT_ID"
log "- S3 Location: s3://$BUCKET_NAME/$S3_KEY"
log "- DynamoDB Table: $DYNAMODB_TABLE"
log "- ALB URL: $ALB_URL"
log ""
log "You can check the processing result using:"
log "curl $ALB_URL/status/$DOCUMENT_ID"
log ""
log "Check Lambda logs with:"
log "aws logs tail /aws/lambda/document-processor-dynamodb-trigger --follow"
