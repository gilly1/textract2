#!/bin/bash

# Script to make S3 bucket publicly accessible
echo "🌐 Making S3 bucket publicly accessible..."
echo ""
echo "⚠️  WARNING: This will make all files in the bucket publicly readable!"
echo "   Anyone with the URL will be able to access the files."
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborted."
    exit 1
fi

cd infra

echo "📋 Step 1: Planning Terraform changes..."
terraform plan \
    -target=aws_s3_bucket_public_access_block.documents \
    -target=aws_s3_bucket_policy.documents_policy \
    -target=aws_s3_bucket_cors_configuration.documents_cors

echo ""
echo "Do you want to apply these changes?"
read -p "Apply changes? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Step 2: Applying changes..."
    terraform apply \
        -target=aws_s3_bucket_public_access_block.documents \
        -target=aws_s3_bucket_policy.documents_policy \
        -target=aws_s3_bucket_cors_configuration.documents_cors \
        -auto-approve
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ S3 bucket is now publicly accessible!"
        
        # Get bucket info
        BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null)
        AWS_REGION="us-east-1"  # Set from your config
        
        echo ""
        echo "📁 Bucket Details:"
        echo "   🪣 Name: $BUCKET_NAME"
        echo "   🌍 Region: $AWS_REGION"
        echo "   🔗 Public URL format: https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/[file-path]"
        echo ""
        echo "📋 Example URLs for your uploaded files:"
        echo "   https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/documents/[document-id]/[filename]"
        echo ""
        echo "🧪 Test with your workflow:"
        echo "   ./test-workflow.sh invoice.pdf"
        echo "   Then access: https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/documents/test-doc-[timestamp]/invoice.pdf"
        
    else
        echo "❌ Failed to apply changes"
        exit 1
    fi
else
    echo "❌ Aborted."
fi

cd ..
