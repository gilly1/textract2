#!/bin/bash

echo "🔧 Adding CloudWatch logging support to ECS..."

cd infra

echo "📋 Planning Terraform changes..."
terraform plan

echo ""
read -p "Apply these changes to add logging? (y/n): " APPLY

if [[ "$APPLY" == "y" ]]; then
    echo "🚀 Applying Terraform changes..."
    terraform apply -auto-approve
    
    echo "✅ Logging support added!"
    echo ""
    echo "🔄 Now force a new ECS deployment to pick up the logging configuration..."
    aws ecs update-service \
        --cluster document-processor-cluster \
        --service document-processor-service \
        --force-new-deployment \
        --region us-east-1 \
        --no-cli-pager
    
    echo ""
    echo "⏳ Wait 2-3 minutes for deployment, then check logs with:"
    echo "aws logs describe-log-groups --log-group-name-prefix '/ecs'"
    echo ""
    echo "To view logs:"
    echo "LATEST_STREAM=\$(aws logs describe-log-streams --log-group-name '/ecs/document-processor' --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text)"
    echo "aws logs get-log-events --log-group-name '/ecs/document-processor' --log-stream-name \"\$LATEST_STREAM\""
else
    echo "⏭️ Skipping Terraform apply."
fi

cd ..
