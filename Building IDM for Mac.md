# **Project Nexus: Comprehensive Architectural Specification and Product Requirements for a Native macOS Internet Download Manager**

## **1\. Executive Summary and Strategic Alignment**

The digital content landscape is defined by an exponential increase in file sizes and media complexity. While bandwidth availability has grown, the mechanisms for reliable, high-speed file transfer on the client side have often stagnated within standard browser implementations. Internet Download Manager (IDM) on the Windows platform has established a hegemony in this sector by offering a distinct set of capabilities: dynamic file segmentation, robust error recovery, and deep browser integration.1 However, the macOS ecosystem currently lacks a native solution that strictly replicates IDM’s aggressive acceleration logic and feature density while adhering to Apple’s modern architectural standards, such as the Apple File System (APFS) and App Sandboxing.

This report serves as the foundational Product Requirements Document (PRD) and Technical Specification for **Project Nexus**, a proposed native macOS application designed to fill this market void. The objective is to engineer a "Productivity Powerhouse" 2 capable of accelerating downloads by up to 5-8 times through algorithmic optimizations.3 By analyzing the technical underpinnings of IDM—specifically its "In-Half" dynamic segmentation rule and connection reuse strategies 4—and mapping them to macOS primitives like URLSession, FileHandle (for sparse file support) 6, and SwiftData 8 for persistence, this document outlines a path to delivering a market-leading utility.

The proposed architecture leverages the Swift programming language for type safety and performance, integrates yt-dlp for complex media extraction 9, and employs Native Messaging for secure, sandboxed browser communication.10 This report details the functional requirements, user interface specifications, and the intricate engineering logic required to replicate IDM's behavior within the constraints of the macOS Hardened Runtime.

*Implementation alignment: This document has been updated to reflect the current codebase (SwiftData, NexusHost manifest name and IPC, URLSession as primary stack, Timer-based sync queues, etc.). For a requirement-by-requirement compliance checklist, see DOCUMENTATION/SpecComplianceReport.md.*

## ---

**2\. Feature Analysis and Algorithmic Deconstruction**

To architect a superior solution, one must first deconstruct the functional behaviors that define the market leader. IDM’s efficacy is not merely a result of downloading files but of *how* it manages the Transmission Control Protocol (TCP) and HTTP application layer to maximize throughput and reliability.

### **2.1 Dynamic File Segmentation and Acceleration**

The core differentiator of IDM is "Dynamic File Segmentation." Unlike standard downloaders that split a file into a fixed number of parts before the transfer begins, IDM segments files dynamically during the download process.3 This addresses the issue of "tail drop," where a single slow connection delays the completion of the entire file.

The proposed logic for Project Nexus relies on the **"In-Half" Division Rule**. When a connection becomes available (e.g., a thread finishes its assigned segment early), the download manager identifies the largest remaining incomplete segment currently being downloaded by another thread. It then effectively splits this largest segment in half, assigning the new idle thread to download the second half. This ensures that fast connections are never left idle while waiting for a slow connection to finish a large chunk.4

Crucially, this system must implement **Connection Reuse**. The application reuses existing connections without going through additional connect and login stages (handshakes). This reduces the latency overhead associated with the TCP three-way handshake and SSL/TLS negotiation, which is particularly critical for HTTPS downloads where session resumption can significantly reduce Time-To-First-Byte (TTFB).3

### **2.2 Robust Resume Capability and Error Recovery**

Network instability is inevitable, particularly for users on wireless or satellite connections. The system’s reliability stems from its ability to resume broken downloads from exactly where they left off, preventing the waste of bandwidth and time.

The technical enabler for this is the standard HTTP Range header (Range: bytes=start-end). The application must verify server support for partial content (HTTP 206\) via a HEAD request before attempting a resume. If the ETag or Last-Modified headers have changed, the application must detect this discrepancy and alert the user or restart the download to prevent data corruption.12

State persistence is equally vital. The application must serialize the download state—including the byte offsets of every thread and the file map—to disk several times per minute. This ensures that in the event of a power failure, system crash, or forced termination, the download can be reconstructed without data loss.4

### **2.3 Advanced Browser Integration (The Sniffer)**

