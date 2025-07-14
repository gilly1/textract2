#!/bin/bash

echo "🔄 Updating DynamoDB table schema..."

# Note: Since DynamoDB doesn't support changing the primary key of an existing table,
# we'll need to create a new table. This script will backup existing data and recreate the table.

echo "⚠️  WARNING: This will recreate the DynamoDB table with a new schema."
echo "⚠️  This will result in data loss if you haven't backed up existing data."
echo ""
read -p "Do you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Operation cancelled."
    exit 1
fi

echo "🗂️  Applying Terraform changes..."

cd infra

# Apply the infrastructure changes
terraform plan -out=dynamo-update.tfplan
terraform apply dynamo-update.tfplan

cd ..

echo "✅ DynamoDB table schema updated successfully!"
echo ""
echo "📋 New table schema:"
echo "   - Partition Key: fileId (String)"
echo "   - Sort Key: uploadedBy (String)"
echo "   - Global Secondary Indexes:"
echo "     - StatusIndex: status (hash key)"
echo "     - UploadDateIndex: uploadedBy (hash key), uploadDate (range key)"
echo ""
echo "🔧 New API endpoints available:"
echo "   - POST /files/metadata - Save file metadata"
echo "   - GET /status/{fileId} - Get file status (default user: system)"
echo "   - GET /status/{fileId}/{uploadedBy} - Get file status with specific user"
echo "   - GET /files/{uploadedBy} - Get all files by user"
echo "   - GET /files/status/{status} - Get all files by status"
echo ""
echo "📊 To test the new schema, use the save_file_metadata function:"
echo "   fileData = {"
echo "     'fileKey': 'unique-file-id',"
echo "     'uploadedBy': 'user123',"
echo "     'fileName': 'invoice.pdf',"
echo "     'fileType': 'pdf',"
echo "     'fileSize': 1024,"
echo "     'url': 's3://bucket/path',"
echo "     'metadata': {}"
echo "   }"
