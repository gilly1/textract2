import os
import io
import re
import fitz
import boto3
import cv2
import pytesseract
import tempfile
import logging
import requests
import numpy as np
from PIL import Image
from pyzbar.pyzbar import decode
from bs4 import BeautifulSoup
from datetime import datetime
from decimal import Decimal
from typing import List, Dict, Any, Optional
from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel

# Setup
app = FastAPI(title="Hybrid Document Processor", version="4.0.0")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# AWS setup
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
DYNAMODB_TABLE_NAME = os.getenv("DYNAMODB_TABLE_NAME", "document-processor-results")
s3_client = boto3.client("s3", region_name=AWS_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)

# ----------------------------- Models -----------------------------

class DynamoDBRecord(BaseModel):
    document_id: str
    bucket: str
    key: str
    status: str
    file_type: str
    upload_date: Optional[str] = None

class ProcessingRequest(BaseModel):
    record: DynamoDBRecord

class QRCode(BaseModel):
    page: int
    data: str
    position: Dict[str, int]

class OCRResult(BaseModel):
    page: int
    text: str
    confidence: float
    raw_text: Optional[str] = None
    word_count: Optional[int] = None
    line_count: Optional[int] = None
    word_details: Optional[List[Dict[str, Any]]] = None

class ProcessingResult(BaseModel):
    document_id: str
    status: str
    qr_codes: List[QRCode]
    ocr_results: List[OCRResult]
    validation_score: int
    errors: List[str]
    processed_date: str
    invoice_fields: Dict[str, Any]
    validated_qr_links: List[str]
    invalid_qr_links: List[str]
    ocr_summary: Optional[Dict[str, Any]] = None

# -------------------------- Utilities ----------------------------

def convert_float_to_decimal(obj):
    if isinstance(obj, list):
        return [convert_float_to_decimal(i) for i in obj]
    elif isinstance(obj, dict):
        return {k: convert_float_to_decimal(v) for k, v in obj.items()}
    elif isinstance(obj, float):
        return Decimal(str(obj))
    else:
        return obj

