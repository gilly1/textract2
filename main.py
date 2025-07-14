from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
import boto3
import pytesseract
import fitz  # PyMuPDF
from pyzbar import pyzbar
import cv2
import numpy as np
from PIL import Image
import io
import tempfile
import uuid
import json
import os
from datetime import datetime
from typing import List, Dict, Any, Optional
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Document Processor Service", version="1.0.0")

# Configuration from environment variables
AWS_REGION = os.getenv('AWS_DEFAULT_REGION', 'us-east-1')
DYNAMODB_TABLE_NAME = os.getenv('DYNAMODB_TABLE_NAME', 'document-processor-results')

# AWS clients
s3_client = boto3.client('s3', region_name=AWS_REGION)
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)

# Pydantic models
class DynamoDBRecord(BaseModel):
    document_id: str
    bucket: str
    key: str
    status: str
    file_type: str
    upload_date: Optional[str] = None
    processed_date: Optional[str] = None
    source: Optional[str] = None

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

@app.post("/process")
async def process_document(request: ProcessingRequest, background_tasks: BackgroundTasks):
    """
    Process a document based on DynamoDB record
    Accepts a DynamoDB record and processes the referenced document in S3
    """
    record = request.record
    
    # Validate the record
    if record.status != "pending":
        raise HTTPException(status_code=400, detail="Document status must be 'pending'")
    
    if not all([record.bucket, record.key, record.document_id]):
        raise HTTPException(status_code=400, detail="Missing required fields: bucket, key, document_id")
    
    # Start background processing
    background_tasks.add_task(process_document_background, record)
    
    return {
        "message": "Document processing started",
        "document_id": record.document_id,
        "status": "processing"
    }

async def process_document_background(record: DynamoDBRecord):
    """Background task to process the document"""
    try:
        # Update status to processing
        await update_dynamodb_status(record.document_id, "processing", {"current_step": "downloading"})
        
        # Download and process document
        with tempfile.TemporaryDirectory() as temp_dir:
            # Download file from S3
            file_extension = record.key.split('.')[-1].lower()
            file_path = f"{temp_dir}/document.{file_extension}"
            s3_client.download_file(record.bucket, record.key, file_path)
            
            # Process based on file type
            if record.file_type == "pdf":
                # Convert PDF to images
                await update_dynamodb_status(record.document_id, "processing", {"current_step": "converting"})
                images = convert_pdf_to_images(file_path, temp_dir)
            elif record.file_type == "image":
                # Process image directly
                await update_dynamodb_status(record.document_id, "processing", {"current_step": "processing_image"})
                images = [file_path]  # Process the image file directly
            else:
                raise ValueError(f"Unsupported file type: {record.file_type}")
            
            # Process each image
            await update_dynamodb_status(record.document_id, "processing", {"current_step": "extracting"})
            qr_codes = []
            ocr_results = []
            
            for i, image_path in enumerate(images):
                page_num = i + 1
                
                # QR Code extraction
                page_qr_codes = extract_qr_codes(image_path, page_num)
                qr_codes.extend(page_qr_codes)
                
                # OCR text extraction
                ocr_result = extract_text_ocr(image_path, page_num)
                ocr_results.append(ocr_result)
            
            # Validation
            await update_dynamodb_status(record.document_id, "processing", {"current_step": "validating"})
            validation_result = validate_extraction_data(qr_codes, ocr_results)
            
            # Prepare final result
            result = ProcessingResult(
                document_id=record.document_id,
                status="completed" if validation_result["score"] >= 50 else "failed",
                qr_codes=qr_codes,
                ocr_results=ocr_results,
                validation_score=validation_result["score"],
                errors=validation_result["errors"],
                processed_date=datetime.utcnow().isoformat()
            )
            
            # Update DynamoDB with final results
            await update_dynamodb_final_result(result)
            
    except Exception as e:
        logger.error(f"Error processing document {record.document_id}: {str(e)}")
        await update_dynamodb_status(
            record.document_id, 
            "failed", 
            {"error": str(e), "processed_date": datetime.utcnow().isoformat()}
        )

def convert_pdf_to_images(pdf_path: str, output_dir: str) -> List[str]:
    """Convert PDF pages to images"""
    image_paths = []
    
    try:
        doc = fitz.open(pdf_path)
        
        for page_num in range(len(doc)):
            page = doc.load_page(page_num)
            
            # Render page to image
            mat = fitz.Matrix(2.0, 2.0)  # 2x zoom for better quality
            pix = page.get_pixmap(matrix=mat)
            
            # Save as PNG
            image_path = f"{output_dir}/page_{page_num + 1}.png"
            pix.save(image_path)
            image_paths.append(image_path)
        
        doc.close()
        
    except Exception as e:
        logger.error(f"Error converting PDF to images: {str(e)}")
        raise
    
    return image_paths

