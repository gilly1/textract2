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

    fields = {
        "Invoice Number": find(r'INVOICE\s*(?:NO|NUMBER)[:\s]+([A-Z0-9/]+)', re.IGNORECASE),
        "Invoice Date": find(r'Date\s*:\s*([0-9]{2}/[0-9]{2}/[0-9]{4})'),
        "Total Amount Due": find(r'Total\s*KSh\s*([\d,\.]+)'),
        "Currency": "KES" if "KSh" in text or "KES" in text else "Not found",
        "Purchase Order Number": find(r'Purchase Order Number\s*[:\-]?\s*([A-Z0-9\-]+)', re.IGNORECASE)
    }
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
    text = pytesseract.image_to_string(image, config=custom_config).strip()
    
    try:
        data = pytesseract.image_to_data(image, output_type=pytesseract.Output.DICT, config=custom_config)
        confidences = [int(conf) for conf in data['conf'] if conf != '-1']
        avg_conf = sum(confidences) / len(confidences) if confidences else 0
    except:
        avg_conf = 0
    
    return OCRResult(page=page_num, text=text, confidence=round(avg_conf, 1))

def convert_pdf_to_images(pdf_path: str, output_dir: str) -> List[str]:
    image_paths = []
    doc = fitz.open(pdf_path)
    for i, page in enumerate(doc):
        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
        path = os.path.join(output_dir, f"page_{i + 1}.png")
        pix.save(path)
        image_paths.append(path)
    return image_paths

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
                invalid_qr_links=invalid_links
            )

            await update_dynamodb(record.document_id, {
                "status": result.status,
                "qr_codes": [q.dict() for q in result.qr_codes],
                "ocr_results": [o.dict() for o in result.ocr_results],
                "validation_score": result.validation_score,
                "validation_errors": result.errors,
                "processed_date": result.processed_date,
                "invoice_fields": result.invoice_fields,
                "validated_qr_links": result.validated_qr_links,
                "invalid_qr_links": result.invalid_qr_links
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