Modern users rarely interact with download managers manually; they expect the application to intercept downloads automatically. IDM utilizes a "sniffer" that monitors network traffic or intercepts browser download events.3

Given that modern macOS architecture (specifically App Sandboxing) restricts direct network interface access for packet sniffing, Project Nexus will utilize **Browser Extensions** (Safari Web Extensions, Chrome, Firefox) that communicate with the main application via **Native Messaging**.10 This provides a secure channel to pass the download URL, User-Agent, Cookies, and Referrer data from the browser context to the native download engine, ensuring that authenticated downloads (e.g., from premium file hosts) function correctly.

### **2.4 Media Grabbing and Intelligence**

A highly requested feature is the ability to download embedded video content. IDM presents a "Download this Video" panel over web players.3 To replicate this on macOS, the application must integrate a media extraction engine. While basic HTTP sniffing works for simple files, modern streaming often uses Adaptive Bitrate Streaming (HLS/M3U8) or DASH, where audio and video are separate streams.

Project Nexus will integrate the open-source **yt-dlp** engine to handle these complex media sites.9 This allows for the extraction of high-definition video, audio conversion, and metadata embedding, features that are standard in the Windows ecosystem but often fragmented across different tools on Mac.15

### **2.5 Intelligent Scheduling and Automation**

For enterprise and power users, bandwidth management is critical. The "Scheduler" allows users to organize downloads into queues (e.g., "Nightly Sync," "Large ISOs") and process them sequentially or in parallel.16 The system must support advanced logic, such as:

* **Synchronization Queues:** Periodically checking if a file on a server has changed and re-downloading it if necessary.17  
* **Post-Process Actions:** Triggering system sleep, shutdown, or running a script upon queue completion.18  
* **Speed Limiting:** Utilizing a Token Bucket algorithm to cap bandwidth usage dynamically, preventing the download manager from saturating the network during business hours.19

## ---

**3\. Product Requirements Document (PRD)**

### **3.1 Product Identity and Scope**

* **Product Name:** Project Nexus (Internal Code Name).  
* **Target Platform:** macOS 14.0 (Sonoma) and later; compatible with Apple Silicon (M1/M2/M3) and Intel.  
* **Target Audience:** Power users, IT administrators, creative professionals dealing with large assets, and users with unstable internet connections.2  
* **Core Value Proposition:** The only native macOS application offering "In-Half" dynamic segmentation acceleration, seamless browser integration, and enterprise-grade queue management in a unified, HIG-compliant interface.

### **3.2 Functional Requirements (FR)**

The following table details the mandatory functional requirements derived from the analysis of IDM’s feature set.

| ID | Feature Category | Requirement Description | Priority | Source Reference |
| :---- | :---- | :---- | :---- | :---- |
| **FR-01** | **Core Engine** | The system MUST support HTTP, HTTPS, FTP, and MMS protocols. | P0 | 3 |
| **FR-02** | **Core Engine** | The system MUST implement "Dynamic File Segmentation" using the In-Half division rule to split the largest active segment when a thread becomes free. | P0 | 4 |
| **FR-03** | **Core Engine** | The system MUST support up to 32 simultaneous connections (threads) per file download. | P0 | 1 |
| **FR-04** | **Persistence** | The system MUST save download state (offsets, headers) to persistent storage at least every 30 seconds to enable crash recovery (implementation uses SwiftData with periodic save ~1 s plus throttled per-chunk saves). | P0 | 4 |
| **FR-05** | **File System** | The system MUST utilize APFS Sparse Files to pre-allocate disk space instantly without writing zero-bytes, preserving SSD longevity and performance. | P1 | 6 |
| **FR-06** | **Browser Int.** | The system MUST provide extensions for Safari, Chrome, and Firefox that intercept download links via Native Messaging. | P0 | 10 |
| **FR-07** | **Browser Int.** | The extension MUST detect video streams (M3U8, MP4, FLV) and inject a "Download with Nexus" overlay button on the video player. | P1 | 3 |
| **FR-08** | **Media** | The system MUST include an embedded yt-dlp binary to handle complex video extraction (YouTube, Vimeo) and stream merging (Audio+Video). | P1 | 9 |
| **FR-09** | **Scheduler** | The system MUST allow users to create named queues and configure the number of concurrent downloads (e.g., "Download 4 files at once"). | P2 | 16 |
| **FR-10** | **Traffic Shaping** | The system MUST implement a Token Bucket algorithm to provide accurate, dynamic download speed limiting (e.g., 5MB/s). | P2 | 19 |
| **FR-11** | **Site Grabber** | The system MUST include a "Site Spider" to recursively parse HTML and download specific asset types (images, docs) from a target URL. | P3 | 3 |

