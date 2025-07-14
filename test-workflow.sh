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

# Generate unique document ID and user
DOCUMENT_ID="test-doc-$(date +%s)"
USER_ID="test-user"
S3_KEY="documents/$DOCUMENT_ID/$(basename "$TEST_FILE")"

log "Generated document ID: $DOCUMENT_ID"
log "Using user ID: $USER_ID"

# Step 1: Upload file to S3
log "Step 1: Uploading file to S3..."
aws s3 cp "$TEST_FILE" "s3://$BUCKET_NAME/$S3_KEY" --region $AWS_REGION
if [[ $? -eq 0 ]]; then
    log "File uploaded successfully to s3://$BUCKET_NAME/$S3_KEY"
else
    error "Failed to upload file to S3"
fi

# Step 2: Insert record in DynamoDB using new schema
log "Step 2: Inserting record in DynamoDB..."
FILE_EXT="${TEST_FILE##*.}"
FILE_TYPE=""
case $FILE_EXT in
    pdf) FILE_TYPE="application/pdf" ;;
    jpg|jpeg) FILE_TYPE="image/jpeg" ;;
    png) FILE_TYPE="image/png" ;;
    bmp) FILE_TYPE="image/bmp" ;;
    tiff) FILE_TYPE="image/tiff" ;;
    *) FILE_TYPE="application/octet-stream" ;;
esac

# Get file size
FILE_SIZE=$(stat -f%z "$TEST_FILE" 2>/dev/null || stat -c%s "$TEST_FILE" 2>/dev/null || echo "0")

aws dynamodb put-item \
    --region $AWS_REGION \
    --table-name "$DYNAMODB_TABLE" \
    --item "{
        \"fileId\": {\"S\": \"$DOCUMENT_ID\"},
        \"uploadedBy\": {\"S\": \"$USER_ID\"},
        \"fileName\": {\"S\": \"$(basename "$TEST_FILE")\"},
        \"fileType\": {\"S\": \"$FILE_TYPE\"},
        \"fileSize\": {\"N\": \"$FILE_SIZE\"},
        \"s3Key\": {\"S\": \"$S3_KEY\"},
        \"s3Url\": {\"S\": \"https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/$S3_KEY\"},
        \"uploadDate\": {\"S\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"},
        \"status\": {\"S\": \"pending\"},
        \"metadata\": {\"M\": {
            \"testRun\": {\"S\": \"true\"},
            \"source\": {\"S\": \"test-workflow.sh\"}
        }},
        \"last_updated\": {\"S\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}
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
    
    # Get status from DynamoDB using new composite key
    STATUS=$(aws dynamodb get-item \
        --region $AWS_REGION \
        --table-name "$DYNAMODB_TABLE" \
        --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}" \
        --query 'Item.status.S' \
        --output text 2>/dev/null)
    
    CURRENT_STEP=$(aws dynamodb get-item \
        --region $AWS_REGION \
        --table-name "$DYNAMODB_TABLE" \
        --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}" \
        --query 'Item.current_step.S' \
        --output text 2>/dev/null)
    
    if [[ $? -eq 0 && "$STATUS" != "None" ]]; then
        log "Current status: $STATUS"
        if [[ "$CURRENT_STEP" != "None" && "$CURRENT_STEP" != "" ]]; then
            log "Current step: $CURRENT_STEP"
        fi
        
        case $STATUS in
            "completed")
                log "✅ Processing completed successfully!"
                
                # Show results
                VALIDATION_SCORE=$(aws dynamodb get-item \
                    --region $AWS_REGION \
                    --table-name "$DYNAMODB_TABLE" \
                    --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}" \
                    --query 'Item.validation_score.N' \
                    --output text 2>/dev/null)
                
                if [[ "$VALIDATION_SCORE" != "None" ]]; then
                    log "Validation score: $VALIDATION_SCORE"
                fi
                
                # Get processed date
                PROCESSED_DATE=$(aws dynamodb get-item \
                    --region $AWS_REGION \
                    --table-name "$DYNAMODB_TABLE" \
                    --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}" \
                    --query 'Item.processed_date.S' \
                    --output text 2>/dev/null)
                
                if [[ "$PROCESSED_DATE" != "None" ]]; then
                    log "Processed date: $PROCESSED_DATE"
                fi
                
                # Check if there are QR codes
                QR_CODES_RESPONSE=$(aws dynamodb get-item \
                    --region $AWS_REGION \
                    --table-name "$DYNAMODB_TABLE" \
                    --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}" \
                    --query 'Item.qr_codes.L' \
                    --output text 2>/dev/null)
                
                if [[ "$QR_CODES_RESPONSE" != "None" && "$QR_CODES_RESPONSE" != "" ]]; then
                    log "QR codes found in document"
                else
                    log "No QR codes found"
                fi
                
                # Check invoice fields
                INVOICE_NUMBER=$(aws dynamodb get-item \
                    --region $AWS_REGION \
                    --table-name "$DYNAMODB_TABLE" \
                    --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}" \
                    --query 'Item.invoice_fields.M."Invoice Number".S' \
                    --output text 2>/dev/null)
                
                if [[ "$INVOICE_NUMBER" != "None" && "$INVOICE_NUMBER" != "" ]]; then
                    log "Invoice Number: $INVOICE_NUMBER"
                fi
                
                log "✅ Test completed successfully!"
                break
                ;;
            "failed")
                warn "❌ Processing failed"
                ERROR_MSG=$(aws dynamodb get-item \
                    --region $AWS_REGION \
                    --table-name "$DYNAMODB_TABLE" \
                    --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}" \
                    --query 'Item.error.S' \
                    --output text 2>/dev/null)
                
                if [[ "$ERROR_MSG" != "None" && "$ERROR_MSG" != "" ]]; then
                    warn "Error: $ERROR_MSG"
                else
                    warn "No error message available"
                fi
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
log "- File ID: $DOCUMENT_ID"
log "- User ID: $USER_ID"
log "- S3 Location: s3://$BUCKET_NAME/$S3_KEY"
log "- DynamoDB Table: $DYNAMODB_TABLE"
log "- ALB URL: $ALB_URL"
log ""
log "You can check the processing result using:"
log "curl $ALB_URL/status/$DOCUMENT_ID/$USER_ID"
log ""
log "Or using the API:"
log "curl $ALB_URL/files/$USER_ID"
log ""
log "Check Lambda logs with:"
log "aws logs tail /aws/lambda/document-processor-dynamodb-trigger --follow"
