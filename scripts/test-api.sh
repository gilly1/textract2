#!/bin/bash
# API Testing Script
set -e

SERVICE_ENDPOINT="$1"
TEST_FILE="$2"

if [ -z "$SERVICE_ENDPOINT" ]; then
    echo "Getting service endpoint..."
    INGRESS_IP=$(kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$INGRESS_IP" ]; then
        SERVICE_ENDPOINT="http://$INGRESS_IP"
    else
        echo "❌ Could not get service endpoint. Please provide it manually:"
        echo "Usage: ./test-api.sh 'http://your-endpoint' [test-file]"
        exit 1
    fi
fi

# Default to invoice.pdf if no test file provided
if [ -z "$TEST_FILE" ]; then
    if [ -f "invoice.pdf" ]; then
        TEST_FILE="invoice.pdf"
        echo "Using default test file: invoice.pdf"
    elif [ -f "samples/invoice.pdf" ]; then
        TEST_FILE="samples/invoice.pdf"
        echo "Using test file: samples/invoice.pdf"
    elif [ -f "../invoice.pdf" ]; then
        TEST_FILE="../invoice.pdf"
        echo "Using test file: ../invoice.pdf"
    fi
fi

echo "Testing API at: $SERVICE_ENDPOINT"

# Test 1: Health Check
echo ""
echo "=== Test 1: Health Check ==="
if HEALTH_RESPONSE=$(curl -s -f "$SERVICE_ENDPOINT/health" 2>/dev/null); then
    echo "✅ Health Check: $HEALTH_RESPONSE"
else
    echo "❌ Health Check Failed"
fi

# Test 2: Root endpoint
echo ""
echo "=== Test 2: Root Endpoint ==="
if ROOT_RESPONSE=$(curl -s -f "$SERVICE_ENDPOINT/" 2>/dev/null); then
    echo "✅ Root Endpoint: $ROOT_RESPONSE"
else
    echo "❌ Root Endpoint Failed"
fi

# Test 3: Document Upload
echo ""
echo "=== Test 3: Document Upload ==="
if [ -n "$TEST_FILE" ] && [ -f "$TEST_FILE" ]; then
    echo "Uploading file: $TEST_FILE"
    
    UPLOAD_RESPONSE=$(curl -s -f -X POST \
        -F "file=@$TEST_FILE" \
        "$SERVICE_ENDPOINT/process" \
        2>/dev/null || echo "ERROR")
    
    if [ "$UPLOAD_RESPONSE" != "ERROR" ]; then
        echo "✅ Upload successful!"
        echo "Response: $UPLOAD_RESPONSE"
        
        # Extract processing ID
        PROCESSING_ID=$(echo "$UPLOAD_RESPONSE" | grep -o '"processing_id":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$PROCESSING_ID" ]; then
            echo "Processing ID: $PROCESSING_ID"
            sleep 2
            
            echo "Checking processing status..."
            STATUS_RESPONSE=$(curl -s -f "$SERVICE_ENDPOINT/status/$PROCESSING_ID" 2>/dev/null || echo "ERROR")
            if [ "$STATUS_RESPONSE" != "ERROR" ]; then
                echo "Status: $STATUS_RESPONSE"
            else
                echo "❌ Could not check status"
            fi
        fi
    else
        echo "❌ Document Upload Failed"
    fi
else
    echo "⏭️  Skipped - No test file found"
    echo "To test file upload with invoice.pdf, make sure invoice.pdf exists in:"
    echo "  - Current directory"
    echo "  - samples/ directory"
    echo "  - Parent directory"
    echo "Or run: ./test-api.sh '$SERVICE_ENDPOINT' 'path/to/invoice.pdf'"
fi

# Test 4: List recent results
echo ""
echo "=== Test 4: List Results ==="
if RESULTS_RESPONSE=$(curl -s -f "$SERVICE_ENDPOINT/results" 2>/dev/null); then
    echo "✅ Results retrieved"
    # Count results using grep
    RESULT_COUNT=$(echo "$RESULTS_RESPONSE" | grep -o '"processing_id"' | wc -l)
    echo "Number of results: $RESULT_COUNT"
    if [ "$RESULT_COUNT" -gt 0 ]; then
        echo "Response preview:"
        echo "$RESULTS_RESPONSE" | head -c 500
        if [ ${#RESULTS_RESPONSE} -gt 500 ]; then
            echo "... (truncated)"
        fi
    fi
else
    echo "❌ List Results Failed"
fi

echo ""
echo "=== API Testing Complete ==="
echo "Service Endpoint: $SERVICE_ENDPOINT"

if [ -n "$TEST_FILE" ] && [ -f "$TEST_FILE" ]; then
    echo "Test File Used: $TEST_FILE"
else
    echo "No test file used - place invoice.pdf in current directory for document testing"
fi
