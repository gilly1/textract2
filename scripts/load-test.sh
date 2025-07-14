#!/bin/bash
# Simple Load Test Script
set -e

SERVICE_ENDPOINT="$1"
REQUESTS="${2:-10}"
CONCURRENT="${3:-3}"

if [ -z "$SERVICE_ENDPOINT" ]; then
    INGRESS_IP=$(kubectl get ingress document-processor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$INGRESS_IP" ]; then
        SERVICE_ENDPOINT="http://$INGRESS_IP"
    else
        echo "❌ Could not get service endpoint. Please provide it manually:"
        echo "Usage: ./load-test.sh 'http://your-endpoint' [requests] [concurrent]"
        exit 1
    fi
fi

echo "Running load test against: $SERVICE_ENDPOINT"
echo "Requests: $REQUESTS, Concurrent: $CONCURRENT"

# Create temporary directory for results
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Starting load test..."

# Function to make a single request
make_request() {
    local request_id=$1
    local endpoint=$2
    local temp_dir=$3
    
    local start_time=$(date +%s%3N)
    
    if curl -s -f "$endpoint/health" > "$temp_dir/response_$request_id" 2>/dev/null; then
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        echo "SUCCESS,$request_id,$duration" > "$temp_dir/result_$request_id"
    else
        echo "FAILED,$request_id,0" > "$temp_dir/result_$request_id"
    fi
}

# Start concurrent requests
for ((i=1; i<=REQUESTS; i++)); do
    # Limit concurrent processes
    while [ $(jobs -r | wc -l) -ge $CONCURRENT ]; do
        sleep 0.1
    done
    
    make_request $i "$SERVICE_ENDPOINT" "$TEMP_DIR" &
    echo "Started request $i"
done

# Wait for all background jobs to complete
wait

echo "Collecting results..."

# Analyze results
SUCCESSFUL=0
FAILED=0
TOTAL_DURATION=0
MIN_DURATION=999999
MAX_DURATION=0

for result_file in "$TEMP_DIR"/result_*; do
    if [ -f "$result_file" ]; then
        IFS=',' read -r status request_id duration < "$result_file"
        
        if [ "$status" = "SUCCESS" ]; then
            SUCCESSFUL=$((SUCCESSFUL + 1))
            TOTAL_DURATION=$((TOTAL_DURATION + duration))
            
            if [ "$duration" -lt "$MIN_DURATION" ]; then
                MIN_DURATION=$duration
            fi
            
            if [ "$duration" -gt "$MAX_DURATION" ]; then
                MAX_DURATION=$duration
            fi
        else
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "=== Load Test Results ==="
echo "Total Requests: $REQUESTS"
echo "Successful: $SUCCESSFUL"
echo "Failed: $FAILED"

if [ "$SUCCESSFUL" -gt 0 ]; then
    AVG_DURATION=$((TOTAL_DURATION / SUCCESSFUL))
    echo "Average Response Time: ${AVG_DURATION}ms"
    echo "Min Response Time: ${MIN_DURATION}ms"
    echo "Max Response Time: ${MAX_DURATION}ms"
fi

if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "Failed requests: $FAILED"
fi
