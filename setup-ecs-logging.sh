#!/bin/bash

# Script to apply enhanced CloudWatch logging configuration
echo "🔧 Enhancing ECS CloudWatch Logging Configuration"
echo "================================================="

cd infra

echo "📋 Current log group configuration:"
terraform output ecs_log_group_name 2>/dev/null || echo "Log group output not available yet"

echo ""
echo "📋 Terraform plan for logging improvements:"
terraform plan -target=aws_cloudwatch_log_group.ecs_logs

echo ""
read -p "Apply the enhanced logging configuration? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Applying enhanced logging configuration..."
    terraform apply -target=aws_cloudwatch_log_group.ecs_logs -auto-approve
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Enhanced logging configuration applied!"
        
        # Get the log group name
        LOG_GROUP=$(terraform output -raw ecs_log_group_name 2>/dev/null)
        LAMBDA_LOG_GROUP=$(terraform output -raw lambda_log_group_name 2>/dev/null)
        
        echo ""
        echo "📂 Log Groups:"
        echo "   🐳 ECS: $LOG_GROUP"
        echo "   ⚡ Lambda: $LAMBDA_LOG_GROUP"
        echo ""
        echo "📋 Retention: 14 days (increased from 7)"
        echo ""
        echo "🔍 View logs with these scripts:"
        echo "   ./view-ecs-logs.sh      # Interactive ECS log viewer"
        echo "   ./debug-processing.sh   # Complete debugging info"
        echo ""
        echo "🌐 AWS Console links:"
        echo "   ECS Logs: https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/\$252Fecs\$252Fdocument-processor"
        echo "   Lambda Logs: https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252Fdocument-processor-dynamodb-trigger"
    else
        echo "❌ Failed to apply configuration"
        exit 1
    fi
else
    echo "❌ Aborted"
fi

cd ..
