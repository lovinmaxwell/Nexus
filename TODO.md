# Project Nexus - Development Progress Tracker

> Native macOS Internet Download Manager with IDM-like acceleration

---

## Functional Requirements (FR)

### FR-01: Protocol Support [P0]
- [x] HTTP protocol support
- [x] HTTPS protocol support
- [x] FTP protocol support (FTPHandler with curl)
- [x] NetworkHandlerFactory for protocol selection
- [ ] MMS protocol support

### FR-02: Dynamic File Segmentation [P0]
- [x] Implement "In-Half" division rule algorithm
- [x] Split largest active segment when thread becomes free
- [x] Connection reuse without additional handshakes
- [ ] HTTP 416 (Range Not Satisfiable) error handling with exponential backoff
- [ ] HTTP 503 (Service Unavailable) error handling with exponential backoff

### FR-03: Multi-Connection Downloads [P0]
- [x] Support up to 32 simultaneous connections per file
- [x] Configurable connection count per download
- [x] TaskCoordinator managing worker thread pool

### FR-04: State Persistence & Crash Recovery [P0]
- [x] Save download state every 30 seconds
- [x] Persist byte offsets for every thread
- [x] File segment map persistence
- [x] Resume from exact position after crash/power failure
- [ ] ETag validation on resume (detect file changes)
- [ ] Last-Modified header validation on resume

### FR-05: APFS Sparse Files [P1]
- [x] SparseFileHandler implementation
- [x] Pre-allocate disk space via truncate()
- [x] Random offset writes without zero-fill overhead
- [x] FileWriter actor for thread-safe disk writes

### FR-06: Browser Integration [P0]
- [ ] **Safari Web Extension**
  - [ ] Extension bundled in app
  - [ ] manifest.json with nativeMessaging permission
  - [ ] browser.runtime.sendNativeMessage implementation
  - [ ] Download link interception
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
- [ ] Detect M3U8 streams in browser
- [ ] Detect MP4 video elements
- [ ] Detect FLV streams
- [ ] Inject "Download with Nexus" overlay button on video players
- [ ] Extract video URL and pass to download engine

### FR-08: Media Intelligence (yt-dlp) [P1]
- [x] Basic yt-dlp integration via MediaExtractor
- [x] YouTube URL detection and extraction
- [x] Vimeo URL detection
- [ ] Bundle yt-dlp binary in Resources folder
- [ ] Bundle standalone Python runtime OR PyInstaller-compiled yt-dlp
- [ ] HLS/M3U8 adaptive bitrate stream handling
- [ ] DASH stream handling
- [ ] Audio+Video stream merging (muxing)
- [ ] Metadata embedding in downloaded files
- [ ] yt-dlp auto-update mechanism (signature-checked)

### FR-09: Scheduler & Queue System [P2]
- [ ] QueueManager implementation
- [ ] Named queues (e.g., "Nightly Sync", "Large ISOs")
- [ ] Configurable concurrent downloads per queue (maxConcurrentDownloads)
- [ ] Priority-based task selection
- [ ] Sequential queue processing mode
- [ ] Parallel queue processing mode
- [ ] Queue state observation and auto-progression

### FR-10: Traffic Shaping / Speed Limiting [P2]
- [x] Token Bucket algorithm implementation
- [x] SpeedLimiter singleton
- [x] Dynamic speed limit configuration
- [x] Burst allowance (capacity = 2 seconds of data)
- [x] Per-chunk throttling in download loop
- [ ] UI controls for setting speed limit

### FR-11: Site Grabber / Spider [P3]
- [ ] Recursive HTML parser
- [ ] URL extraction from HTML
- [ ] Filter by asset type (images, documents, etc.)
- [ ] Depth limit configuration
- [ ] Domain restriction options
- [ ] Batch download of extracted assets

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
- [ ] Standard macOS toolbar
- [ ] Native context menus
- [ ] Keyboard shortcuts (Cmd+N, Cmd+P, etc.)
- [ ] Drag and drop support

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
  - [ ] User-defined Queues in sidebar
