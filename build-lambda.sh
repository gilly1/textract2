#!/bin/bash

# Script to package Lambda function with dependencies

set -e

echo "🔧 Building Lambda deployment package..."

# Create build directory
BUILD_DIR="lambda_build"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

# Copy Lambda function code
cp lambda/dynamodb_trigger.py $BUILD_DIR/

# Install dependencies to build directory
pip install -r lambda/requirements.txt -t $BUILD_DIR/

# Create deployment package
cd $BUILD_DIR
zip -r ../lambda_function.zip .
cd ..

# Clean up
rm -rf $BUILD_DIR

echo "✅ Lambda deployment package created: lambda_function.zip"
echo "📝 Package contents:"
unzip -l lambda_function.zip | head -20
