#!/bin/bash
echo "=== Debugging Document Processing ==="
echo "Time: $(date)"
echo ""

echo "1. ECS Service Status:"
aws ecs describe-services --cluster document-processor-cluster --services document-processor-service --query 'services[0].{Status:status,Running:runningCount,TaskDefinition:taskDefinition}' --output table

echo ""
echo "2. Recent ECS Logs (last 5 minutes):"
ECS_LOG_GROUP="/ecs/document-processor"
LATEST_ECS_STREAM=$(aws logs describe-log-streams --log-group-name "$ECS_LOG_GROUP" --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text 2>/dev/null)
if [ "$LATEST_ECS_STREAM" != "None" ] && [ ! -z "$LATEST_ECS_STREAM" ]; then
    echo "📂 ECS Log Stream: $LATEST_ECS_STREAM"
    aws logs get-log-events --log-group-name "$ECS_LOG_GROUP" --log-stream-name "$LATEST_ECS_STREAM" --start-time $(date -d '5 minutes ago' +%s)000 --query 'events[].message' --output text | tail -20
else
    echo "❌ No ECS log streams found"
    echo "🔧 Checking if ECS tasks are running..."
    aws ecs list-tasks --cluster document-processor-cluster --service-name document-processor-service --query 'taskArns' --output table
fi

echo ""
echo "3. Recent Lambda Logs (last 5 minutes):"
LAMBDA_LOG_GROUP="/aws/lambda/document-processor-dynamodb-trigger"
LAMBDA_STREAM=$(aws logs describe-log-streams --log-group-name "$LAMBDA_LOG_GROUP" --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text 2>/dev/null)
if [ "$LAMBDA_STREAM" != "None" ] && [ ! -z "$LAMBDA_STREAM" ]; then
    echo "📂 Lambda Log Stream: $LAMBDA_STREAM"
    aws logs get-log-events --log-group-name "$LAMBDA_LOG_GROUP" --log-stream-name "$LAMBDA_STREAM" --start-time $(date -d '5 minutes ago' +%s)000 --query 'events[].message' --output text | tail -10
else
    echo "❌ No Lambda log streams found"
fi

echo ""
echo "4. ALB Health Check:"
ALB_URL=$(cd infra && terraform output -raw load_balancer_url 2>/dev/null)
if [ ! -z "$ALB_URL" ]; then
    echo "🌐 Testing: $ALB_URL/health"
    HEALTH_RESPONSE=$(curl -s -w "HTTP_STATUS:%{http_code}" "$ALB_URL/health")
    HTTP_STATUS=$(echo "$HEALTH_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
    RESPONSE_BODY=$(echo "$HEALTH_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ Health check passed (HTTP $HTTP_STATUS)"
        echo "📋 Response: $RESPONSE_BODY"
    else
        echo "❌ Health check failed (HTTP $HTTP_STATUS)"
        echo "📋 Response: $RESPONSE_BODY"
    fi
else
    echo "❌ Could not get ALB URL"
fi

echo ""
echo "5. CloudWatch Log Groups:"
echo "📂 Available log groups for this application:"
aws logs describe-log-groups --log-group-name-prefix "/ecs/document-processor" --query 'logGroups[].logGroupName' --output table
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/document-processor" --query 'logGroups[].logGroupName' --output table
