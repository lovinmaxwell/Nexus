import Foundation
import SwiftData

/// Comprehensive download request from browser extension
/// Supports both basic capture and IDM-style webRequest capture
struct BrowserDownloadRequest: Codable {
    // Core URL information
    let url: String
    let originalUrl: String?  // Original URL before redirects
    let filename: String?
    
    // Full redirect chain (IDM-style capture)
    let redirectChain: [String]?
    
    // Request headers captured from browser
    let requestHeaders: [String: String]?
    
    // Response headers from server
    let responseHeaders: [String: String]?
    
    // Authentication & session
    let cookies: String?
    let referrer: String?
    let userAgent: String?
    let authorization: String?  // Auth header if present
    
    // Content information
    let contentType: String?
    let contentLength: Int64?
    let contentDisposition: String?
    
    // Metadata
    let captureMethod: String?  // "webRequest" or "basic"
    let timestamp: Int64?
    
    /// Returns cookies from either the dedicated field or from request headers
    var effectiveCookies: String? {
        if let cookies = cookies, !cookies.isEmpty {
            return cookies
        }
        return requestHeaders?["cookie"]
    }
    
    /// Returns the referer from either the dedicated field or from request headers
    var effectiveReferrer: String? {
        if let referrer = referrer, !referrer.isEmpty {
            return referrer
        }
        return requestHeaders?["referer"]
    }
    
    /// Returns user agent from either the dedicated field or from request headers
    var effectiveUserAgent: String? {
        if let userAgent = userAgent, !userAgent.isEmpty {
            return userAgent
        }
        return requestHeaders?["user-agent"]
    }
}

@MainActor
class BrowserExtensionListener: ObservableObject {
    static let shared = BrowserExtensionListener()
    
    private var timer: Timer?
    private let pendingDirectory: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        pendingDirectory = appSupport.appendingPathComponent("Nexus/PendingDownloads")
        
        try? FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
    }
    
    func startListening() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleNewDownload(_:)),
            name: NSNotification.Name("com.nexus.newDownload"),
            object: nil
        )
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPendingDownloads()
            }
        }
    }
    
    func stopListening() {
        DistributedNotificationCenter.default().removeObserver(self)
        timer?.invalidate()
        timer = nil
    }
    
    @objc private func handleNewDownload(_ notification: Notification) {
        Task { @MainActor in
            checkPendingDownloads()
        }
    }
    
    private func checkPendingDownloads() {
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files where file.pathExtension == "json" {
            processRequestFile(file)
        }
    }
    
    private func processRequestFile(_ file: URL) {
        let fileManager = FileManager.default
        
        guard let data = try? Data(contentsOf: file),
              let request = try? JSONDecoder().decode(BrowserDownloadRequest.self, from: data) else {
            try? fileManager.removeItem(at: file)
            return
        }
        
        try? fileManager.removeItem(at: file)
        
        Task {
            await addDownloadFromBrowser(request)
        }
    }
    
    private func addDownloadFromBrowser(_ request: BrowserDownloadRequest) async {
        // Use Security-Scoped Bookmark if available
        let destinationFolder = SecurityScopedBookmark.getDefaultDownloadDirectoryPath()
        
        guard let url = URL(string: request.url) else {
            print("Browser extension: Invalid URL - \(request.url)")
            return
        }
        
        // Parse original URL if provided (for redirect chains like testfile.org)
        let originalURL: URL? = {
            if let originalUrlString = request.originalUrl,
               !originalUrlString.isEmpty {
                return URL(string: originalUrlString)
            }
            return nil
        }()
        
        let suggestedFilename: String? = {
            guard let raw = request.filename?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                return nil
            }
            let name = URL(fileURLWithPath: raw).lastPathComponent
            return name.isEmpty ? nil : name
        }()

        do {
            // Log capture method and request details
            let captureMethod = request.captureMethod ?? "unknown"
            print("Browser extension: Received download request (capture: \(captureMethod))")
            print("Browser extension: Download URL: \(request.url)")
            
            if let originalURL = originalURL {
                print("Browser extension: Original URL: \(originalURL)")
            }
            
            // Log redirect chain if available (IDM-style capture)
            if let redirectChain = request.redirectChain, redirectChain.count > 1 {
                print("Browser extension: Redirect chain (\(redirectChain.count) hops):")
                for (index, redirectUrl) in redirectChain.enumerated() {
                    print("  [\(index + 1)] \(redirectUrl)")
                }
            }
            
            // Log captured headers if available
            if let requestHeaders = request.requestHeaders, !requestHeaders.isEmpty {
                print("Browser extension: Captured \(requestHeaders.count) request headers")
                if let auth = request.authorization {
                    print("Browser extension: Authorization header present: \(auth.prefix(20))...")
                }
            }
            
            if let contentType = request.contentType {
                print("Browser extension: Content-Type: \(contentType)")
            }
            if let contentLength = request.contentLength {
                print("Browser extension: Content-Length: \(contentLength) bytes")
            }
            
            // Store cookies for all URLs in the redirect chain
            if let cookieString = request.effectiveCookies, !cookieString.isEmpty {
                if let cookieData = cookieString.data(using: .utf8) {
                    // Store for final URL
                    CookieStorage.storeCookies(cookieData, for: url)
                    
                    // Store for original URL if different
                    if let originalURL = originalURL, originalURL != url {
                        CookieStorage.storeCookies(cookieData, for: originalURL)
                    }
                    
                    // Store for all URLs in redirect chain
                    if let redirectChain = request.redirectChain {
                        for urlString in redirectChain {
                            if let redirectURL = URL(string: urlString) {
                                CookieStorage.storeCookies(cookieData, for: redirectURL)
                            }
                        }
                    }
                    print("Browser extension: Stored cookies for download")
                }
            }
            
            // For browser downloads, always allow even without extension
            // First try as media download (YouTube, etc.)
            if let taskID = try await DownloadManager.shared.addMediaDownload(
                urlString: request.url,
                destinationFolder: destinationFolder
            ) {
                print("Browser extension: Queued media download for \(request.url) (task: \(taskID))")
            } else {
                // Not a media URL, try as regular download (without extension requirement)
                if let taskID = await DownloadManager.shared.addDownload(
                    url: url,
                    destinationPath: destinationFolder,
                    requireExtension: false,  // Browser downloads don't require extension
                    suggestedFilename: suggestedFilename
                ) {
                    await DownloadManager.shared.startDownload(taskID: taskID)
                    print("Browser extension: Started regular download for \(request.url)")
                }
            }
        } catch {
            print("Browser extension: Failed to add download - \(error)")
        }
    }
}

