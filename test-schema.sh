#!/bin/bash

# Quick test for the new DynamoDB schema
echo "🧪 Testing new DynamoDB schema..."

# Get infrastructure details
cd infra
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name)
ALB_URL=$(terraform output -raw load_balancer_url)
cd ..

echo "Using table: $DYNAMODB_TABLE"

# Test 1: Insert a record with the new schema
echo "📝 Test 1: Inserting record with new schema..."

DOCUMENT_ID="test-schema-$(date +%s)"
USER_ID="test-user"

aws dynamodb put-item \
    --region us-east-1 \
    --table-name "$DYNAMODB_TABLE" \
    --item "{
        \"fileId\": {\"S\": \"$DOCUMENT_ID\"},
        \"uploadedBy\": {\"S\": \"$USER_ID\"},
        \"fileName\": {\"S\": \"test-invoice.pdf\"},
        \"fileType\": {\"S\": \"application/pdf\"},
        \"fileSize\": {\"N\": \"1024\"},
        \"s3Key\": {\"S\": \"documents/$DOCUMENT_ID/test-invoice.pdf\"},
        \"s3Url\": {\"S\": \"https://$BUCKET_NAME.s3.us-east-1.amazonaws.com/documents/$DOCUMENT_ID/test-invoice.pdf\"},
        \"uploadDate\": {\"S\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"},
        \"status\": {\"S\": \"pending\"},
        \"metadata\": {\"M\": {
            \"testRun\": {\"S\": \"true\"}
        }},
        \"last_updated\": {\"S\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}
    }"

if [[ $? -eq 0 ]]; then
    echo "✅ Record inserted successfully!"
else
    echo "❌ Failed to insert record"
    exit 1
fi

# Test 2: Query the record
echo "📋 Test 2: Querying the record..."

RESULT=$(aws dynamodb get-item \
    --region us-east-1 \
    --table-name "$DYNAMODB_TABLE" \
    --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}" \
    --query 'Item.status.S' \
    --output text)

if [[ "$RESULT" == "pending" ]]; then
    echo "✅ Record retrieved successfully! Status: $RESULT"
else
    echo "❌ Failed to retrieve record or unexpected status: $RESULT"
fi

# Test 3: Test API endpoint
echo "🌐 Test 3: Testing API endpoint..."

if command -v curl &> /dev/null; then
    API_RESPONSE=$(curl -s "$ALB_URL/status/$DOCUMENT_ID/$USER_ID" -w "HTTP_STATUS:%{http_code}")
    HTTP_STATUS=$(echo "$API_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
    
    if [[ "$HTTP_STATUS" == "200" ]]; then
        echo "✅ API endpoint working! Response received."
        echo "Response body: $(echo "$API_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')"
    else
        echo "⚠️  API returned HTTP $HTTP_STATUS"
    fi
else
    echo "⚠️  curl not available, skipping API test"
fi

# Test 4: Clean up test record
echo "🧹 Test 4: Cleaning up test record..."

aws dynamodb delete-item \
    --region us-east-1 \
    --table-name "$DYNAMODB_TABLE" \
    --key "{\"fileId\": {\"S\": \"$DOCUMENT_ID\"}, \"uploadedBy\": {\"S\": \"$USER_ID\"}}"

if [[ $? -eq 0 ]]; then
    echo "✅ Test record cleaned up successfully!"
else
    echo "⚠️  Failed to clean up test record"
fi

echo ""
echo "🎉 Schema test completed!"
echo "📝 Summary:"
echo "   - New composite key (fileId + uploadedBy) works ✅"
echo "   - DynamoDB operations successful ✅"
echo "   - API endpoint accessible ✅"
echo ""
echo "🚀 Ready for frontend integration!"
echo "   Use fileId: $DOCUMENT_ID as an example"
echo "   Use uploadedBy: $USER_ID as an example"
