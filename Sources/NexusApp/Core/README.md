# Core

Application layer containing business logic and coordinators.

## Structure

| File/Folder | Purpose |
|-------------|---------|
| `Network/` | Protocol handlers (HTTP, FTP) |
| `Storage/` | File I/O, persistence |
| `DownloadManager.swift` | Central download coordinator singleton |
| `TaskCoordinator.swift` | Orchestrates individual downloads |
| `QueueManager.swift` | Queue management and scheduling |
| `BrowserExtensionListener.swift` | Handles browser extension requests |

## Key Classes

### DownloadManager
Singleton that coordinates all downloads. Responsibilities:
- Add/remove downloads
- Start/pause/resume downloads
- Manage download queues
- Interface with SwiftData

### TaskCoordinator
Manages a single download task. Responsibilities:
- Dynamic segment creation (In-Half algorithm)
- Concurrent connection management
- Progress tracking
- State persistence

### QueueManager
Manages download queues. Responsibilities:
- Queue creation/deletion
- Concurrent download limits per queue
- Auto-start pending downloads