def extract_invoice_fields(text: str) -> Dict[str, Any]:
    def find(pattern, flags=0, group=1):
        match = re.search(pattern, text, flags)
        return match.group(group).strip() if match else "Not found"

    def find_multiline(label, text, max_lines=5):
        """
        Finds the field by label, collects value after ':', and grabs the following lines 
        until a blank, a separator, or the next field label (i.e., any line ending with colon).
        """
        lines = text.splitlines()
        found = False
        values = []
        for idx, line in enumerate(lines):
            # Find the label
            if not found and line.strip().startswith(label):
                after_colon = line.split(':', 1)[1].strip() if ':' in line else ''
                values.append(after_colon)
                found = True
                continue
            if found:
                # Stop at: blank, separator, or a line that ends with a colon (i.e., new label)
                if (not line.strip() or 
                    re.match(r'^[- ]+$', line.strip()) or 
                    re.match(r'.+:$', line.strip())):
                    break
                values.append(line.strip())
                if len(values) >= max_lines:
                    break
        if values:
            return ''.join(values).replace(' ', '').replace('\n', '')
        return "Not found"

    fields = {}

    fields['Invoice Number'] = find(r'INVOICE NO[:\s]+([A-Z0-9/]+)')
    fields['Invoice Date'] = find(r'Date\s*:\s*([0-9]{2}/[0-9]{2}/[0-9]{4}(?:\s[0-9:]+)?)')
    fields['Due Date'] = find(r'Due Date\s*:\s*([0-9]{2}/[0-9]{2}/[0-9]{4})')

    # Customer (Buyer) Info
    inv_to = re.search(r'INVOICE TO\s+PIN:\s*([A-Z0-9]+)\s+NAME:\s*([A-Z0-9 \-]+)', text)
    fields['Customer/Buyer PIN'] = inv_to.group(1).strip() if inv_to else "Not found"
    fields['Customer/Buyer Name'] = inv_to.group(2).strip() if inv_to else "Not found"

    # Supplier (Vendor) Info
    inv_from = re.search(r'INVOICE FROM\s+PIN:\s*([A-Z0-9]+)\s+NAME:\s*([A-Z0-9 \-]+)', text)
    fields['Supplier/Vendor PIN'] = inv_from.group(1).strip() if inv_from else "Not found"
    fields['Supplier/Vendor Name'] = inv_from.group(2).strip() if inv_from else "Not found"

    # Addresses (if present)
    fields['Supplier Address'] = find(r'INVOICE FROM.*?ADDRESS[:\s]+([A-Z0-9 ,\-]+)', re.DOTALL)
    fields['Customer Address'] = find(r'INVOICE TO.*?ADDRESS[:\s]+([A-Z0-9 ,\-]+)', re.DOTALL)

    # Line Items Array Extraction
    line_item_pattern = re.compile(
        r'([A-Z0-9]+)\s+([A-Za-z ]+?)\s+(\d+)\s+x\s+([\d,\.]+)\s+(\d+%)\s+([\d,\.]+)\s+([\d,\.]+)\s+([\d,\.]+)',
        re.MULTILINE
    )
    items = []
    for m in line_item_pattern.finditer(text):
        item = {
            "Item Code": m.group(1),
            "Description": m.group(2).strip(),
            "Quantity": m.group(3),
            "Unit Price": m.group(4),
            "Tax Rate": m.group(5),
            "Subtotal": m.group(6),
            "Tax Amount": m.group(7),
            "Total": m.group(8)
        }
        items.append(item)
    fields['Line Items'] = items

    # Amounts and currency
    fields['Subtotal Amount'] = find(r'Totals\s+KSh\s*([\d,\.]+)\s+KSh\s*[\d,\.]+\s+KSh\s*[\d,\.]+')
    fields['Taxable Amount'] = find(r'Totals\s+KSh\s*([\d,\.]+)\s+KSh\s*[\d,\.]+\s+KSh\s*[\d,\.]+')
    fields['VAT/Tax Amount'] = find(r'Tax\s*KSh\s*([\d,\.]+)')
    fields['Total Amount Due'] = find(r'Total\s*KSh\s*([\d,\.]+)')
    fields['Currency'] = "KES" if "KSh" in text or "KES" in text else "Not found"

    # Payment Terms and PO
    fields['Payment Terms'] = find(r'Payment Terms\s*:\s*([A-Za-z0-9 ]+)')
    fields['Purchase Order Number'] = find(r'Purchase Order Number\s*[:\-]?\s*([A-Z0-9\-]+)', flags=re.IGNORECASE)

    # SCU / CU and Internal Data (multi-line aware)
    fields['Internal Data'] = find_multiline('Internal Data', text)
    fields['Receipt Signature'] = find_multiline('Receipt Signature', text)
    fields['SCU ID'] = find_multiline('SCU ID', text)
    fields['CU INVOICE NO.'] = find_multiline('CU INVOICE NO.', text)

    return fields

def check_qr_links(qr_links: List[str], invoice_fields: Dict[str, Any]) -> tuple[List[str], List[str]]:
    valid, invalid = [], []
    expected_invoice = invoice_fields.get("Invoice Number", "").lower()

    for link in qr_links:
        try:
            r = requests.get(link, timeout=10)
            text = BeautifulSoup(r.text, "html.parser").get_text(" ", strip=True).lower()
            if expected_invoice and expected_invoice in text:
                valid.append(link)
            else:
                invalid.append(link)
        except Exception as e:
            invalid.append(f"{link} - Error: {e}")
    return valid, invalid

def extract_qr_codes(image: Image.Image, page_num: int) -> List[QRCode]:
    gray = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2GRAY)
    decoded = decode(gray)
    result = []

    for obj in decoded:
        qr_data = obj.data.decode('utf-8')
        x, y, w, h = obj.rect
        result.append(QRCode(
            page=page_num,
            data=qr_data,
            position={"x": x, "y": y, "width": w, "height": h}
        ))
    return result

def extract_text_ocr(image: Image.Image, page_num: int) -> OCRResult:
    custom_config = r'--oem 3 --psm 6'
    raw_text = pytesseract.image_to_string(image, config=custom_config).strip()
    
    # Format the text for better readability
    formatted_text = format_ocr_text(raw_text)
    
    try:
        data = pytesseract.image_to_data(image, output_type=pytesseract.Output.DICT, config=custom_config)
        confidences = [int(conf) for conf in data['conf'] if conf != '-1']
        avg_conf = sum(confidences) / len(confidences) if confidences else 0
        
        # Extract word-level details for better analysis
        word_details = extract_word_details(data)
    except:
        avg_conf = 0
        word_details = []
    
    return OCRResult(
        page=page_num, 
        text=formatted_text, 
        confidence=round(avg_conf, 1),
        raw_text=raw_text,
        word_count=len(formatted_text.split()),
        line_count=len([line for line in formatted_text.split('\n') if line.strip()]),
        word_details=word_details[:20]  # Limit to first 20 words for storage efficiency
    )

