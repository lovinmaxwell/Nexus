# Protocols

Abstract interfaces for dependency inversion.

## Purpose

Protocols define contracts that:
- Enable dependency injection
- Facilitate unit testing with mocks
- Decouple layers of the architecture

## Protocols

### NetworkHandler
Defines network operations for any protocol:
```swift
protocol NetworkHandler {
    func headRequest(url: URL) async throws -> (contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?)
    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<Data, Error>
}
```

### Future Protocols
- `StorageHandler` - File system operations
- `MediaExtractor` - Media URL extraction
- `QueueScheduler` - Download scheduling
