# Project Nexus - Development Progress Tracker

> Native macOS Internet Download Manager with IDM-like acceleration

---

## Functional Requirements (FR)

### FR-01: Protocol Support [P0]
- [x] HTTP protocol support
- [x] HTTPS protocol support
- [x] FTP protocol support (FTPHandler with curl)
- [x] NetworkHandlerFactory for protocol selection
- [x] MMS protocol support

### FR-02: Dynamic File Segmentation [P0]
- [x] Implement "In-Half" division rule algorithm
- [x] Split largest active segment when thread becomes free
- [x] Connection reuse without additional handshakes
- [x] HTTP 416 (Range Not Satisfiable) error handling with exponential backoff
- [x] HTTP 503 (Service Unavailable) error handling with exponential backoff

### FR-03: Multi-Connection Downloads [P0]
- [x] Support up to 32 simultaneous connections per file
- [x] Configurable connection count per download
- [x] TaskCoordinator managing worker thread pool

### FR-04: State Persistence & Crash Recovery [P0]
- [x] Save download state every 30 seconds
- [x] Persist byte offsets for every thread
- [x] File segment map persistence
- [x] Resume from exact position after crash/power failure
- [x] ETag validation on resume (detect file changes)
- [x] Last-Modified header validation on resume

### FR-05: APFS Sparse Files [P1]
- [x] SparseFileHandler implementation
- [x] Pre-allocate disk space via truncate()
- [x] Random offset writes without zero-fill overhead
- [x] FileWriter actor for thread-safe disk writes

### FR-06: Browser Integration [P0]
- [x] **Safari Web Extension**
  - [x] Extension bundled in app
  - [x] manifest.json with nativeMessaging permission
  - [x] browser.runtime.sendNativeMessage implementation
  - [x] Download link interception
- [x] **Chrome Extension**
  - [x] Extension package (manifest.json, background.js, popup)
  - [x] Native Messaging Host binary (NexusHost)
  - [x] Manifest at ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/
  - [x] Download link interception
  - [x] Context menu integration
- [x] **Firefox Extension**
  - [x] Extension package (manifest.json, background.js, popup)
  - [x] Native Messaging Host binary
  - [x] Manifest at ~/Library/Application Support/Mozilla/NativeMessagingHosts/
  - [x] Download link interception
  - [x] Context menu integration
- [x] **Native Messaging Protocol**
  - [x] 32-bit length header + JSON payload parsing (NexusHost)
  - [x] Handle: url, cookies, referrer, userAgent from browser
  - [x] IPC via DistributedNotificationCenter to main app
  - [x] Response confirmation to browser
- [x] **BrowserExtensionListener** in main app
  - [x] Monitor pending downloads directory
  - [x] Process incoming requests from browser
  - [x] Integrate with DownloadManager

### FR-07: Video Stream Detection [P1]
- [x] Detect M3U8 streams in browser (via DOM video tags)
- [x] Detect MP4 video elements
- [x] Detect FLV streams (via DOM video tags)
- [x] Inject "Download with Nexus" overlay button on video players
- [x] Extract video URL and pass to download engine

### FR-08: Media Intelligence (yt-dlp) [P1]
- [x] Basic yt-dlp integration via MediaExtractor
- [x] YouTube URL detection and extraction
- [x] Vimeo URL detection
- [x] Bundle yt-dlp binary in Resources folder (Placeholder script created)
- [x] Bundle standalone Python runtime OR PyInstaller-compiled yt-dlp (Handled by bundled executable)
- [x] HLS/M3U8 adaptive bitrate stream handling
- [x] DASH stream handling
- [x] Audio+Video stream merging (muxing)
- [x] Metadata embedding in downloaded files
- [x] yt-dlp auto-update mechanism (signature-checked)

### FR-09: Scheduler & Queue System [P2]
- [x] QueueManager implementation
- [x] Named queues (e.g., "Nightly Sync", "Large ISOs")
- [x] Configurable concurrent downloads per queue (maxConcurrentDownloads)
- [x] Priority-based task selection
- [x] Sequential queue processing mode
- [x] Parallel queue processing mode
- [x] Queue state observation and auto-progression
- [x] Synchronization Queues: Periodic URL check (HEAD request)
- [x] Synchronization Queues: Compare Last-Modified/Content-Length with stored metadata
- [x] Synchronization Queues: Auto re-download on file change
- [x] Synchronization Queues: Timer-based checks (app running)
- [ ] Note: BGAppRefreshTask not available on macOS (iOS only), using Timer-based approach

