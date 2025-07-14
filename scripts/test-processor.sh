#!/bin/bash

# Test Document Processor Service
set -e

# Configuration
PROJECT_NAME="document-processor"
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Testing Document Processor Service...${NC}"

# Get service endpoint
INGRESS_HOSTNAME=$(kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$INGRESS_HOSTNAME" ]; then
    echo -e "${YELLOW}No external ingress found, using port-forward...${NC}"
    # Start port forwarding in background
    kubectl port-forward service/document-processor-service 8080:80 &
    PORT_FORWARD_PID=$!
    sleep 5
    ENDPOINT="http://localhost:8080"
else
    ENDPOINT="http://${INGRESS_HOSTNAME}"
fi

echo -e "${YELLOW}Testing endpoint: ${ENDPOINT}${NC}"

# Test health endpoint
echo -e "${GREEN}Testing health endpoint...${NC}"
HEALTH_RESPONSE=$(curl -s -w "%{http_code}" ${ENDPOINT}/health || echo "000")
HTTP_CODE="${HEALTH_RESPONSE: -3}"

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Health check passed${NC}"
else
    echo -e "${RED}❌ Health check failed (HTTP $HTTP_CODE)${NC}"
fi

# Test with sample document processing request
echo -e "${GREEN}Testing document processing endpoint...${NC}"

# Create test payload
TEST_PAYLOAD='{
    "record": {
        "document_id": "test-doc-'$(date +%s)'",
        "bucket": "test-bucket",
        "key": "test-document.pdf",
        "status": "pending",
        "file_type": "pdf",
        "upload_date": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "source": "test"
    }
}'

echo -e "${YELLOW}Test payload:${NC}"
echo "$TEST_PAYLOAD" | jq '.' || echo "$TEST_PAYLOAD"

# Make request
PROCESS_RESPONSE=$(curl -s -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$TEST_PAYLOAD" \
    ${ENDPOINT}/process || echo "000")

HTTP_CODE="${PROCESS_RESPONSE: -3}"
RESPONSE_BODY="${PROCESS_RESPONSE%???}"

echo -e "${YELLOW}Response (HTTP $HTTP_CODE):${NC}"
echo "$RESPONSE_BODY" | jq '.' || echo "$RESPONSE_BODY"

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Processing endpoint test passed${NC}"
else
    echo -e "${RED}❌ Processing endpoint test failed (HTTP $HTTP_CODE)${NC}"
fi

# Test status endpoint if we got a document ID
if echo "$RESPONSE_BODY" | jq -r '.document_id' >/dev/null 2>&1; then
    DOC_ID=$(echo "$RESPONSE_BODY" | jq -r '.document_id')
    echo -e "${GREEN}Testing status endpoint for document: $DOC_ID${NC}"
    
    sleep 2  # Give it a moment
    
    STATUS_RESPONSE=$(curl -s -w "%{http_code}" ${ENDPOINT}/status/${DOC_ID} || echo "000")
    STATUS_HTTP_CODE="${STATUS_RESPONSE: -3}"
    STATUS_BODY="${STATUS_RESPONSE%???}"
    
    echo -e "${YELLOW}Status Response (HTTP $STATUS_HTTP_CODE):${NC}"
    echo "$STATUS_BODY" | jq '.' || echo "$STATUS_BODY"
fi

# Test metrics (if available)
echo -e "${GREEN}Testing metrics endpoint...${NC}"
METRICS_RESPONSE=$(curl -s -w "%{http_code}" ${ENDPOINT}/metrics 2>/dev/null || echo "404")
METRICS_HTTP_CODE="${METRICS_RESPONSE: -3}"

if [ "$METRICS_HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Metrics endpoint available${NC}"
else
    echo -e "${YELLOW}⚠️  Metrics endpoint not available (HTTP $METRICS_HTTP_CODE)${NC}"
fi

# Show pod logs
echo -e "${GREEN}Recent pod logs:${NC}"
kubectl logs -l app=document-processor --tail=50

# Cleanup port forward if used
if [ -n "$PORT_FORWARD_PID" ]; then
    kill $PORT_FORWARD_PID 2>/dev/null || true
fi

echo -e "${GREEN}✅ Testing completed!${NC}"

# Show additional debugging info
echo -e "${YELLOW}Debugging information:${NC}"
echo "Pod status:"
kubectl get pods -l app=document-processor
echo ""
echo "Service status:"
kubectl get service document-processor-service
echo ""
echo "Ingress status:"
kubectl get ingress document-processor-ingress
