import Foundation

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
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationFolder = downloadsDir.path
        
        do {
            if let taskID = try await DownloadManager.shared.addMediaDownload(
                urlString: request.url,
                destinationFolder: destinationFolder
            ) {
                await DownloadManager.shared.startDownload(taskID: taskID)
                print("Browser extension: Started download for \(request.url)")
            }
        } catch {
            print("Browser extension: Failed to add download - \(error)")
        }
    }
}