### **3.3 Non-Functional Requirements (NFR)**

* **NFR-01 Performance:** The application's CPU usage MUST NOT exceed 5% on an Apple Silicon M1 chip while performing 5 concurrent downloads.  
* **NFR-02 Memory Efficiency:** The application MUST utilize memory mapping (mmap) or buffered streams to ensure RAM usage remains under 250MB, even when downloading files exceeding 100GB.  
* **NFR-03 Native UX:** The user interface MUST strictly adhere to macOS Human Interface Guidelines (HIG), utilizing SF Symbols, standard toolbars, and translucent sidebars to ensure it feels like a native system utility.23  
* **NFR-04 Security:** The application MUST be fully Sandboxed and Notarized by Apple. All helper binaries (e.g., yt-dlp, Native Messaging Host) must be signed with the developer's certificate and strictly confined.25

### **3.4 User Interface Specifications**

The user interface design prioritizes information density and clarity, adapting the "spreadsheet" style of legacy download managers into a modern macOS context.

* **Main Window:**  
  * **Sidebar (Translucent Material):** Navigation categories (All Downloads, Compressed, Documents, Music, Video, Programs) and user-defined Queues.  
  * **Main List View:** Columns for File Name, Size, Status (ProgressBar), Transfer Rate, Time Left, and "Resume Capability" (Yes/No). Implemented as a SwiftUI List with equivalent columns.  
  * **Inspector Pane (Collapsible):** Detailed visualization of the segmentation map (showing active threads filling the file), server headers, and a debug log.  
* **Menu Bar Utility:** A lightweight NSStatusItem providing a "Mini Mode" to view active transfer speeds, pause/resume all, and add URLs from the clipboard, catering to users who prefer unobtrusive utilities.26  
* **Dock Integration:** The Dock icon will display a badge count for active downloads and a circular progress overlay indicating global progress.

## ---

**4\. Technical Architecture and Engineering Strategy**

This section translates the functional requirements into a concrete engineering plan, specifically addressing how to implement IDM-like features using macOS frameworks.

### **4.1 Core Networking Stack: URLSession vs. libcurl**

The choice of networking stack is pivotal. Apple's URLSession is the standard, optimized for battery life and background execution.27 However, IDM's logic often requires "fighting" for bandwidth using aggressive timeouts and non-standard connection behaviors that URLSession's high-level abstraction may suppress.

Strategic Decision: Hybrid Architecture  
Project Nexus employs a hybrid model:

1. **Standard Mode (URLSession):** Used for standard file transfers, background downloads (via URLSessionConfiguration.background), and battery-sensitive operations. This ensures compliance with macOS energy policies. *Current implementation uses URLSession for all downloads, with In-Half segmentation and up to 32 connections.*  
2. **Turbo Mode (libcurl / Swift Wrapper) [Planned]:** For optional "32-connection" acceleration with finer control over connection pooling and keep-alive, the application may wrap libcurl. See DOCUMENTATION/libcurlIntegration.md. libcurl would allow implementation of the same In-Half logic without connection coalescing.29

### **4.2 Dynamic Segmentation Algorithm Implementation**

The implementation of the "In-Half" rule requires a sophisticated TaskCoordinator that manages a pool of worker threads.

**Algorithm Logic:**

1. **Initialization:** The Coordinator performs a HEAD request to valid the URL and retrieve Content-Length. It checks for Accept-Ranges: bytes.13  
2. Initial Partitioning: The file size $S$ is divided by the user-configured number of connections $N$. Initial ranges are calculated: $R\_0 \=$.  
   \* Both threads now work to converge on the end of the segment.