def convert_pdf_to_images(pdf_path: str, output_dir: str) -> List[str]:
    image_paths = []
    doc = fitz.open(pdf_path)
    for i, page in enumerate(doc):
        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
        path = os.path.join(output_dir, f"page_{i + 1}.png")
        pix.save(path)
        image_paths.append(path)
    return image_paths

def format_ocr_text(raw_text: str) -> str:
    """Format OCR text for better readability and structure."""
    if not raw_text.strip():
        return raw_text
    
    lines = raw_text.split('\n')
    formatted_lines = []
    
    for line in lines:
        # Clean up extra spaces and normalize
        cleaned = ' '.join(line.split())
        if cleaned:
            # Preserve important formatting patterns
            if any(keyword in cleaned.upper() for keyword in ['INVOICE', 'TOTAL', 'DATE', 'AMOUNT']):
                # Make important fields more prominent
                cleaned = cleaned.upper() if len(cleaned) < 50 else cleaned
            formatted_lines.append(cleaned)
    
    # Join with proper line breaks, removing excessive blank lines
    result = '\n'.join(formatted_lines)
    
    # Clean up multiple consecutive newlines
    while '\n\n\n' in result:
        result = result.replace('\n\n\n', '\n\n')
    
    return result.strip()

def extract_word_details(data: dict) -> List[Dict[str, Any]]:
    """Extract word-level details from Tesseract OCR data."""
    word_details = []
    
    for i in range(len(data['text'])):
        word = data['text'][i].strip()
        if word and data['conf'][i] != '-1':
            detail = {
                'word': word,
                'confidence': int(data['conf'][i]),
                'bbox': {
                    'left': data['left'][i],
                    'top': data['top'][i], 
                    'width': data['width'][i],
                    'height': data['height'][i]
                }
            }
            word_details.append(detail)
    
    # Sort by confidence descending and return top words
    word_details.sort(key=lambda x: x['confidence'], reverse=True)
    return word_details

def format_ocr_summary(ocr_results: List[OCRResult]) -> Dict[str, Any]:
    """Create a formatted summary of OCR results."""
    if not ocr_results:
        return {"summary": "No OCR data available"}
    
    total_confidence = sum(result.confidence for result in ocr_results) / len(ocr_results)
    total_words = sum(result.word_count or 0 for result in ocr_results)
    total_lines = sum(result.line_count or 0 for result in ocr_results)
    
    # Get best and worst confidence pages
    best_page = max(ocr_results, key=lambda x: x.confidence)
    worst_page = min(ocr_results, key=lambda x: x.confidence)
    
    # Extract key text snippets (first 100 chars from each page)
    text_snippets = []
    for result in ocr_results:
        snippet = result.text[:100] + "..." if len(result.text) > 100 else result.text
        text_snippets.append(f"Page {result.page}: {snippet}")
    
    return {
        "pages_processed": len(ocr_results),
        "average_confidence": round(total_confidence, 1),
        "total_words_extracted": total_words,
        "total_lines_extracted": total_lines,
        "best_quality_page": {"page": best_page.page, "confidence": best_page.confidence},
        "worst_quality_page": {"page": worst_page.page, "confidence": worst_page.confidence},
        "text_preview": text_snippets,
        "quality_assessment": (
            "Excellent" if total_confidence >= 90 else
            "Good" if total_confidence >= 75 else
            "Fair" if total_confidence >= 60 else
            "Poor"
        )
    }

# ----------------------- Background Processor ----------------------

