import json
import os
import boto3
import requests
import logging
from typing import Dict, Any

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
ECS_SERVICE_URL = os.getenv('ECS_SERVICE_URL')  # ALB URL for ECS service
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')  # AWS automatically provides AWS_REGION

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Lambda function triggered by DynamoDB stream on INSERT events.
    Calls the FastAPI /process endpoint for new documents.
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    processed_count = 0
    errors = []
    
    try:
        for record in event.get('Records', []):
            # Only process INSERT events
            if record['eventName'] != 'INSERT':
                logger.info(f"Skipping {record['eventName']} event")
                continue
            
            # Extract DynamoDB item data
            dynamodb_item = record['dynamodb']['NewImage']
            
            # Handle both old and new DynamoDB schema formats
            # New schema: fileId, uploadedBy, s3Key, fileType
            # Old schema: id, bucket, key, file_type
            
            if 'fileId' in dynamodb_item:
                # New schema format
                document_record = {
                    'fileId': dynamodb_item['fileId']['S'],
                    'uploadedBy': dynamodb_item['uploadedBy']['S'],
                    'fileName': dynamodb_item.get('fileName', {}).get('S', ''),
                    'fileType': dynamodb_item.get('fileType', {}).get('S', ''),
                    'fileSize': int(dynamodb_item.get('fileSize', {}).get('N', '0')) if 'fileSize' in dynamodb_item else None,
                    's3Key': dynamodb_item.get('s3Key', {}).get('S', ''),
                    's3Url': dynamodb_item.get('s3Url', {}).get('S', ''),
                    'uploadDate': dynamodb_item.get('uploadDate', {}).get('S', ''),
                    'status': dynamodb_item['status']['S'],
                    'metadata': dynamodb_item.get('metadata', {}).get('M', {})
                }
                
                # Extract bucket name from s3Key or s3Url for backward compatibility
                s3_key = document_record['s3Key']
                if document_record['s3Url']:
                    # Extract bucket from URL: https://bucket-name.s3.region.amazonaws.com/key
                    try:
                        import re
                        bucket_match = re.search(r'https://([^.]+)\.s3\.', document_record['s3Url'])
                        bucket = bucket_match.group(1) if bucket_match else 'document-processor-documents'
                    except:
                        bucket = 'document-processor-documents'
                else:
                    bucket = 'document-processor-documents'  # Default bucket
                
                # Add legacy fields for ECS compatibility
                document_record.update({
                    'document_id': document_record['fileId'],  # Map fileId to document_id
                    'bucket': bucket,
                    'key': s3_key,
                    'file_type': document_record['fileType'].split('/')[-1] if '/' in document_record['fileType'] else document_record['fileType'],
                    'upload_date': document_record['uploadDate']
                })
                
            else:
                # Old schema format (backward compatibility)
                document_record = {
                    'document_id': dynamodb_item['id']['S'],
                    'bucket': dynamodb_item['bucket']['S'],
                    'key': dynamodb_item['key']['S'],
                    'status': dynamodb_item['status']['S'],
                    'file_type': dynamodb_item['file_type']['S']
                }
                
                # Add upload_date if present
                if 'upload_date' in dynamodb_item:
                    document_record['upload_date'] = dynamodb_item['upload_date']['S']
                
                # Add new schema fields for compatibility
                document_record.update({
                    'fileId': document_record['document_id'],
                    'uploadedBy': 'system',  # Default for legacy records
                    'fileName': document_record['key'].split('/')[-1],
                    'fileType': document_record['file_type'],
                    's3Key': document_record['key'],
                    's3Url': f"https://{document_record['bucket']}.s3.{AWS_REGION}.amazonaws.com/{document_record['key']}",
                    'uploadDate': document_record.get('upload_date', '')
                })
            
            # Only process documents with 'pending' status
            if document_record['status'] != 'pending':
                file_id = document_record.get('fileId', document_record.get('document_id', 'unknown'))
                logger.info(f"Skipping document {file_id} with status: {document_record['status']}")
                continue
            
            # Call the FastAPI /process endpoint
            try:
                response = call_process_endpoint(document_record)
                file_id = document_record.get('fileId', document_record.get('document_id', 'unknown'))
                logger.info(f"Successfully triggered processing for document {file_id}")
                processed_count += 1
                
            except Exception as e:
                file_id = document_record.get('fileId', document_record.get('document_id', 'unknown'))
                error_msg = f"Failed to process document {file_id}: {str(e)}"
                logger.error(error_msg)
                errors.append(error_msg)
    
    except Exception as e:
        error_msg = f"Error processing DynamoDB stream event: {str(e)}"
        logger.error(error_msg)
        errors.append(error_msg)
    
    # Return processing summary
    result = {
        'statusCode': 200,
        'body': {
            'processed_documents': processed_count,
            'errors': errors,
            'total_records': len(event.get('Records', []))
        }
    }
    
    logger.info(f"Processing complete: {json.dumps(result)}")
    return result