This logic requires careful handling of HTTP 416 (Range Not Satisfiable) and 503 (Service Unavailable) errors, implementing exponential backoff for retries.

### **4.3 Storage Optimization: APFS Sparse Files**

Writing to random offsets in a file (as required by segmented downloading) can be inefficient if the file system forces the allocation of zero-filled blocks for the "gaps" between segments. macOS's APFS supports **Sparse Files**, where logical size can exceed physical size, and unwritten blocks consume no space.6

Implementation Detail:  
To utilize this, Project Nexus will use FileHandle (part of Foundation).

1. Create the file at the destination path.  
2. Call fileHandle.truncate(atOffset: totalSize) or seek to the end and write a single byte. This sets the logical file size instantly.  
3. As network threads receive data buffers, the FileWriter actor (a thread-safe Swift Actor) seeks to the specific offset and writes the data: fileHandle.seek(toFileOffset: segmentOffset); fileHandle.write(data).  
4. APFS automatically handles the fragmentation and mapping of these written blocks.7

### **4.4 Data Persistence Schema (SwiftData)**

To support the robust resume capability (FR-04), the application state must be modeled relationally. The implementation uses **SwiftData** (ModelContainer, @Model), which provides the same schema concepts and persistence as Core Data.8

**Schema Design:**

| Entity | Attribute | Type | Description |
| :---- | :---- | :---- | :---- |
| **DownloadTask** | uuid | UUID | Unique Identifier for the task. |
|  | sourceURL | URI | The origin URL. |
|  | destinationPath | String | Local file system path. |
|  | totalSize | Int64 | Total file size in bytes. |
|  | status | Int16 | Enum: 0=Paused, 1=Running, 2=Complete, 3=Error. |
|  | eTag | String | Validator for resume integrity. |
|  | lastModified | Date | Server timestamp for validation. |
|  | httpCookies | Binary | Serialized HTTPCookieStorage for authentication. |
|  | createdDate | Date | For sorting and history. |
| **FileSegment** | id | UUID | Unique Segment ID. |
|  | startOffset | Int64 | The logical start byte of this segment. |
|  | endOffset | Int64 | The logical end byte. |
|  | currentOffset | Int64 | The current write pointer (progress). |
|  | isComplete | Boolean | Completion flag. |
| **Relationship** | segments | To-Many | A DownloadTask has many FileSegments. |

**Resume Logic:** Upon application launch, the DownloadManager (via QueueManager) processes queues and starts pending tasks. When a task is started, the TaskCoordinator loads segments from the store, performs a HEAD request to validate ETag/Last-Modified/Content-Length, and resumes threads from currentOffset.12

### **4.5 Browser Integration: Native Messaging Architecture**

The "Click-to-Download" experience relies on tightly coupling the browser with the native app. Since direct API access is restricted, we must implement a **Native Messaging Host**.10

#### **4.5.1 Manifest Configuration**

The Native Messaging Host is a distinct executable binary bundled inside the main application. Browsers discover it via a JSON manifest file.

* **Chrome/Firefox:** The manifest is placed in \~/Library/Application Support/Google/Chrome/NativeMessagingHosts/ (or the equivalent for Firefox). The implementation uses the name `com.nexus.host` and app path Nexus.app (e.g. `/Applications/Nexus.app/Contents/MacOS/NexusHost`).  
  JSON (conceptual):  
  {  
    "name": "com.nexus.host",  
    "description": "Nexus Download Manager Native Messaging Host",  
    "path": "/Applications/Nexus.app/Contents/MacOS/NexusHost",  
    "type": "stdio",  
    "allowed\_origins": \["chrome-extension://\<extension-id\>/"\]  
  }

* **Safari:** Safari Web Extensions (since Safari 14\) are bundled inside the app. The extension's manifest.json must declare the "nativeMessaging" permission. Communication is handled via browser.runtime.sendNativeMessage which Safari routes to the containing app's handler.11

#### **4.5.2 Message Protocol**

The communication protocol is standard across browsers:

* **Input (Browser \-\> App):** A 32-bit unsigned integer (in native byte order) specifying the message length, followed by the JSON payload.  
  * *Payload:* { "url": "https://...", "cookies": "session=...", "referrer": "...", "userAgent": "..." }.  
* **Output (App \-\> Browser):** A 32-bit length integer followed by a JSON response (e.g., confirmation of download start).  
* **Swift Implementation:** The NexusHost binary utilizes FileHandle.standardInput to read the 32-bit length header and JSON payload, deserializes the JSON, and passes the download command to the main app via a file written to a shared Application Support directory plus DistributedNotificationCenter (com.nexus.newDownload), which the main app observes.

### **4.6 Media Intelligence: Embedding yt-dlp**

To fulfill FR-08, the application must bundle the yt-dlp executable. This presents specific challenges regarding Apple's App Sandbox.

**Implementation Strategy:**

1. **Bundling:** The yt-dlp binary is placed in the Resources folder of the App Bundle.  
2. **Runtime Environment:** Since macOS 12.3 removed the system Python, Project Nexus must bundle a standalone, relocatable Python runtime or use a compiled version of yt-dlp (e.g., via PyInstaller) to ensure it runs out-of-the-box.9  
3. **Sandboxing & Execution:** The main app cannot simply exec a binary. It must use the Process API (formerly NSTask). The app requires the com.apple.security.app-sandbox entitlement. Because yt-dlp writes to disk and accesses the network, the app may require temporary exception entitlements or explicitly ask the user to grant read/write access to a "Downloads" directory via NSOpenPanel, which grants a Security-Scoped Bookmark.25  
4. **Updates:** yt-dlp updates frequently to keep up with site changes. The app needs an internal update mechanism to download the latest yt-dlp binary signature-checked by the developers of Project Nexus, replacing the bundled version.

## ---

**5\. Scheduler and Queue Management Logic**

The Scheduler is the control center for automated operations. Its architecture is event-driven.

### **5.1 Queue Processing Logic**

The QueueManager maintains a list of DownloadQueue objects. Each queue has a concurrency limit property (maxConcurrentDownloads).

* **Logic:**  
  1. The QueueManager observes the state of all tasks in a queue.  
  2. If activeDownloads \< maxConcurrentDownloads, it selects the next Pending task based on priority/order.  
  3. It calls task.start().  
  4. When a task transitions to Complete or Error, the QueueManager is notified and triggers the next task.35

### **5.2 Synchronization and Periodic Checks**

For the "Synchronization Queue" feature (FR-09), the system uses Timer-based periodic checks while the app is active (BGAppRefreshTask is not available on macOS; it is iOS-only). When the app is running, sync queues are checked at their configured intervals.

* **Mechanism:** The app sends a HEAD request to the URL. It compares the Last-Modified or Content-Length header with the locally stored metadata. If different, it triggers a re-download.17

### **5.3 Speed Limiter (Token Bucket Algorithm)**

To implement smooth speed limiting (FR-10), a simple "sleep" or "pause" is insufficient as it causes TCP saw-toothing. We will use a **Token Bucket** algorithm.19

**Algorithm:**

* A Bucket is initialized with a capacity (burst size) and a refill rate (bytes per second).  
* Tokens (representing bytes) are added to the bucket at the refill rate.  
* Before a network thread reads data from the socket or writes to disk, it must "consume" tokens from the bucket.  
* **Implementation:**  
  Swift  
  func requestTokens(amount: Int) async {  
      while currentTokens \< amount {  
          let needed \= amount \- currentTokens  
          let waitTime \= needed / refillRate  
          try? await Task.sleep(nanoseconds: UInt64(waitTime \* 1\_000\_000\_000))  
          refillTokens()  
      }  
      currentTokens \-= amount  
  }

* This ensures that the average throughput strictly adheres to the user's setting while allowing micro-bursts for responsiveness.20

## ---

**6\. Implementation Challenges and Solutions**

### **6.1 The "App Sandbox" Constraint**

Unlike Windows, where IDM has broad system access, Project Nexus must operate within the macOS App Sandbox.

