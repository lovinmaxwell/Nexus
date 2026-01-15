# Utilities

Helper classes, extensions, and shared utilities.

## Files

| File | Purpose |
|------|---------|
| `TokenBucket.swift` | Rate limiting algorithm for speed control |
| `MediaExtractor.swift` | yt-dlp integration for media URL extraction |
| `Extensions.swift` | Swift standard library extensions |

## TokenBucket

Implements token bucket algorithm for bandwidth limiting:
- Configurable rate (bytes/second)
- Burst allowance
- Thread-safe consumption

## MediaExtractor

Wraps yt-dlp for extracting media URLs:
- YouTube video/audio extraction
- Format selection
- Metadata retrieval
