# libcurl Integration for Turbo Mode

## Overview

libcurl provides granular control over TCP connections, enabling the "32-connection aggressive segmentation" feature that URLSession's high-level abstraction may suppress.

## Implementation Status

**Current:** URLSession-based downloads with configurable connection counts (1-32)

**Planned:** libcurl wrapper for Turbo Mode with:
- 32-connection aggressive segmentation
- TCP keep-alive configuration
- Connection pooling
- Protocol negotiation (HTTP/1.1 vs HTTP/2)

## Architecture

### Why libcurl?

1. **Granular Control:** Direct access to TCP connection parameters
2. **Connection Reuse:** Fine-tuned connection pooling without system coalescing
3. **Protocol Control:** Explicit HTTP/1.1 vs HTTP/2 negotiation
4. **Performance:** Lower-level optimizations for high-speed downloads

### Implementation Approach

1. **Swift Wrapper:** Create a Swift wrapper around libcurl C API
2. **Hybrid Mode:** Use URLSession for standard downloads, libcurl for Turbo Mode
3. **Connection Pool:** Maintain a pool of reusable TCP connections
4. **Segmentation:** Implement "In-Half" rule with libcurl's multi interface

## Dependencies

- libcurl (via Homebrew: `brew install curl`)
- Or bundle libcurl in app (requires static linking)

## Code Structure

```
Sources/NexusApp/Core/Network/
  - LibcurlHandler.swift (NetworkHandler protocol implementation)
  - LibcurlConnectionPool.swift (Connection management)
  - LibcurlTurboMode.swift (32-connection segmentation)
```

## Notes

- This is a future enhancement
- Current URLSession implementation provides good performance
- libcurl integration requires additional dependencies and complexity
- Consider user preference: "Turbo Mode" toggle in settings
