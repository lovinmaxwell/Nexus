# Models

SwiftData entity models for persistence.

## Entities

### DownloadTask
Primary download entity containing:
- Source URL and destination path
- Total file size
- Status (paused, running, complete, error)
- ETag and Last-Modified for validation
- Relationship to FileSegments and DownloadQueue

### FileSegment
Individual segment of a download:
- Byte range (startOffset, endOffset)
- Downloaded bytes count
- Completion status
- Parent DownloadTask relationship

### DownloadQueue
Named queue for organizing downloads:
- Queue name and creation date
- Max concurrent downloads limit
- Active status
- Collection of DownloadTasks