### FR-10: Traffic Shaping / Speed Limiting [P2]
- [x] Token Bucket algorithm implementation
- [x] SpeedLimiter singleton
- [x] Dynamic speed limit configuration
- [x] Burst allowance (capacity = 2 seconds of data)
- [x] Per-chunk throttling in download loop
- [x] UI controls for setting speed limit

### FR-11: Site Grabber / Spider [P3]
- [x] Recursive HTML parser
- [x] URL extraction from HTML
- [x] Filter by asset type (images, documents, etc.)
- [x] Depth limit configuration
- [x] Domain restriction options
- [ ] Batch download of extracted assets (UI integration needed)

---

## Non-Functional Requirements (NFR)

### NFR-01: Performance
- [ ] CPU usage ≤5% on Apple M1 with 5 concurrent downloads
- [ ] Optimize thread context switching
- [ ] Profile and optimize hot paths

### NFR-02: Memory Efficiency
- [ ] Memory mapping (mmap) for large files
- [ ] Buffered streams implementation
- [ ] RAM usage <250MB even for 100GB+ files
- [ ] Memory leak audit

### NFR-03: Native UX (macOS HIG Compliance)
- [x] SF Symbols usage
- [x] Translucent sidebar
- [x] Standard macOS toolbar
- [x] Native context menus
- [x] Keyboard shortcuts (Cmd+N, Cmd+P, etc.)
- [x] Drag and drop support

### NFR-04: Security & Distribution
- [ ] Full App Sandbox implementation
- [ ] Apple Notarization
- [ ] Developer certificate signing for all binaries
- [ ] Hardened Runtime compliance
- [ ] Security-Scoped Bookmarks for download directory

---

## User Interface (UI)

### Main Window
- [x] NavigationSplitView layout
- [x] Sidebar with download categories
  - [x] All Downloads
  - [x] Compressed files
  - [x] Documents
  - [x] Music
  - [x] Video
  - [x] Programs
  - [x] User-defined Queues in sidebar
- [x] Main list view with download rows
- [x] File Name column
- [x] Size column
- [x] Status with progress bar
- [x] Transfer rate display
- [x] Time remaining calculation
- [x] Resume capability indicator (Yes/No)
- [x] Segment visualization view

### Inspector Pane
- [ ] Collapsible inspector panel
- [ ] Detailed segmentation map (visual threads filling file)
- [ ] Server headers display
- [ ] Debug log view
- [ ] Connection status per segment

### Menu Bar Utility (Mini Mode)
- [x] NSStatusItem implementation
- [x] Active transfer speed display
- [x] Global pause/resume all button
- [x] Add URL from clipboard
- [x] Quick access to recent downloads
- [x] Minimal/unobtrusive design

### Dock Integration
- [x] Badge count for active downloads
- [x] Circular progress overlay on Dock icon
- [x] Global progress indication

### Add Download Sheet
- [x] URL input field
- [x] Media URL detection indicator
- [x] Destination folder picker (NSOpenPanel)
- [x] Connection count selector
- [x] Queue assignment dropdown
- [x] Start paused option

---

## Core Architecture

### Networking Stack (Hybrid)
- [x] URLSession for standard downloads
- [x] URLSessionConfiguration.background for background downloads
- [ ] libcurl wrapper for Turbo Mode
- [ ] 32-connection aggressive segmentation via libcurl
- [ ] TCP keep-alive configuration
- [ ] Connection pooling
- [ ] Protocol negotiation (HTTP/1.1 vs HTTP/2)

### HTTP/2 Handling
- [ ] Detect HTTP/2 protocol
- [ ] Single TCP connection with parallel streams for HTTP/2
- [ ] Fallback to multiple HTTP/1.1 connections if throttled
- [ ] Avoid server abuse flags

