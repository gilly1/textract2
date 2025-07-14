// Example of how to use the new DynamoDB schema with the save_file_metadata function

// JavaScript function that matches your requirement
export const saveFileMetadata = async (fileData) => {
  const item = {
    fileId: fileData.fileKey, // Partition key
    uploadedBy: fileData.uploadedBy || 'anonymous', // Sort key
    fileName: fileData.fileName,
    fileType: fileData.fileType,
    fileSize: fileData.fileSize,
    s3Key: fileData.fileKey,
    s3Url: fileData.url,
    uploadDate: new Date().toISOString(),
    status: 'UPLOADED',
    metadata: fileData.metadata || {}
  };

  // Call the new API endpoint
  try {
    const response = await fetch('/files/metadata', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fileData)
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const result = await response.json();
    console.log('File metadata saved:', result);
    return result;
  } catch (error) {
    console.error('Error saving file metadata:', error);
    throw error;
  }
};

// Example usage:
const exampleFileData = {
  fileKey: 'invoice-2025-001',
  uploadedBy: 'user123',
  fileName: 'invoice.pdf',
  fileType: 'pdf',
  fileSize: 2048576,
  url: 'https://s3.amazonaws.com/bucket/invoice-2025-001.pdf',
  metadata: {
    department: 'finance',
    priority: 'high'
  }
};

// Save the metadata
saveFileMetadata(exampleFileData)
  .then(result => console.log('Success:', result))
  .catch(error => console.error('Error:', error));

// Additional API usage examples:

// Get file status
async function getFileStatus(fileId, uploadedBy = 'system') {
  const response = await fetch(`/status/${fileId}/${uploadedBy}`);
  return response.json();
}

// Get all files for a user
async function getUserFiles(uploadedBy) {
  const response = await fetch(`/files/${uploadedBy}`);
  return response.json();
}

// Get all files with specific status
async function getFilesByStatus(status) {
  const response = await fetch(`/files/status/${status}`);
  return response.json();
}

// Process a document (existing functionality with new schema support)
async function processDocument(fileData) {
  const record = {
    fileId: fileData.fileKey,
    uploadedBy: fileData.uploadedBy || 'anonymous',
    fileName: fileData.fileName,
    fileType: fileData.fileType,
    fileSize: fileData.fileSize,
    s3Key: fileData.fileKey,
    s3Url: fileData.url,
    uploadDate: fileData.uploadDate || new Date().toISOString(),
    status: 'pending',
    metadata: fileData.metadata || {},
    // Legacy support fields
    document_id: fileData.fileKey,
    bucket: fileData.bucket || 'default-bucket',
    key: fileData.fileKey,
    file_type: fileData.fileType,
    upload_date: fileData.uploadDate
  };

  const response = await fetch('/process', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ record })
  });

  return response.json();
}