def extract_qr_codes(image_path: str, page_num: int) -> List[QRCode]:
    """Extract QR codes from an image"""
    qr_codes = []
    
    try:
        # Load image
        image = cv2.imread(image_path)
        if image is None:
            return qr_codes
        
        # Convert to grayscale
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Detect QR codes
        decoded_objects = pyzbar.decode(gray)
        
        for obj in decoded_objects:
            qr_data = obj.data.decode('utf-8')
            x, y, w, h = obj.rect
            
            qr_code = QRCode(
                page=page_num,
                data=qr_data,
                position={"x": x, "y": y, "width": w, "height": h}
            )
            qr_codes.append(qr_code)
            
    except Exception as e:
        logger.error(f"Error extracting QR codes from page {page_num}: {str(e)}")
    
    return qr_codes

def extract_text_ocr(image_path: str, page_num: int) -> OCRResult:
    """Extract text from an image using OCR"""
    try:
        # Load image
        image = Image.open(image_path)
        
        # Configure tesseract
        custom_config = r'--oem 3 --psm 6'
        
        # Extract text
        extracted_text = pytesseract.image_to_string(image, config=custom_config).strip()
        
        # Get confidence score
        try:
            data = pytesseract.image_to_data(
                image, 
                output_type=pytesseract.Output.DICT,
                config=custom_config
            )
            confidences = [int(conf) for conf in data['conf'] if int(conf) > 0]
            avg_confidence = sum(confidences) / len(confidences) if confidences else 0
        except:
            avg_confidence = 0
        
        return OCRResult(
            page=page_num,
            text=extracted_text,
            confidence=round(avg_confidence, 1)
        )
        
    except Exception as e:
        logger.error(f"Error extracting text from page {page_num}: {str(e)}")
        return OCRResult(page=page_num, text="", confidence=0.0)

def validate_extraction_data(qr_codes: List[QRCode], ocr_results: List[OCRResult]) -> Dict[str, Any]:
    """Validate extracted data and calculate score"""
    errors = []
    score = 0
    
    # Validate QR codes
    if qr_codes:
        score += 30
        for qr in qr_codes:
            if len(qr.data) > 10:
                score += 10
    else:
        errors.append("No QR codes detected")
    
    # Validate OCR results
    all_text = " ".join([ocr.text for ocr in ocr_results if ocr.text])
    avg_confidence = sum([ocr.confidence for ocr in ocr_results]) / len(ocr_results) if ocr_results else 0
    
    if all_text and len(all_text.strip()) > 0:
        score += 20
        
        if avg_confidence > 70:
            score += 20
        elif avg_confidence > 50:
            score += 10
        else:
            errors.append(f"Low OCR confidence: {avg_confidence:.1f}%")
        
        if len(all_text.strip()) > 50:
            score += 10
    else:
        errors.append("No text extracted")
    
    # Business logic validation
    if all_text:
        required_patterns = ['date', 'amount', 'total', 'invoice']
        found_patterns = [pattern for pattern in required_patterns 
                         if pattern.lower() in all_text.lower()]
        
        if found_patterns:
            score += len(found_patterns) * 5
        else:
            errors.append("Missing required document patterns")
    
    return {
        "score": min(score, 100),
        "errors": errors
    }

async def update_dynamodb_status(document_id: str, status: str, additional_data: Dict = None):
    """Update document status in DynamoDB"""
    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        
        update_data = {
            "status": status,
            "last_updated": datetime.utcnow().isoformat()
        }
        
        if additional_data:
            update_data.update(additional_data)
        
        # Build update expression
        update_expression = "SET "
        expression_values = {}
        
        for key, value in update_data.items():
            update_expression += f"{key} = :{key}, "
            expression_values[f":{key}"] = value
        
        update_expression = update_expression.rstrip(", ")
        
        table.update_item(
            Key={"document_id": document_id},
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_values
        )
        
    except Exception as e:
        logger.error(f"Error updating DynamoDB status: {str(e)}")

async def update_dynamodb_final_result(result: ProcessingResult):
    """Update DynamoDB with final processing results"""
    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        
        table.update_item(
            Key={"document_id": result.document_id},
            UpdateExpression="""
                SET #status = :status,
                    qr_codes = :qr_codes,
                    ocr_results = :ocr_results,
                    validation_score = :validation_score,
                    validation_errors = :errors,
                    processed_date = :processed_date,
                    last_updated = :last_updated
            """,
            ExpressionAttributeNames={
                "#status": "status"
            },
            ExpressionAttributeValues={
                ":status": result.status,
                ":qr_codes": [qr.dict() for qr in result.qr_codes],
                ":ocr_results": [ocr.dict() for ocr in result.ocr_results],
                ":validation_score": result.validation_score,
                ":errors": result.errors,
                ":processed_date": result.processed_date,
                ":last_updated": datetime.utcnow().isoformat()
            }
        )
        
    except Exception as e:
        logger.error(f"Error updating final result in DynamoDB: {str(e)}")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "document-processor"}

@app.get("/status/{document_id}")
async def get_document_status(document_id: str):
    """Get processing status of a document"""
    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        
        response = table.get_item(Key={"document_id": document_id})
        
        if "Item" not in response:
            raise HTTPException(status_code=404, detail="Document not found")
        
        return response["Item"]
        
    except Exception as e:
        logger.error(f"Error getting document status: {str(e)}")
        raise HTTPException(status_code=500, detail="Error retrieving document status")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
