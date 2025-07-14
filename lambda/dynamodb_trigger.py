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
AWS_REGION = os.getenv('AWS_DEFAULT_REGION', 'us-east-1')

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
            
            # Convert DynamoDB item to our expected format
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
            
            # Only process documents with 'pending' status
            if document_record['status'] != 'pending':
                logger.info(f"Skipping document {document_record['document_id']} with status: {document_record['status']}")
                continue
            
            # Call the FastAPI /process endpoint
            try:
                response = call_process_endpoint(document_record)
                logger.info(f"Successfully triggered processing for document {document_record['document_id']}")
                processed_count += 1
                
            except Exception as e:
                error_msg = f"Failed to process document {document_record['document_id']}: {str(e)}"
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
    
    # Prepare the request payload
    payload = {
        'record': document_record
    }
    
    # Make the HTTP request to the ECS service
    process_url = f"{ECS_SERVICE_URL.rstrip('/')}/process"
    
    logger.info(f"Calling process endpoint: {process_url}")
    logger.info(f"Payload: {json.dumps(payload)}")
    
    headers = {
        'Content-Type': 'application/json'
    }
    
    response = requests.post(
        process_url,
        json=payload,
        headers=headers,
        timeout=30
    )
    
    response.raise_for_status()
    
    result = response.json()
    logger.info(f"Process endpoint response: {json.dumps(result)}")
    
    return result
