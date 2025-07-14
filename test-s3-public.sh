#!/bin/bash

# Script to test S3 public access
echo "🧪 Testing S3 bucket public access..."

cd infra
BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null)
cd ..

if [ -z "$BUCKET_NAME" ]; then
    echo "❌ Could not get bucket name from Terraform"
    exit 1
fi

AWS_REGION="us-east-1"
echo "📁 Bucket: $BUCKET_NAME"
echo "🌍 Region: $AWS_REGION"
echo ""

# Check if there are any existing files to test with
echo "🔍 Looking for existing files in bucket..."
SAMPLE_FILES=$(aws s3 ls s3://$BUCKET_NAME/documents/ --recursive | head -5)

if [ -z "$SAMPLE_FILES" ]; then
    echo "📝 No files found. Upload a file first using:"
    echo "   ./test-workflow.sh invoice.pdf"
    echo ""
    echo "🔗 After upload, files will be accessible at:"
    echo "   https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/documents/[document-id]/[filename]"
else
    echo "📋 Found files:"
    echo "$SAMPLE_FILES"
    echo ""
    
    # Test the first file
    FIRST_FILE=$(echo "$SAMPLE_FILES" | head -1 | awk '{print $4}')
    if [ ! -z "$FIRST_FILE" ]; then
        PUBLIC_URL="https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/$FIRST_FILE"
        echo "🌐 Testing public access for: $FIRST_FILE"
        echo "🔗 URL: $PUBLIC_URL"
        echo ""
        
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$PUBLIC_URL")
        
        if [ "$HTTP_STATUS" = "200" ]; then
            echo "✅ Public access working! File is accessible."
        elif [ "$HTTP_STATUS" = "403" ]; then
            echo "❌ Access denied. Bucket may not be public yet."
        elif [ "$HTTP_STATUS" = "404" ]; then
            echo "⚠️  File not found (may have been moved/deleted)."
        else
            echo "❓ Unexpected response: HTTP $HTTP_STATUS"
        fi
    fi
fi

echo ""
echo "📋 Public URL format:"
echo "   https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/[file-path]"
echo ""
echo "🔧 To make bucket public (if not already done):"
echo "   ./make-s3-public.sh"
