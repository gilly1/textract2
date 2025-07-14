#!/bin/bash

# Script to view ECS CloudWatch logs
echo "📋 ECS CloudWatch Logs Viewer"
echo "=============================="

# Get log group name
cd infra
LOG_GROUP="/ecs/document-processor"
echo "📂 Log Group: $LOG_GROUP"

# Check if log group exists
if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --query 'logGroups[0].logGroupName' --output text >/dev/null 2>&1; then
    echo "❌ Log group not found. Creating it..."
    aws logs create-log-group --log-group-name "$LOG_GROUP"
fi

# Get available log streams
echo ""
echo "🔍 Available log streams:"
STREAMS=$(aws logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --order-by LastEventTime \
    --descending \
    --max-items 5 \
    --query 'logStreams[].[logStreamName,lastEventTime,storedBytes]' \
    --output table)

if [ $? -eq 0 ]; then
    echo "$STREAMS"
else
    echo "❌ Could not retrieve log streams"
    exit 1
fi

# Get the latest stream
LATEST_STREAM=$(aws logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text 2>/dev/null)

if [ "$LATEST_STREAM" = "None" ] || [ -z "$LATEST_STREAM" ]; then
    echo ""
    echo "⚠️  No log streams found. This could mean:"
    echo "   1. ECS service hasn't started yet"
    echo "   2. ECS tasks are failing to start"
    echo "   3. Logging configuration needs to be applied"
    echo ""
    echo "🔧 Troubleshooting steps:"
    echo "   1. Check ECS service status: aws ecs describe-services --cluster document-processor-cluster --services document-processor-service"
    echo "   2. Check ECS tasks: aws ecs list-tasks --cluster document-processor-cluster"
    echo "   3. Apply logging configuration: cd infra && terraform apply"
    exit 1
fi

echo ""
echo "📖 Latest log stream: $LATEST_STREAM"
echo ""

# Function to get recent logs
get_recent_logs() {
    local minutes=${1:-10}
    local start_time=$(date -d "$minutes minutes ago" +%s)000
    
    echo "📋 Recent logs (last $minutes minutes):"
    echo "========================================"
    
    aws logs get-log-events \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name "$LATEST_STREAM" \
        --start-time $start_time \
        --query 'events[].[timestamp,message]' \
        --output table
}

# Function to tail logs in real-time
tail_logs() {
    echo "📡 Tailing logs in real-time (Press Ctrl+C to stop)..."
    echo "====================================================="
    
    # Start time for tailing
    START_TIME=$(date +%s)000
    
    while true; do
        CURRENT_TIME=$(date +%s)000
        
        # Get logs since last check
        aws logs get-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-name "$LATEST_STREAM" \
            --start-time $START_TIME \
            --end-time $CURRENT_TIME \
            --query 'events[].message' \
            --output text 2>/dev/null | grep -v "^$"
        
        # Update start time for next iteration
        START_TIME=$CURRENT_TIME
        
        sleep 2
    done
}

# Menu
echo "What would you like to do?"
echo "1) View recent logs (last 10 minutes)"
echo "2) View recent logs (last 30 minutes)"
echo "3) View recent logs (last 1 hour)"
echo "4) Tail logs in real-time"
echo "5) Check ECS service status"
read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        get_recent_logs 10
        ;;
    2)
        get_recent_logs 30
        ;;
    3)
        get_recent_logs 60
        ;;
    4)
        tail_logs
        ;;
    5)
        echo ""
        echo "🔍 ECS Service Status:"
        echo "====================="
        aws ecs describe-services \
            --cluster document-processor-cluster \
            --services document-processor-service \
            --query 'services[0].{Status:status,RunningCount:runningCount,PendingCount:pendingCount,DesiredCount:desiredCount}' \
            --output table
        
        echo ""
        echo "🔍 ECS Tasks:"
        echo "============"
        aws ecs list-tasks \
            --cluster document-processor-cluster \
            --service-name document-processor-service \
            --query 'taskArns' \
            --output table
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

cd ..
