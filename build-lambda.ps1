# PowerShell script to package Lambda function with dependencies

$ErrorActionPreference = "Stop"

Write-Host "🔧 Building Lambda deployment package..." -ForegroundColor Green

# Create build directory
$BUILD_DIR = "lambda_build"
if (Test-Path $BUILD_DIR) {
    Remove-Item $BUILD_DIR -Recurse -Force
}
New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null

# Copy Lambda function code
Copy-Item "lambda/dynamodb_trigger.py" "$BUILD_DIR/"

# Install dependencies to build directory
Write-Host "📦 Installing Python dependencies..." -ForegroundColor Yellow
pip install -r lambda/requirements.txt -t $BUILD_DIR/

# Create deployment package
Write-Host "📝 Creating ZIP package..." -ForegroundColor Yellow
Compress-Archive -Path "$BUILD_DIR/*" -DestinationPath "lambda_function.zip" -Force

# Clean up
Remove-Item $BUILD_DIR -Recurse -Force

Write-Host "✅ Lambda deployment package created: lambda_function.zip" -ForegroundColor Green
Write-Host "📝 Package size:" -ForegroundColor Cyan
$fileSize = (Get-Item "lambda_function.zip").Length / 1MB
Write-Host "$([math]::Round($fileSize, 2)) MB" -ForegroundColor White
