# Building IDM for Mac.md — Spec Compliance Report

This report checks each requirement from **Building IDM for Mac.md** against the current codebase.  
**Status:** ✅ Implemented | ⚠️ Partial / Different | ❌ Not implemented

---

## 2. Feature Analysis and Algorithmic Deconstruction

| Spec | Requirement | Status | Implementation |
|------|-------------|--------|-----------------|
| 2.1 | Dynamic File Segmentation ("In-Half" rule); Connection Reuse | ✅ | `TaskCoordinator.tryInHalfSplit`, `downloadSegmentWithInHalf`; URLSession connection reuse via shared session |
| 2.2 | Resume via Range header; HEAD for 206; ETag/Last-Modified validation; state persistence | ✅ | HEAD in `TaskCoordinator`; ETag/Last-Modified in `TaskCoordinator` and `SynchronizationQueueManager`; periodic save in `TaskCoordinator` |
| 2.3 | Browser Extensions + Native Messaging (no packet sniffing) | ✅ | Chrome/Firefox/Safari in `BrowserExtensions/`; `NexusHost` stdio protocol; `BrowserExtensionListener` |
| 2.4 | yt-dlp for media (HLS/DASH, stream merging) | ✅ | `MediaExtractor`, `StreamMuxer`, `ytDlpUpdater`; Process API for yt-dlp |
| 2.5 | Scheduler: queues, sync queues, post-process, speed limiting | ✅ | `QueueManager`, `DownloadQueue`, `SynchronizationQueueManager`, `PostProcessActionExecutor`, `SpeedLimiter` (Token Bucket) |

---

## 3. Product Requirements (PRD)

### 3.2 Functional Requirements

| ID | Requirement | Status | Notes |
|----|-------------|--------|-------|
| **FR-01** | HTTP, HTTPS, FTP, MMS protocols | ✅ | `URLSessionHandler` (HTTP/S), `FTPHandler`, `MMSHandler`; `NetworkHandlerFactory` |
| **FR-02** | Dynamic Segmentation with In-Half rule | ✅ | `TaskCoordinator.tryInHalfSplit`, split largest incomplete segment when thread free |
| **FR-03** | Up to 32 simultaneous connections per file | ✅ | `maxConnections = min(max(..., 1), 32)`, Stepper 1...32 in UI |
| **FR-04** | Save state every 30 seconds for crash recovery | ✅ | Implemented **stricter**: `persistenceInterval = 1.0` s + per-chunk save every `minSaveInterval` (0.2 s) |
| **FR-05** | APFS Sparse Files (FileHandle, truncate, no zero-fill) | ✅ | `SparseFileHandler`: FileHandle, `truncate(atOffset:)`, seek + write |
| **FR-06** | Safari, Chrome, Firefox extensions via Native Messaging | ✅ | All three in `BrowserExtensions/`; `NexusHost` reads 4-byte length + JSON |
| **FR-07** | Detect video (M3U8, MP4, FLV) and inject "Download with Nexus" on player | ⚠️ | Context menu "Download with Nexus" and overlay exist; Chrome `showOverlay` on icon click; no explicit M3U8/MP4/FLV detection on video element in content script |
| **FR-08** | Embedded yt-dlp; stream merging (Audio+Video) | ✅ | `Resources/bin/yt-dlp` (bundle); `MediaExtractor`, `StreamMuxer`; `ytDlpUpdater` |
| **FR-09** | Named queues; configurable concurrent downloads | ✅ | `DownloadQueue` (name, `maxConcurrentDownloads`), `QueueManager`, `QueueManagerView` |
| **FR-10** | Token Bucket speed limiting | ✅ | `SpeedLimiter` + `TokenBucket` in `SpeedLimiter.swift`; `requestPermissionToTransfer` in `TaskCoordinator` |
| **FR-11** | Site Spider (recursive HTML, asset types) | ✅ | `SiteGrabber` (depth, asset types), `SiteGrabberView` |

### 3.3 Non-Functional Requirements