- [x] Main list view with download rows
- [x] File Name column
- [x] Size column
- [x] Status with progress bar
- [x] Transfer rate display
- [ ] Time remaining calculation
- [ ] Resume capability indicator (Yes/No)
- [x] Segment visualization view

### Inspector Pane
- [ ] Collapsible inspector panel
- [ ] Detailed segmentation map (visual threads filling file)
- [ ] Server headers display
- [ ] Debug log view
- [ ] Connection status per segment

### Menu Bar Utility (Mini Mode)
- [ ] NSStatusItem implementation
- [ ] Active transfer speed display
- [ ] Global pause/resume all button
- [ ] Add URL from clipboard
- [ ] Quick access to recent downloads
- [ ] Minimal/unobtrusive design

### Dock Integration
- [ ] Badge count for active downloads
- [ ] Circular progress overlay on Dock icon
- [ ] Global progress indication

### Add Download Sheet
- [x] URL input field
- [x] Media URL detection indicator
- [x] Destination folder picker (NSOpenPanel)
- [ ] Connection count selector
- [ ] Queue assignment dropdown
- [ ] Start paused option

---

## Core Architecture

### Networking Stack (Hybrid)
- [x] URLSession for standard downloads
- [ ] URLSessionConfiguration.background for background downloads
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
  - [ ] cookies (Binary - serialized HTTPCookieStorage)
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
- [ ] HEAD request validation before resume
- [ ] ETag/Last-Modified mismatch detection
- [ ] User alert on file change detection

---

## Scheduler Features

### Queue Processing
- [ ] QueueManager class
- [ ] Observe task state changes
- [ ] Auto-start next pending task when slot available
- [ ] Respect maxConcurrentDownloads limit
- [ ] Handle Complete/Error state transitions

### Synchronization Queues
- [ ] Periodic URL check (HEAD request)
- [ ] Compare Last-Modified/Content-Length with stored metadata
- [ ] Auto re-download on file change
- [ ] BGAppRefreshTask for background checks (app not running)
- [ ] Timer-based checks (app running)

### Post-Process Actions
- [ ] System sleep on queue completion
- [ ] System shutdown on queue completion
- [ ] Run custom script on completion
- [ ] Notification on completion

---

## Implementation Challenges

### App Sandbox Compliance
- [ ] NSOpenPanel for download directory selection
- [ ] Security-Scoped Bookmark storage in UserDefaults
- [ ] Persistent read/write access across launches
- [ ] No kernel extensions or network filters

### UI Performance
- [ ] Throttled UI updates (0.5-1.0 second timer)
- [ ] Atomic bytesReceived counter per segment
- [ ] Main-thread timer for UI refresh
- [ ] Decouple networking from UI thread
- [ ] Avoid 60fps redraw for 32 progress indicators

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
- [ ] Unit tests for Token Bucket algorithm
- [ ] Unit tests for MediaExtractor
- [ ] Integration test: Pause/Resume functionality
- [ ] Integration test: Crash recovery simulation
- [ ] Performance test: CPU usage under load
- [ ] Performance test: Memory usage with large files

---

## Statistics

| Category | Completed | Total | Progress |
|----------|-----------|-------|----------|
| FR-01 Protocol | 2 | 4 | 50% |
| FR-02 Segmentation | 3 | 5 | 60% |
| FR-03 Multi-Connection | 3 | 3 | 100% |
| FR-04 Persistence | 4 | 6 | 67% |
| FR-05 Sparse Files | 4 | 4 | 100% |
| FR-06 Browser Integration | 0 | 16 | 0% |
| FR-07 Video Detection | 0 | 5 | 0% |
| FR-08 yt-dlp | 3 | 10 | 30% |
| FR-09 Scheduler | 0 | 7 | 0% |
| FR-10 Speed Limiting | 5 | 6 | 83% |
| FR-11 Site Grabber | 0 | 6 | 0% |
| NFR | 2 | 14 | 14% |
| UI | 14 | 34 | 41% |
| Architecture | 11 | 27 | 41% |
| Testing | 4 | 10 | 40% |

**Overall Progress: ~35%**

---

*Last updated: January 15, 2026*
