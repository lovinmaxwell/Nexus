# NexusApp

Main application target for Nexus Download Manager.

## Structure

| Folder | Purpose |
|--------|---------|
| `App/` | Application entry point, configuration, lifecycle |
| `Core/` | Business logic, managers, coordinators |
| `Domain/` | Data models, protocols, value objects |
| `Presentation/` | SwiftUI views and UI components |
| `Utilities/` | Helper classes, extensions |

## Key Files

- `NexusApp.swift` - App entry point with SwiftData configuration
- `Core/DownloadManager.swift` - Central download coordinator
- `Core/TaskCoordinator.swift` - Individual download orchestration
- `Domain/Models/DownloadTask.swift` - Download entity model
