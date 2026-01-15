# Nexus Development Guidelines

## Architecture Pattern: Clean Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Presentation Layer                    │
│              (UI, Views, ViewModels)                     │
├─────────────────────────────────────────────────────────┤
│                    Application Layer                     │
│         (Use Cases, Managers, Coordinators)              │
├─────────────────────────────────────────────────────────┤
│                      Domain Layer                        │
│            (Entities, Protocols, Value Objects)          │
├─────────────────────────────────────────────────────────┤
│                   Infrastructure Layer                   │
│        (Network, Storage, External Services)             │
└─────────────────────────────────────────────────────────┘
```

## Folder Structure

```
Sources/
├── NexusApp/
│   ├── App/              # App entry point, configuration
│   ├── Core/             # Application layer (managers, coordinators)
│   │   ├── Network/      # Network handlers, protocols
│   │   └── Storage/      # File handlers, persistence
│   ├── Domain/           # Domain layer (entities, protocols)
│   │   ├── Models/       # Data models (SwiftData entities)
│   │   └── Protocols/    # Abstract interfaces
│   ├── Presentation/     # Presentation layer
│   │   ├── Views/        # SwiftUI views
│   │   ├── ViewModels/   # View models (if needed)
│   │   └── Components/   # Reusable UI components
│   ├── Utilities/        # Helper classes, extensions
│   └── Resources/        # Assets, localization
├── NexusHost/            # Native Messaging Host binary
BrowserExtensions/
├── Chrome/               # Chrome extension
├── Firefox/              # Firefox extension
└── Safari/               # Safari Web Extension
```

## Code Standards

### 1. Documentation
Every public class, struct, enum, and function MUST have documentation:

```swift
/// Downloads a file segment from a remote URL.
///
/// This method handles HTTP range requests and supports resume capability.
///
/// - Parameters:
///   - url: The source URL to download from
///   - start: Starting byte offset
///   - end: Ending byte offset
/// - Returns: An async stream of data chunks
/// - Throws: `NetworkError` if the connection fails
func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<Data, Error>
```

### 2. Naming Conventions
- **Classes/Structs**: PascalCase (`DownloadManager`, `FileSegment`)
- **Functions/Variables**: camelCase (`startDownload`, `totalSize`)
- **Constants**: camelCase (`maxConnections`)
- **Protocols**: PascalCase with descriptive name (`NetworkHandler`, `Downloadable`)
- **Enums**: PascalCase, cases in camelCase (`TaskStatus.running`)

### 3. File Organization
Each file should follow this order:
1. Imports
2. Documentation comment
3. Type definition
4. Properties (static, then instance)
5. Initializers
6. Public methods
7. Private methods
8. Extensions

### 4. SOLID Principles
- **S**ingle Responsibility: Each class has one job
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable
- **I**nterface Segregation: Many specific protocols over one general
- **D**ependency Inversion: Depend on abstractions, not concretions

### 5. Error Handling
- Use typed errors (enums conforming to `Error`)
- Provide meaningful error messages
- Handle all error cases explicitly

```swift
enum DownloadError: Error, LocalizedError {
    case invalidURL
    case connectionFailed(underlying: Error)
    case serverError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The URL is invalid"
        case .connectionFailed(let error): return "Connection failed: \(error.localizedDescription)"
        case .serverError(let code): return "Server returned error: \(code)"
        }
    }
}
```

### 6. Concurrency
- Use Swift's structured concurrency (`async/await`, `Task`, `TaskGroup`)
- Use `actor` for shared mutable state
- Mark main-thread code with `@MainActor`

### 7. Testing
- Write unit tests for all business logic
- Use descriptive test names: `test_downloadManager_startsDownload_whenURLIsValid`
- Mock external dependencies

## Code Review Checklist
- [ ] Documentation present for public APIs
- [ ] Follows naming conventions
- [ ] No force unwraps (`!`) without justification
- [ ] Error cases handled
- [ ] No commented-out code
- [ ] Tests added/updated
- [ ] No hardcoded strings (use constants)
- [ ] Accessibility considered for UI

## Git Commit Messages
```
<type>(<scope>): <subject>

Types: feat, fix, docs, style, refactor, test, chore
Example: feat(download): add FTP protocol support
```