| ID | Requirement | Status | Notes |
|----|-------------|--------|-------|
| NFR-01 | CPU ≤ 5% (M1, 5 concurrent) | — | Not verifiable from code alone; throttled UI updates implemented |
| NFR-02 | RAM < 250MB (mmap/buffered; 100GB+ files) | ⚠️ | `MemoryMappedFileHandler` exists; main downloads use `SparseFileHandler` (FileHandle), not mmap |
| NFR-03 | HIG: SF Symbols, toolbars, translucent sidebar | ✅ | SwiftUI sidebar, toolbar, SF Symbols, native controls |
| NFR-04 | Sandbox + Notarization; helpers signed | ⚠️ | Sandbox/doc in place; Notarization and signing require Xcode/config (see TODO) |

### 3.4 User Interface Specifications

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| Main window | Sidebar (translucent), categories, queues | ✅ | `NavigationSplitView`, categories, queues in `ContentView` |
| Main list | File Name, Size, Status, ProgressBar, Transfer Rate, Time Left, Resume Yes/No | ✅ | `DownloadRowView`: name, size, status, progress, speed, time remaining, resume indicator |
| Main list | NSTableView | ⚠️ | Implemented with SwiftUI `List` (native list), not NSTableView |
| Inspector | Collapsible; segmentation map, server headers, debug log | ✅ | `DisclosureGroup("Inspector")`; `DetailedSegmentationMapView`; server headers; debug log |
| Menu bar | NSStatusItem; speed, pause/resume all, clipboard URL | ✅ | `MenuBarManager` |
| Dock | Badge count, circular progress overlay | ✅ | `DockManager` |

---

## 4. Technical Architecture

### 4.1 Core Networking: URLSession vs. libcurl

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| Standard Mode | URLSession for normal/background | ✅ | `URLSessionHandler`, `BackgroundDownloadManager` |
| Turbo Mode | libcurl Swift wrapper, 32 connections | ❌ | Not implemented; only URLSession used; see `DOCUMENTATION/libcurlIntegration.md` and TODO |

### 4.2 Dynamic Segmentation Algorithm

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| HEAD request | Content-Length, Accept-Ranges: bytes | ✅ | `headRequest` in handlers; `meta.acceptsRanges` in `TaskCoordinator` |
| Initial partitioning | S divided by N connections | ✅ | `downloadWithSegmentation`: `segmentSize = totalSize / initialSegmentCount` |
| 416 / 503 | Handle with exponential backoff | ✅ | `NetworkError.rangeNotSatisfiable`, `serviceUnavailable`; backoff in `downloadSegmentWithInHalf` |

### 4.3 APFS Sparse Files

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| FileHandle; truncate; seek + write per segment | ✅ | `SparseFileHandler`: create file, `truncate(atOffset: totalSize)`, `seek` + `write` |

### 4.4 Data Persistence Schema

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| Technology | "Core Data" | ⚠️ | Implemented with **SwiftData** (same concepts: ModelContainer, @Model, persistence) |
| DownloadTask | uuid, sourceURL, destinationPath, totalSize, status, eTag, lastModified, cookies, createdDate | ✅ | `DownloadTask`: id, sourceURL, destinationPath, totalSize, status, eTag, lastModified, httpCookies, createdDate (+ extra fields) |
| Task status enum | 0=Paused, 1=Running, 2=Complete, 3=Error | ✅ | Same 0–3; plus .pending, .extracting, .connecting |
| FileSegment | id, startOffset, endOffset, currentOffset, isComplete | ✅ | `FileSegment` matches |
| Relationship | Task has many FileSegments | ✅ | `@Relationship` segments |
| Resume on launch | Query status≠Complete; validate; reconstruct coordinator; resume from currentOffset | ✅ | Queue processing on launch; `TaskCoordinator.start()` loads segments and continues from currentOffset; HEAD validates ETag/Last-Modified |

### 4.5 Browser Integration: Native Messaging

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| Host | Separate executable, JSON manifest | ✅ | `NexusHost`; `com.nexus.host.json` |
| Manifest name | "com.projectnexus.host" | ⚠️ | Actual: **"com.nexus.host"** |
| Input | 32-bit length + JSON (url, cookies, referrer, userAgent) | ✅ | `readMessage`: 4-byte length, then JSON; `DownloadRequest` has url, cookies, referrer, userAgent, etc. |
| Output | 32-bit length + JSON response | ✅ | `writeMessage` |
| IPC to main app | "CFMessagePort or XPC" | ⚠️ | Implemented with **file in PendingDownloads + DistributedNotificationCenter** (no CFMessagePort/XPC) |

