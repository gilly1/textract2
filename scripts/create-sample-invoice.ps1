# Create Sample Invoice PDF Script
param(
    [string]$OutputPath = "invoice.pdf"
)

Write-Host "Creating sample invoice PDF for testing..." -ForegroundColor Cyan

# Check if we have a way to create PDFs
$HasPython = $false
$HasWkhtmltopdf = $false

try {
    python --version > $null 2>&1
    $HasPython = $true
} catch {}

try {
    wkhtmltopdf --version > $null 2>&1
    $HasWkhtmltopdf = $true
} catch {}

if ($HasPython) {
    Write-Host "Using Python to create PDF..." -ForegroundColor Green
    
    # Create HTML content for invoice
    $HtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Sample Invoice</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { text-align: center; margin-bottom: 30px; }
        .company { font-size: 24px; font-weight: bold; color: #2c3e50; }
        .invoice-title { font-size: 20px; margin: 20px 0; }
        .info-section { margin: 20px 0; }
        .table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .table th, .table td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        .table th { background-color: #f8f9fa; font-weight: bold; }
        .total { text-align: right; font-size: 18px; font-weight: bold; margin-top: 20px; }
        .qr-section { margin-top: 30px; text-align: center; }
        .footer { margin-top: 40px; text-align: center; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <div class="company">ACME Corporation</div>
        <div>123 Business Street, Suite 100</div>
        <div>Business City, BC 12345</div>
        <div>Phone: (555) 123-4567 | Email: billing@acme.com</div>
    </div>
    
    <div class="invoice-title">INVOICE #INV-2025-001</div>
    
    <div class="info-section">
        <strong>Bill To:</strong><br>
        John Smith<br>
        456 Customer Avenue<br>
        Customer City, CC 67890<br>
        john.smith@email.com
    </div>
    
    <div class="info-section">
        <strong>Invoice Date:</strong> July 14, 2025<br>
        <strong>Due Date:</strong> August 14, 2025<br>
        <strong>Payment Terms:</strong> Net 30
    </div>
    
    <table class="table">
        <thead>
            <tr>
                <th>Description</th>
                <th>Quantity</th>
                <th>Rate</th>
                <th>Amount</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Document Processing Service</td>
                <td>100</td>
                <td>$2.50</td>
                <td>$250.00</td>
            </tr>
            <tr>
                <td>OCR Text Extraction</td>
                <td>50</td>
                <td>$1.25</td>
                <td>$62.50</td>
            </tr>
            <tr>
                <td>QR Code Processing</td>
                <td>25</td>
                <td>$0.75</td>
                <td>$18.75</td>
            </tr>
            <tr>
                <td>Premium Support</td>
                <td>1</td>
                <td>$99.00</td>
                <td>$99.00</td>
            </tr>
        </tbody>
    </table>
    
    <div class="total">
        <div>Subtotal: $430.25</div>
        <div>Tax (8.5%): $36.57</div>
        <div style="border-top: 2px solid #333; padding-top: 10px; margin-top: 10px;">
            <strong>Total: $466.82</strong>
        </div>
    </div>
    
    <div class="qr-section">
        <div>Payment QR Code:</div>
        <div style="margin: 10px 0; font-family: monospace; font-size: 20px; letter-spacing: 2px;">
            ████ ██ ████ ████<br>
            ██    ██    ██  ██<br>
            ██ ██ ██ ██ ██ ██<br>
            ██    ██    ██    <br>
            ████ ██ ████ ████
        </div>
        <div>Scan to pay: $466.82</div>
    </div>
    
    <div class="footer">
        <div>Thank you for your business!</div>
        <div>Payment ID: PAY-2025-INV001-XYZ123</div>
        <div>Reference: ACME-PROC-20250714</div>
    </div>
</body>
</html>
"@
    
    # Save HTML to temp file
    $TempHtml = [System.IO.Path]::GetTempFileName() + ".html"
    $HtmlContent | Out-File -FilePath $TempHtml -Encoding UTF8
    
    # Create Python script to convert HTML to PDF
    $PythonScript = @"
import sys
try:
    from weasyprint import HTML
    HTML('$($TempHtml.Replace('\', '/'))').write_pdf('$($OutputPath.Replace('\', '/'))')
    print('PDF created successfully using WeasyPrint')
except ImportError:
    try:
        import pdfkit
        pdfkit.from_file('$($TempHtml.Replace('\', '//'))', '$($OutputPath.Replace('\', '/'))')
        print('PDF created successfully using pdfkit')
    except ImportError:
        print('Neither WeasyPrint nor pdfkit available')
        print('Install with: pip install weasyprint')
        sys.exit(1)
except Exception as e:
    print(f'Error creating PDF: {e}')
    sys.exit(1)
"@
    
    $TempPython = [System.IO.Path]::GetTempFileName() + ".py"
    $PythonScript | Out-File -FilePath $TempPython -Encoding UTF8
    
    try {
        python $TempPython
        if (Test-Path $OutputPath) {
            Write-Host "✅ Sample invoice PDF created: $OutputPath" -ForegroundColor Green
            Write-Host "This PDF contains:" -ForegroundColor Cyan
            Write-Host "  - Invoice text for OCR testing" -ForegroundColor White
            Write-Host "  - Table data for text extraction" -ForegroundColor White
            Write-Host "  - QR code placeholder for QR testing" -ForegroundColor White
            Write-Host "  - Various text elements to test processing" -ForegroundColor White
        } else {
            Write-Host "❌ Failed to create PDF" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Error running Python script: $_" -ForegroundColor Red
        Write-Host "Try installing required packages:" -ForegroundColor Yellow
        Write-Host "  pip install weasyprint" -ForegroundColor Cyan
        Write-Host "  or" -ForegroundColor Yellow
        Write-Host "  pip install pdfkit" -ForegroundColor Cyan
    } finally {
        # Clean up temp files
        if (Test-Path $TempHtml) { Remove-Item $TempHtml }
        if (Test-Path $TempPython) { Remove-Item $TempPython }
    }
} else {
    Write-Host "❌ Python not found. Please install Python to create sample PDF" -ForegroundColor Red
    Write-Host "Alternatively, you can:" -ForegroundColor Yellow
    Write-Host "  1. Create your own invoice.pdf file" -ForegroundColor Cyan
    Write-Host "  2. Download a sample PDF from the internet" -ForegroundColor Cyan
    Write-Host "  3. Use any existing PDF file for testing" -ForegroundColor Cyan
}