* **Challenge:** The app cannot write to arbitrary locations or sniff global network traffic.  
* **Solution:**  
  * **File Access:** Use NSOpenPanel during the first run to prompt the user to select a default download directory. Store the resulting URL as a Security-Scoped Bookmark in UserDefaults. This grants persistent read/write access to that specific directory across app launches.27  
  * **Network:** Rely strictly on the Browser Extension for URL interception rather than attempting to install a kernel extension or network filter, which improves system stability and user trust.

### **6.2 High CPU Usage with Multi-Threading**

Managing 32 threads for a single download, plus UI updates, can be CPU intensive.

* **Challenge:** Frequent context switching and UI redrawing (60fps) for 32 progress bars can spike CPU usage.  
* **Solution:** **Throttled UI Updates.** The networking threads do not update the UI directly. They update segment progress (and optionally a progress broadcaster). A main-thread Timer or push-based broadcaster updates the UI at a bounded rate (e.g. every 0.15–1.0 s). This decoupling prevents the UI from becoming a bottleneck during high-speed transfers.

### **6.3 Handling HTTP/2 and Multiplexing**

IDM's "multiple connections" strategy is optimized for HTTP/1.1. HTTP/2 utilizes multiplexing over a single TCP connection, rendering multiple connections redundant or even harmful (server may flag as abuse).

* **Solution:** The TaskCoordinator (via HTTP2Detector and NetworkHandlerFactory) performs protocol negotiation. If HTTP/2 is detected, a single connection with URLSession’s built-in multiplexing is used; if HTTP/1.1, multiple connections are used.38

## ---

**7\. Conclusion**

Project Nexus represents a significant engineering effort to bring enterprise-grade download management to the macOS platform. By carefully synthesizing the aggressive acceleration algorithms of IDM—specifically dynamic segmentation and connection reuse—with the modern, secure, and efficient frameworks of macOS (Swift, APFS, SwiftData), this project bridges a long-standing gap in the Apple software ecosystem.

The architecture prioritizes performance through URLSession-based downloads (with optional libcurl Turbo Mode documented for future use), reliability through robust persistence and resume logic, and usability through deep browser integration via Native Messaging. While the constraints of the App Sandbox and Hardened Runtime present unique challenges, the strategies outlined in this report—specifically the use of Security-Scoped Bookmarks and bundled helper runtimes—ensure that Project Nexus will be both a powerful tool for power users and a compliant citizen of the macOS environment.

This document serves as the blueprint for development, providing the necessary specifications to move from concept to a fully realized, market-leading application.

#### **Works cited**