def call_process_endpoint(document_record: Dict[str, Any]) -> Dict[str, Any]:
    """
    Call the FastAPI /process endpoint with the document record.
    """
    if not ECS_SERVICE_URL:
        raise ValueError("ECS_SERVICE_URL environment variable not set")
    
    # Prepare a clean record that matches the ECS DynamoDBRecord model exactly
    # All required fields: fileId, uploadedBy, fileName, fileType, s3Key, status
    clean_record = {
        'fileId': str(document_record['fileId']),  # Ensure string
        'uploadedBy': str(document_record['uploadedBy']),  # Ensure string
        'fileName': str(document_record.get('fileName', '')),  # Required, default to empty string
        'fileType': str(document_record.get('fileType', '')),  # Required, default to empty string
        's3Key': str(document_record.get('s3Key', '')),  # Required, ensure string
        'status': str(document_record['status']),  # Required, ensure string
    }
    
    # Add optional fields only if they have values (not None)
    file_size = document_record.get('fileSize')
    if file_size is not None:
        clean_record['fileSize'] = int(file_size)
    
    s3_url = document_record.get('s3Url')
    if s3_url:
        clean_record['s3Url'] = str(s3_url)
    
    upload_date = document_record.get('uploadDate')
    if upload_date:
        clean_record['uploadDate'] = str(upload_date)
    
    metadata = document_record.get('metadata')
    if metadata:
        clean_record['metadata'] = metadata
    
    # Legacy fields (optional) - only add if they have values
    document_id = document_record.get('document_id', document_record['fileId'])
    if document_id:
        clean_record['document_id'] = str(document_id)
    
    bucket = document_record.get('bucket')
    if bucket:
        clean_record['bucket'] = str(bucket)
    
    key = document_record.get('key', document_record.get('s3Key'))
    if key:
        clean_record['key'] = str(key)
    
    # The FastAPI endpoint expects a ProcessingRequest with a 'record' field
    # So we send the clean_record as the 'record' field
    payload = {
        'record': clean_record
    }
    
    # Make the HTTP request to the ECS service
    process_url = f"{ECS_SERVICE_URL.rstrip('/')}/process"
    
    logger.info(f"Calling process endpoint: {process_url}")
    logger.info(f"Payload structure: record with keys: {list(clean_record.keys())}")
    logger.info(f"Record fileId: {clean_record['fileId']}, s3Key: {clean_record['s3Key']}")
    
    headers = {
        'Content-Type': 'application/json'
    }
    
    try:
        response = requests.post(
            process_url,
            json=payload,
            headers=headers,
            timeout=30
        )
        
        logger.info(f"HTTP Status: {response.status_code}")
        
        if response.status_code == 422:
            logger.error(f"Validation error (422): {response.text}")
            logger.error(f"Sent payload: {json.dumps(payload, indent=2)}")
            
        response.raise_for_status()
        
        result = response.json()
        logger.info(f"Process endpoint response: {json.dumps(result)}")
        
        return result
        
    except requests.exceptions.HTTPError as e:
        logger.error(f"HTTP Error: {e}")
        logger.error(f"Response text: {response.text}")
        raise
    except Exception as e:
        logger.error(f"Request failed: {e}")
        raise
