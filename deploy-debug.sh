#!/bin/bash

echo "🔧 Quick rebuild and deploy with debug logging..."

# Build and push
docker build -t document-processor:latest .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 105714714499.dkr.ecr.us-east-1.amazonaws.com
docker tag document-processor:latest 105714714499.dkr.ecr.us-east-1.amazonaws.com/document-processor:latest
docker push 105714714499.dkr.ecr.us-east-1.amazonaws.com/document-processor:latest

# Force deployment
aws ecs update-service \
    --cluster document-processor-cluster \
    --service document-processor-service \
    --force-new-deployment \
    --region us-east-1 \
    --no-cli-pager

echo "✅ Deployment initiated. Wait 2-3 minutes then test again."
echo "📊 Monitor logs with:"
echo "aws logs tail /ecs/document-processor --follow"