1. WTH is Internet Download Manager? : r/software \- Reddit, accessed January 15, 2026, [https://www.reddit.com/r/software/comments/4te2w9/wth\_is\_internet\_download\_manager/](https://www.reddit.com/r/software/comments/4te2w9/wth_is_internet_download_manager/)  
2. Internet Download Manager: The Essential Tool for Businesses in the Digital Age \- Support Systems, accessed January 15, 2026, [https://supportssystems.com/internet-download-manager-the-essential-tool-for-businesses-in-the-digital-age/](https://supportssystems.com/internet-download-manager-the-essential-tool-for-businesses-in-the-digital-age/)  
3. Internet Download Manager features, accessed January 15, 2026, [https://www.internetdownloadmanager.com/features2.html](https://www.internetdownloadmanager.com/features2.html)  
4. Dynamic Segmentation and Performance \- Internet Download Manager, accessed January 15, 2026, [https://www.internetdownloadmanager.com/support/segmentation.html](https://www.internetdownloadmanager.com/support/segmentation.html)  
5. Internet Download Manager \- Documentation & Help, accessed January 15, 2026, [https://documentation.help/Internet-Download-Manager/doc.htm](https://documentation.help/Internet-Download-Manager/doc.htm)  
6. Sparse files are common in APFS \- The Eclectic Light Company, accessed January 15, 2026, [https://eclecticlight.co/2021/03/29/sparse-files-are-common-in-apfs/](https://eclecticlight.co/2021/03/29/sparse-files-are-common-in-apfs/)  
7. Sparse Files Are Common in APFS \- Michael Tsai, accessed January 15, 2026, [https://mjtsai.com/blog/2021/03/30/sparse-files-are-common-in-apfs/](https://mjtsai.com/blog/2021/03/30/sparse-files-are-common-in-apfs/)  
8. Core Data Programming Guide: Creating a Managed Object Model \- Apple Developer, accessed January 15, 2026, [https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/KeyConcepts.html](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/KeyConcepts.html)  
9. section83/MacYTDL: A macOS GUI front-end for the YT-DLP video downloader \- GitHub, accessed January 15, 2026, [https://github.com/section83/MacYTDL](https://github.com/section83/MacYTDL)  
10. Native messaging \- Mozilla \- MDN Web Docs, accessed January 15, 2026, [https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native\_messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging)  
11. Messaging between a webpage and your Safari web extension \- Apple Developer, accessed January 15, 2026, [https://developer.apple.com/documentation/safariservices/messaging-between-a-webpage-and-your-safari-web-extension](https://developer.apple.com/documentation/safariservices/messaging-between-a-webpage-and-your-safari-web-extension)  
12. ELI5: How Download Managers detect Resume Capability of a file(s) ? : r/explainlikeimfive, accessed January 15, 2026, [https://www.reddit.com/r/explainlikeimfive/comments/4p2wpn/eli5\_how\_download\_managers\_detect\_resume/](https://www.reddit.com/r/explainlikeimfive/comments/4p2wpn/eli5_how_download_managers_detect_resume/)  
13. HTTP range requests \- MDN Web Docs \- Mozilla, accessed January 15, 2026, [https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Range\_requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Range_requests)  
14. Maximizing Download Efficiency with Internet Download Manager (IDM)? | by Osman Ramzan | Medium, accessed January 15, 2026, [https://medium.com/@osmanwriter007/maximizing-download-efficiency-with-internet-download-manager-idm-8520a3aa3542](https://medium.com/@osmanwriter007/maximizing-download-efficiency-with-internet-download-manager-idm-8520a3aa3542)  
15. Simple UI for yt-dlp (macOS Only) : r/shortcuts \- Reddit, accessed January 15, 2026, [https://www.reddit.com/r/shortcuts/comments/199h5zm/simple\_ui\_for\_ytdlp\_macos\_only/](https://www.reddit.com/r/shortcuts/comments/199h5zm/simple_ui_for_ytdlp_macos_only/)  
16. How to use Internet Download Manager: Using Scheduler, accessed January 15, 2026, [https://www.internetdownloadmanager.com/support/idm-scheduler/idm\_scheduler.html](https://www.internetdownloadmanager.com/support/idm-scheduler/idm_scheduler.html)  
17. Internet Download Manager(IDM) Queue Use \- YouTube, accessed January 15, 2026, [https://www.youtube.com/watch?v=vqde5VQvi3Q](https://www.youtube.com/watch?v=vqde5VQvi3Q)  
18. Using Scheduler \- Internet Download Manager, accessed January 15, 2026, [https://www.internetdownloadmanager.com/support/old/support/using\_scheduler.html](https://www.internetdownloadmanager.com/support/old/support/using_scheduler.html)  
19. perrystreetsoftware/tokenbucketratelimiter: A token bucket rate limiter implemented in Swift, accessed January 15, 2026, [https://github.com/perrystreetsoftware/tokenbucketratelimiter](https://github.com/perrystreetsoftware/tokenbucketratelimiter)  
20. Single Token Bucket Algorithm | Junos OS \- Juniper Networks, accessed January 15, 2026, [https://www.juniper.net/documentation/us/en/software/junos/routing-policy/topics/concept/policer-algorithm-single-token-bucket.html](https://www.juniper.net/documentation/us/en/software/junos/routing-policy/topics/concept/policer-algorithm-single-token-bucket.html)  
21. yt-dlp/yt-dlp: A feature-rich command-line audio/video downloader \- GitHub, accessed January 15, 2026, [https://github.com/yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp)  
22. DenTelezhkin/Swarm: Simple, fast, modular Web-scrapping engine written in Swift \- GitHub, accessed January 15, 2026, [https://github.com/DenTelezhkin/Swarm](https://github.com/DenTelezhkin/Swarm)  
23. Toolbars | Apple Developer Documentation, accessed January 15, 2026, [https://developer.apple.com/design/human-interface-guidelines/toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)  
24. Human Interface Guidelines | Apple Developer Documentation, accessed January 15, 2026, [https://developer.apple.com/design/human-interface-guidelines](https://developer.apple.com/design/human-interface-guidelines)  
25. Is Apple allowed to distribute GPLv3-licensed software through its iOS App Store?, accessed January 15, 2026, [https://opensource.stackexchange.com/questions/9500/is-apple-allowed-to-distribute-gplv3-licensed-software-through-its-ios-app-store](https://opensource.stackexchange.com/questions/9500/is-apple-allowed-to-distribute-gplv3-licensed-software-through-its-ios-app-store)  
26. Design Choice \- Menu bar vs Normal apps : r/macapps \- Reddit, accessed January 15, 2026, [https://www.reddit.com/r/macapps/comments/1mc829e/design\_choice\_menu\_bar\_vs\_normal\_apps/](https://www.reddit.com/r/macapps/comments/1mc829e/design_choice_menu_bar_vs_normal_apps/)  
27. Downloading files from websites | Apple Developer Documentation, accessed January 15, 2026, [https://developer.apple.com/documentation/foundation/downloading-files-from-websites](https://developer.apple.com/documentation/foundation/downloading-files-from-websites)  
28. URLSession | Apple Developer Documentation, accessed January 15, 2026, [https://developer.apple.com/documentation/foundation/urlsession](https://developer.apple.com/documentation/foundation/urlsession)  
29. Why is NSURLSession slower than cURL when downloading many files? \- Stack Overflow, accessed January 15, 2026, [https://stackoverflow.com/questions/28227891/why-is-nsurlsession-slower-than-curl-when-downloading-many-files](https://stackoverflow.com/questions/28227891/why-is-nsurlsession-slower-than-curl-when-downloading-many-files)  
30. NSURLSession & libcurl \- Core Libraries \- Swift Forums, accessed January 15, 2026, [https://forums.swift.org/t/nsurlsession-libcurl/1790](https://forums.swift.org/t/nsurlsession-libcurl/1790)  
31. APFS: How sparse files work \- The Eclectic Light Company, accessed January 15, 2026, [https://eclecticlight.co/2024/06/08/apfs-how-sparse-files-work/](https://eclecticlight.co/2024/06/08/apfs-how-sparse-files-work/)  
32. Native messaging \- Chrome for Developers, accessed January 15, 2026, [https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)  
33. Messaging between the app and JavaScript in a Safari web extension \- Apple Developer, accessed January 15, 2026, [https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)  
34. Safari web extensions | Apple Developer Documentation, accessed January 15, 2026, [https://developer.apple.com/documentation/safariservices/safari-web-extensions](https://developer.apple.com/documentation/safariservices/safari-web-extensions)  
35. How to use Internet Download Manager: IDM Queues, accessed January 15, 2026, [https://www.internetdownloadmanager.com/support/idm-scheduler/idm\_queues.html](https://www.internetdownloadmanager.com/support/idm-scheduler/idm_queues.html)  
36. Rate Limiting Using a Token Bucket in Swift \- Paulo's Blog, accessed January 15, 2026, [https://pfandrade.me/blog/rate-limiting-using-a-token-bucket-in-swift/](https://pfandrade.me/blog/rate-limiting-using-a-token-bucket-in-swift/)  
37. The Algorithm Behind Rate Limiting (Token Bucket in 100 Seconds) \- Reddit, accessed January 15, 2026, [https://www.reddit.com/r/programming/comments/1mw5a85/the\_algorithm\_behind\_rate\_limiting\_token\_bucket/](https://www.reddit.com/r/programming/comments/1mw5a85/the_algorithm_behind_rate_limiting_token_bucket/)  
38. Accelerated downloads with HTTP byte range headers \- Stack Overflow, accessed January 15, 2026, [https://stackoverflow.com/questions/4113760/accelerated-downloads-with-http-byte-range-headers](https://stackoverflow.com/questions/4113760/accelerated-downloads-with-http-byte-range-headers)