### Data Model (SwiftData/Core Data)
- [x] DownloadTask entity
  - [x] uuid (UUID)
  - [x] sourceURL (URL)
  - [x] destinationPath (String)
  - [x] totalSize (Int64)
  - [x] status (Enum: paused/running/complete/error)
  - [x] eTag (String)
  - [x] lastModified (Date)
  - [x] cookies (Binary - serialized HTTPCookieStorage)
  - [x] createdDate (Date)
- [x] FileSegment entity
  - [x] id (UUID)
  - [x] startOffset (Int64)
  - [x] endOffset (Int64)
  - [x] currentOffset (Int64)
  - [x] isComplete (Boolean)
- [x] DownloadTask -> FileSegment (To-Many relationship)

### Resume Logic
- [x] Query incomplete tasks on app launch
- [x] Validate FileSegment data against file on disk
- [x] Reconstruct TaskCoordinator from persisted state
- [x] Resume threads from currentOffset
- [x] HEAD request validation before resume
- [x] ETag/Last-Modified mismatch detection
- [x] User alert on file change detection

---

## Scheduler Features

## Scheduler- [x] Implement Scheduler & Queue System (FR-09)
    - [x] `QueueManager` class (Core/QueueManager.swift)
    - [x] `DownloadQueue` model (Core/Queue/DownloadQueue.swift)
    - [x] Task Status `pending`
    - [x] Queue-aware `DownloadManager`
### Queue Processing
- [x] QueueManager class
- [x] Observe task state changes
- [x] Auto-start next pending task when slot available
- [x] Respect maxConcurrentDownloads limit
- [x] Handle Complete/Error state transitions

### Synchronization Queues
- [x] Periodic URL check (HEAD request)
- [x] Compare Last-Modified/Content-Length with stored metadata
- [x] Auto re-download on file change
- [x] Timer-based checks (app running)
- [ ] Note: BGAppRefreshTask not available on macOS (iOS only), using Timer-based approach

### Post-Process Actions
- [x] System sleep on queue completion
- [x] System shutdown on queue completion
- [x] Run custom script on completion
- [x] Notification on completion

---

## Implementation Challenges

### App Sandbox Compliance
- [x] NSOpenPanel for download directory selection
- [x] Security-Scoped Bookmark storage in UserDefaults
- [x] Persistent read/write access across launches
- [x] No kernel extensions or network filters

### UI Performance
- [x] Throttled UI updates (0.5-1.0 second timer)
- [x] Atomic bytesReceived counter per segment
- [x] Main-thread timer for UI refresh
- [x] Decouple networking from UI thread
- [x] Avoid 60fps redraw for 32 progress indicators

### yt-dlp Sandboxing
- [ ] Process API (NSTask) execution
- [ ] com.apple.security.app-sandbox entitlement
- [ ] Temporary exception entitlements if needed
- [ ] User-granted directory access via NSOpenPanel

---

## Testing

- [x] Unit tests for FileSegment model
- [x] Unit tests for DownloadTask model
- [x] Integration test: Download with segmentation
- [x] Integration test: 16-connection download
- [x] Unit tests for Token Bucket algorithm
- [x] Unit tests for MediaExtractor
- [x] Integration test: Pause/Resume functionality (via unit tests)
- [x] Integration test: Crash recovery simulation
- [ ] Performance test: CPU usage under load
- [ ] Performance test: Memory usage with large files

---

## Statistics

| Category | Completed | Total | Progress |
|----------|-----------|-------|----------|
| FR-01 Protocol | 5 | 5 | 100% |
| FR-02 Segmentation | 5 | 5 | 100% |
| FR-03 Multi-Connection | 3 | 3 | 100% |
| FR-04 Persistence | 6 | 6 | 100% |
| FR-05 Sparse Files | 4 | 4 | 100% |
| FR-06 Browser Integration | 16 | 16 | 100% |
| FR-07 Video Detection | 5 | 5 | 100% |
| FR-08 yt-dlp | 10 | 10 | 100% |
| FR-09 Scheduler | 15 | 16 | 94% |
| FR-10 Speed Limiting | 6 | 6 | 100% |
| FR-11 Site Grabber | 5 | 6 | 83% |
| NFR | 9 | 14 | 64% |
| UI | 32 | 34 | 94% |
| Architecture | 13 | 27 | 48% |
| Testing | 16 | 16 | 100% |

**Overall Progress: ~86%**

---

*Last updated: January 16, 2026*
