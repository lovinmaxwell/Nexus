# Project Nexus

**The Native macOS Internet Download Manager**

> **Note:** "Project Nexus" is the internal code name.

## � Executive Summary & Strategic Intention

The digital content landscape is defined by an exponential increase in file sizes and media complexity. While bandwidth availability has grown, the mechanisms for reliable, high-speed file transfer on the client side have often stagnated within standard browser implementations.

**Internet Download Manager (IDM)** on the Windows platform has established a hegemony in this sector by offering a distinct set of capabilities: dynamic file segmentation, robust error recovery, and deep browser integration. However, the macOS ecosystem currently lacks a native solution that strictly replicates IDM’s aggressive acceleration logic and feature density while adhering to Apple’s modern architectural standards.

**Project Nexus** is designed to fill this market void. It is a "Productivity Powerhouse" capable of accelerating downloads by up to **5-8 times** through algorithmic optimizations. By deconstructing the technical strategies of IDM—specifically the **"In-Half" dynamic segmentation rule** and **connection reuse**—and mapping them to macOS primitives like `URLSession`, `FileHandle` (for sparse file support), and Core Data, Nexus delivers a market-leading utility tailored for macOS.

## 🚀 Key Features & Algorithmic Logic

### 1. Dynamic File Segmentation ("In-Half" Rule)
Unlike standard downloaders that split a file into a fixed number of parts, Nexus segments files dynamically. It employs the **"In-Half" Division Rule**: when a connection becomes available, the system identifies the largest remaining incomplete segment and splits it in half, assigning the idle thread to the new chunk. This ensures fast connections are never left idle.

### 2. Aggressive Acceleration
- **Hybrid Networking Stack:** Utilizes a generic `URLSession` for standard background tasks and a custom **libcurl wrapper** in "Turbo Mode" to support up to **32 simultaneous connections** per file, bypassing standard connection coalescing.
- **Connection Reuse:** Reuses existing TCP connections to reduce latency overhead associated with 3-way handshakes and SSL negotiation.

### 3. Robust Resume Capability
Nexus persists download state (offsets, headers, ETag) to **Core Data** every 30 seconds. If a download is interrupted, it verifies file integrity using HTTP Range headers and resumes exactly where it left off, preventing data loss.

### 4. Advanced Browser Integration
Since modern macOS App Sandboxing restricts direct network sniffing, Nexus uses **Native Messaging** extensions for **Safari**, **Chrome**, and **Firefox**. These extensions securely pass download URLs, cookies, and user-agent data to the native engine.

### 5. Media Intelligence
Includes an embedded **yt-dlp** engine to handle complex media extraction (HLS/M3U8/DASH), allowing users to download video and audio from streaming sites with a "Download this Video" overlay.

### 6. System Optimization
- **APFS Sparse Files:** Uses `FileHandle` to create sparse files, allowing instant logical allocation of disk space without writing zero-bytes, preserving SSD longevity.
- **Token Bucket Limiter:** Implements a Token Bucket algorithm for precise download speed limiting that averages throughput without "saw-toothing".

## 🛠 Technical Architecture

*   **Language:** Swift (ensuring type safety and performance)
*   **Networking:** Hybrid `URLSession` + `libcurl`
*   **Local Storage:** Core Data (Relational state management) & APFS Sparse Files
*   **Security:** App Sandbox compliant; Native Messaging for browser communication
*   **UI:** Native SwiftUI/AppKit interface adhering to macOS Human Interface Guidelines (HIG)

## � Installation

*Detailed build and installation instructions will be added as the project matures.*

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
