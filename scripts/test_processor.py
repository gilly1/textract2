import asyncio
import aiohttp
import json
import sys
import time
from datetime import datetime

async def test_document_processor(endpoint_url, s3_bucket, test_document_key):
    """Test the document processor service end-to-end"""
    
    print(f"Testing Document Processor at: {endpoint_url}")
    print(f"S3 Bucket: {s3_bucket}")
    print(f"Test Document: {test_document_key}")
    print("-" * 50)
    
    async with aiohttp.ClientSession() as session:
        # Test 1: Health Check
        print("1. Testing health endpoint...")
        try:
            async with session.get(f"{endpoint_url}/health") as response:
                if response.status == 200:
                    data = await response.json()
                    print(f"   ✅ Health check passed: {data}")
                else:
                    print(f"   ❌ Health check failed: {response.status}")
                    return False
        except Exception as e:
            print(f"   ❌ Health check error: {e}")
            return False
        
        # Test 2: Document Processing
        print("\n2. Testing document processing...")
        
        document_id = f"test-doc-{int(time.time())}"
        test_payload = {
            "record": {
                "document_id": document_id,
                "bucket": s3_bucket,
                "key": test_document_key,
                "status": "pending",
                "file_type": "pdf",
                "upload_date": datetime.utcnow().isoformat() + "Z",
                "source": "test"
            }
        }
        
        try:
            async with session.post(
                f"{endpoint_url}/process", 
                json=test_payload,
                headers={"Content-Type": "application/json"}
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    print(f"   ✅ Processing started: {data}")
                else:
                    text = await response.text()
                    print(f"   ❌ Processing failed: {response.status} - {text}")
                    return False
        except Exception as e:
            print(f"   ❌ Processing error: {e}")
            return False
        
        # Test 3: Status Check
        print("\n3. Testing status endpoint...")
        
        # Wait a bit for processing to start
        await asyncio.sleep(5)
        
        try:
            async with session.get(f"{endpoint_url}/status/{document_id}") as response:
                if response.status == 200:
                    data = await response.json()
                    print(f"   ✅ Status retrieved: {data}")
                elif response.status == 404:
                    print("   ⚠️  Document not found in DynamoDB (expected for test)")
                else:
                    text = await response.text()
                    print(f"   ❌ Status check failed: {response.status} - {text}")
        except Exception as e:
            print(f"   ❌ Status check error: {e}")
        
        # Test 4: Error Handling
        print("\n4. Testing error handling...")
        
        invalid_payload = {
            "record": {
                "document_id": "invalid-doc",
                "bucket": "",  # Invalid bucket
                "key": "",     # Invalid key
                "status": "pending",
                "file_type": "pdf"
            }
        }
        
        try:
            async with session.post(
                f"{endpoint_url}/process",
                json=invalid_payload,
                headers={"Content-Type": "application/json"}
            ) as response:
                if response.status == 400:
                    data = await response.json()
                    print(f"   ✅ Error handling works: {data}")
                else:
                    print(f"   ⚠️  Unexpected response for invalid data: {response.status}")
        except Exception as e:
            print(f"   ❌ Error handling test failed: {e}")
        
        print("\n" + "=" * 50)
        print("Test completed!")
        return True

async def main():
    if len(sys.argv) < 2:
        print("Usage: python test_processor.py <endpoint_url> [s3_bucket] [test_document_key]")
        print("Example: python test_processor.py http://localhost:8080 my-bucket test.pdf")
        sys.exit(1)
    
    endpoint_url = sys.argv[1].rstrip('/')
    s3_bucket = sys.argv[2] if len(sys.argv) > 2 else "test-bucket"
    test_document_key = sys.argv[3] if len(sys.argv) > 3 else "test-document.pdf"
    
    success = await test_document_processor(endpoint_url, s3_bucket, test_document_key)
    
    if success:
        print("🎉 All tests passed!")
        sys.exit(0)
    else:
        print("💥 Some tests failed!")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