async def update_dynamodb(document_id: str, updates: Dict[str, Any]):
    table = dynamodb.Table(DYNAMODB_TABLE_NAME)
    
    # Build expression parts
    set_expressions = []
    names = {}
    values = {}
    
    # Debug logging
    logger.info(f"Updating DynamoDB for document {document_id} with updates: {updates}")
    
    # Handle each update field
    for k, v in updates.items():
        if k == "status":
            # Use ExpressionAttributeNames for reserved keyword 'status'
            set_expressions.append("#status = :status")
            names["#status"] = "status"
            values[":status"] = v
        else:
            # Regular fields
            set_expressions.append(f"{k} = :{k}")
            values[f":{k}"] = v
    
    # Add last_updated timestamp
    set_expressions.append("last_updated = :last_updated")
    values[":last_updated"] = datetime.utcnow().isoformat()
    
    # Build final expression
    expression = "SET " + ", ".join(set_expressions)
    
    # Debug logging
    logger.info(f"UpdateExpression: {expression}")
    logger.info(f"ExpressionAttributeNames: {names}")
    logger.info(f"ExpressionAttributeValues keys: {list(values.keys())}")
    
    # Update item
    update_params = {
        "Key": {"id": document_id},
        "UpdateExpression": expression,
        "ExpressionAttributeValues": convert_float_to_decimal(values)
    }
    
    # Only add ExpressionAttributeNames if we have any
    if names:
        update_params["ExpressionAttributeNames"] = names
        logger.info("Added ExpressionAttributeNames to update_params")
    else:
        logger.info("No ExpressionAttributeNames needed")
    
    try:
        table.update_item(**update_params)
        logger.info(f"Successfully updated DynamoDB for document {document_id}")
    except Exception as e:
        logger.error(f"DynamoDB update failed for document {document_id}: {str(e)}")
        raise

async def process_document_background(record: DynamoDBRecord):
    try:
        await update_dynamodb(record.document_id, {"status": "processing", "current_step": "downloading"})

        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = os.path.join(tmpdir, os.path.basename(record.key))
            s3_client.download_file(record.bucket, record.key, file_path)

            if record.file_type == "pdf":
                image_paths = convert_pdf_to_images(file_path, tmpdir)
            elif record.file_type == "image":
                image_paths = [file_path]
            else:
                raise ValueError("Unsupported file type")

            qr_codes, ocr_results, all_text = [], [], ""
            for i, path in enumerate(image_paths):
                image = Image.open(path)
                qr_codes += extract_qr_codes(image, i + 1)
                ocr = extract_text_ocr(image, i + 1)
                ocr_results.append(ocr)
                all_text += "\n" + ocr.text

            await update_dynamodb(record.document_id, {"current_step": "validating"})

            invoice_fields = extract_invoice_fields(all_text)
            qr_data_list = [qr.data for qr in qr_codes]
            valid_links, invalid_links = check_qr_links(qr_data_list, invoice_fields)
            score = 80 if invoice_fields.get("Invoice Number") != "Not found" else 40

            # Create OCR summary for better presentation
            ocr_summary = format_ocr_summary(ocr_results)

            result = ProcessingResult(
                document_id=record.document_id,
                status="completed" if score >= 50 else "failed",
                qr_codes=qr_codes,
                ocr_results=ocr_results,
                validation_score=score,
                errors=[] if score >= 50 else ["Missing Invoice Number"],
                processed_date=datetime.utcnow().isoformat(),
                invoice_fields=invoice_fields,
                validated_qr_links=valid_links,
                invalid_qr_links=invalid_links,
                ocr_summary=ocr_summary
            )

            await update_dynamodb(record.document_id, {
                "status": result.status,
                "qr_codes": [q.dict() for q in result.qr_codes],
                "ocr_results": [o.dict() for o in result.ocr_results],
                "ocr_summary": result.ocr_summary,
                "validation_score": result.validation_score,
                "validation_errors": result.errors,
                "processed_date": result.processed_date,
                "invoice_fields": result.invoice_fields,
                "validated_qr_links": result.validated_qr_links,
                "invalid_qr_links": result.invalid_qr_links,
                "ocr_summary": result.ocr_summary  # Save summary to DB
            })

    except Exception as e:
        logger.error(f"Error processing {record.document_id}: {e}")
        await update_dynamodb(record.document_id, {
            "status": "failed",
            "error": str(e),
            "processed_date": datetime.utcnow().isoformat()
        })

# ----------------------------- API Routes -----------------------------

@app.post("/process")
async def process_document(request: ProcessingRequest, background_tasks: BackgroundTasks):
    record = request.record
    if record.status != "pending":
        raise HTTPException(status_code=400, detail="Document status must be 'pending'")
    background_tasks.add_task(process_document_background, record)
    return {"message": "Processing started", "document_id": record.document_id}

@app.get("/status/{document_id}")
async def get_status(document_id: str):
    table = dynamodb.Table(DYNAMODB_TABLE_NAME)
    response = table.get_item(Key={"id": document_id})
    if "Item" not in response:
        raise HTTPException(status_code=404, detail="Document not found")
    return response["Item"]

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "hybrid-document-processor"}
