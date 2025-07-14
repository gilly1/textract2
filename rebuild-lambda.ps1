# PowerShell script to rebuild Lambda function package
Write-Host "Rebuilding Lambda function package..."

# Change to lambda directory
Set-Location "lambda"

# Create zip file with Lambda function and dependencies
if (Test-Path "..\lambda_function.zip") {
    Remove-Item "..\lambda_function.zip" -Force
}

# Compress all Python files and requirements
Compress-Archive -Path "*.py", "requirements.txt" -DestinationPath "..\lambda_function.zip" -Force

# Return to parent directory
Set-Location ".."

Write-Host "Lambda package rebuilt successfully: lambda_function.zip"
Write-Host "File size: $((Get-Item 'lambda_function.zip').Length) bytes"
