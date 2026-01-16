import Foundation
import SwiftData

struct BrowserDownloadRequest: Codable {
    let url: String
    let cookies: String?
    let referrer: String?
    let userAgent: String?
    let filename: String?
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
        
        let suggestedFilename: String? = {
            guard let raw = request.filename?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                return nil
            }
            let name = URL(fileURLWithPath: raw).lastPathComponent
            return name.isEmpty ? nil : name
        }()

        do {
            // Store cookies if provided
            if let cookieString = request.cookies, !cookieString.isEmpty {
                if let cookieData = cookieString.data(using: .utf8) {
                    CookieStorage.storeCookies(cookieData, for: url)
                    print("Browser extension: Stored cookies for \(request.url)")
                }
            }
            
            // For browser downloads, always allow even without extension
            // First try as media download (YouTube, etc.)
            if let taskID = try await DownloadManager.shared.addMediaDownload(
                urlString: request.url,
                destinationFolder: destinationFolder
            ) {
                // Store cookies in task for later use
                if let cookieString = request.cookies, !cookieString.isEmpty {
                    // Cookies are already stored in HTTPCookieStorage, and will be used automatically
                    // We also store the raw cookie string in the task for persistence
                    // This is handled in DownloadManager.addDownload/addMediaDownload
                }
                
                await DownloadManager.shared.startDownload(taskID: taskID)
                print("Browser extension: Started download for \(request.url)")
            } else {
                // Not a media URL, try as regular download (without extension requirement)
                guard let url = URL(string: request.url) else {
                    print("Browser extension: Invalid URL - \(request.url)")
                    return
                }
                
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

