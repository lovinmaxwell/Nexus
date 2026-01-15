# Domain

Domain layer containing business entities and protocols.

## Structure

| Folder | Purpose |
|--------|---------|
| `Models/` | SwiftData entities and value objects |
| `Protocols/` | Abstract interfaces for dependency inversion |

## Models

Core data models persisted via SwiftData:
- `DownloadTask` - Represents a download with segments
- `FileSegment` - Individual segment of a download
- `DownloadQueue` - Named queue with concurrent limits

## Design Principles

- Models are PODs (Plain Old Data) with minimal logic
- Business rules live in the Application layer
- Protocols define contracts for external dependencies
