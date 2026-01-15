import SafariServices

/// Handles communication between Safari Web Extension and the main Nexus app.
///
/// Safari Web Extensions use this handler to receive messages from the browser
/// and send responses back. This bridges the JavaScript extension with native Swift code.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    
    /// Processes incoming requests from the Safari Web Extension.
    ///
    /// - Parameter context: The extension context containing the request
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any] else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        let response = processMessage(message)
        
        let responseItem = NSExtensionItem()
        responseItem.userInfo = [SFExtensionMessageKey: response]
        
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }
    
    /// Processes the message from the extension and returns a response.
    ///
    /// - Parameter message: The message dictionary from JavaScript
    /// - Returns: Response dictionary to send back to JavaScript
    private func processMessage(_ message: [String: Any]) -> [String: Any] {
        guard let action = message["action"] as? String else {
            return ["success": false, "message": "Missing action"]
        }
        
        switch action {
        case "ping":
            return ["success": true, "message": "Nexus is running"]
            
        case "download":
            return handleDownloadRequest(message)
            
        default:
            return ["success": false, "message": "Unknown action: \(action)"]
        }
    }
    
    /// Handles a download request from the browser extension.
    ///
    /// - Parameter message: The download request containing URL and metadata
    /// - Returns: Response indicating success or failure
    private func handleDownloadRequest(_ message: [String: Any]) -> [String: Any] {
        guard let urlString = message["url"] as? String else {
            return ["success": false, "message": "Missing URL"]
        }
        
        let request = BrowserDownloadRequest(
            url: urlString,
            cookies: message["cookies"] as? String,
            referrer: message["referrer"] as? String,
            userAgent: message["userAgent"] as? String,
            filename: message["filename"] as? String
        )
        
        let success = savePendingDownload(request)
        
        if success {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.nexus.newDownload"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return ["success": true, "message": "Download added"]
        } else {
            return ["success": false, "message": "Failed to save download request"]
        }
    }
    
    /// Saves the download request to a shared location for the main app to process.
    ///
    /// - Parameter request: The download request to save
    /// - Returns: True if saved successfully, false otherwise
    private func savePendingDownload(_ request: BrowserDownloadRequest) -> Bool {
        let fileManager = FileManager.default
        
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        
        let pendingDir = appSupport.appendingPathComponent("Nexus/PendingDownloads")
        
        do {
            try fileManager.createDirectory(at: pendingDir, withIntermediateDirectories: true)
            
            let filename = UUID().uuidString + ".json"
            let filePath = pendingDir.appendingPathComponent(filename)
            
            let data = try JSONEncoder().encode(request)
            try data.write(to: filePath)
            
            return true
        } catch {
            return false
        }
    }
}
