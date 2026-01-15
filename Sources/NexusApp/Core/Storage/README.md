# Storage

File system operations and persistence handlers.

## Files

| File | Purpose |
|------|---------|
| `SparseFileHandler.swift` | APFS sparse file operations |
| `FileWriter.swift` | Thread-safe file writing actor |

## SparseFileHandler

Handles APFS sparse file operations for efficient disk usage:
- Pre-allocate file size via `truncate()`
- Write at arbitrary offsets without zero-fill
- Reduces disk I/O for segmented downloads

## FileWriter

Actor ensuring thread-safe concurrent writes:
- Sequential write ordering
- Error handling and recovery
- Automatic retry on transient failures
