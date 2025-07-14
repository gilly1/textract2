#!/bin/bash
# Create Sample Invoice PDF Script
set -e

OUTPUT_PATH="${1:-invoice.pdf}"

echo "Creating sample invoice PDF for testing..."

# Check if we have tools to create PDFs
HAS_PYTHON=false
HAS_WKHTMLTOPDF=false

if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    HAS_PYTHON=true
fi

if command -v wkhtmltopdf >/dev/null 2>&1; then
    HAS_WKHTMLTOPDF=true
fi

if [ "$HAS_PYTHON" = true ]; then
    echo "Using Python to create PDF..."
    
    # Create HTML content for invoice
    TEMP_HTML=$(mktemp --suffix=.html)
    
    cat > "$TEMP_HTML" << 'EOF'
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
EOF

    # Create Python script to convert HTML to PDF
    TEMP_PYTHON=$(mktemp --suffix=.py)
    
    cat > "$TEMP_PYTHON" << EOF
import sys
try:
    from weasyprint import HTML
    HTML('$TEMP_HTML').write_pdf('$OUTPUT_PATH')
    print('PDF created successfully using WeasyPrint')
except ImportError:
    try:
        import pdfkit
        pdfkit.from_file('$TEMP_HTML', '$OUTPUT_PATH')
        print('PDF created successfully using pdfkit')
    except ImportError:
        print('Neither WeasyPrint nor pdfkit available')
        print('Install with: pip install weasyprint')
        sys.exit(1)
except Exception as e:
    print(f'Error creating PDF: {e}')
    sys.exit(1)
EOF

    # Try Python3 first, then Python
    PYTHON_CMD=""
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
    fi
    
    if [ -n "$PYTHON_CMD" ]; then
        if $PYTHON_CMD "$TEMP_PYTHON"; then
            if [ -f "$OUTPUT_PATH" ]; then
                echo "✅ Sample invoice PDF created: $OUTPUT_PATH"
                echo "This PDF contains:"
                echo "  - Invoice text for OCR testing"
                echo "  - Table data for text extraction"
                echo "  - QR code placeholder for QR testing"
                echo "  - Various text elements to test processing"
            else
                echo "❌ Failed to create PDF"
            fi
        else
            echo "❌ Error running Python script"
            echo "Try installing required packages:"
            echo "  pip install weasyprint"
            echo "  or"
            echo "  pip install pdfkit"
        fi
    fi
    
    # Clean up temp files
    rm -f "$TEMP_HTML" "$TEMP_PYTHON"
    
elif [ "$HAS_WKHTMLTOPDF" = true ]; then
    echo "Using wkhtmltopdf to create PDF..."
    # Similar process with wkhtmltopdf if available
    echo "❌ wkhtmltopdf method not implemented yet"
else
    echo "❌ Neither Python nor wkhtmltopdf found"
    echo "Please install Python to create sample PDF, or:"
    echo "  1. Create your own invoice.pdf file"
    echo "  2. Download a sample PDF from the internet" 
    echo "  3. Use any existing PDF file for testing"
fi