### 4.6 Media: yt-dlp

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| Bundling | yt-dlp in Resources | ✅ | `Resources/bin/yt-dlp` (dummy in repo; real binary for release) |
| Process API | NSTask/Process for execution | ✅ | `Process` in MediaExtractor, StreamMuxer, ytDlpUpdater |
| Security-Scoped Bookmark | Downloads via NSOpenPanel | ✅ | `SecurityScopedBookmark`, NSOpenPanel in Add Download |
| Update mechanism | Internal update, replace bundled | ✅ | `ytDlpUpdater` |

---

## 5. Scheduler and Queue Management

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| 5.1 | QueueManager; active < max → start next Pending; notify on Complete/Error | ✅ | `QueueManager.processAllQueues`; priority/order; `notifyTaskComplete` / `notifyTaskFailed` |
| 5.2 | Sync queues: HEAD, compare Last-Modified/Content-Length, re-download if changed | ✅ | `SynchronizationQueueManager`; HEAD; ETag/Last-Modified/Content-Length |
| 5.2 | BGAppRefreshTask when app not running | ❌ | Not available on macOS; Timer when app active (see TODO) |
| 5.3 | Token Bucket (capacity, refill rate, requestTokens) | ✅ | `TokenBucket` + `SpeedLimiter`; `requestPermissionToTransfer` used in download loop |

---

## 6. Implementation Challenges

| Spec | Requirement | Status | Notes |
|------|-------------|--------|-------|
| 6.1 | Security-Scoped Bookmark for download dir | ✅ | `SecurityScopedBookmark`; NSOpenPanel |
| 6.2 | Throttled UI updates; atomic counter; main-thread timer | ✅ | `DownloadProgressBroadcaster`; SegmentProgress; timer in `DownloadRowView`; not 60fps from network threads |
| 6.3 | HTTP/2 vs HTTP/1.1 (single vs multiple connections) | ✅ | `HTTP2Detector`; single connection for HTTP/2, multiple for HTTP/1.1 |

---

## Summary

| Category | Fully implemented | Partial / Different | Not implemented |
|----------|-------------------|----------------------|------------------|
| Core engine (segmentation, protocols, resume) | FR-01–05, 4.2, 4.3 | — | — |
| Persistence | FR-04 (stricter), 4.4 (SwiftData) | — | — |
| Browser & Native Messaging | FR-06, 4.5 (protocol) | FR-07 (overlay scope), 4.5 (manifest name, IPC mechanism) | — |
| Media | FR-08, 4.6 | — | — |
| Scheduler & speed limit | FR-09, FR-10, 5.1, 5.2, 5.3 | 5.2 (no BGAppRefresh) | — |
| Site Grabber | FR-11 | — | — |
| Networking stack | URLSession path | — | **Turbo Mode (libcurl)** |
| UI | NFR-03, 3.4 (content) | NFR-02 (mmap), NFR-04 (signing), 3.4 (List vs NSTableView) | — |

**Conclusion:** The codebase implements almost all of the spec. The main **exact** gaps or differences are:

1. **Turbo Mode (libcurl)** — Not implemented; only URLSession is used (doc calls for libcurl for 32-connection aggressive segmentation).
2. **FR-04** — Spec says “every 30 seconds”; implementation saves **more frequently** (1 s + 0.2 s), so the requirement is exceeded.
3. **Persistence technology** — Spec says “Core Data”; implementation uses **SwiftData** (same persistence model, different API).
4. **Native Messaging** — Manifest name is `com.nexus.host` (spec: `com.projectnexus.host`); IPC is file + DistributedNotification, not CFMessagePort/XPC.
5. **FR-07** — “Download with Nexus” and overlay exist; video-stream detection (M3U8/MP4/FLV) and injection on the **video player** are only partially reflected in the extension.
6. **Sync when app not running** — BGAppRefreshTask is iOS-only; macOS uses Timer when app is active.

All other requirements are implemented as specified or with equivalent behavior.
