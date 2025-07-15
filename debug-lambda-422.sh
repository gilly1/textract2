#!/bin/bash

echo "🔍 Getting detailed Lambda logs to debug 422 error..."

# Get the latest Lambda log stream
LAMBDA_LOG_GROUP="/aws/lambda/document-processor-dynamodb-trigger"
LATEST_STREAM=$(aws logs describe-log-streams \
    --log-group-name "$LAMBDA_LOG_GROUP" \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text 2>/dev/null)

if [ "$LATEST_STREAM" = "None" ] || [ -z "$LATEST_STREAM" ]; then
    echo "❌ No Lambda log streams found"
    exit 1
fi

echo "📂 Lambda Log Stream: $LATEST_STREAM"
echo ""
echo "📋 Recent Lambda logs (last 5 minutes):"
echo "========================================"

aws logs get-log-events \
    --log-group-name "$LAMBDA_LOG_GROUP" \
    --log-stream-name "$LATEST_STREAM" \
    --start-time $(date -d '5 minutes ago' +%s)000 \
    --query 'events[].message' \
    --output text | tail -20

echo ""
echo "🔍 Looking for validation errors..."
echo "=================================="

aws logs get-log-events \
    --log-group-name "$LAMBDA_LOG_GROUP" \
    --log-stream-name "$LATEST_STREAM" \
    --start-time $(date -d '5 minutes ago' +%s)000 \
    --query 'events[].message' \
    --output text | grep -A5 -B5 "422\|Validation error\|Unprocessable Entity" || echo "No validation error details found in Lambda logs"
