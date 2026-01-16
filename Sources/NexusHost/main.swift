import Foundation

struct DownloadRequest: Codable {
    let url: String?
    let cookies: String?
    let referrer: String?
    let userAgent: String?
    let filename: String?
    let ping: Bool?
}

struct DownloadResponse: Codable {
    let success: Bool
    let message: String
    let taskId: String?
}

class NativeMessagingHost {
    private let inputHandle = FileHandle.standardInput
    private let outputHandle = FileHandle.standardOutput
    
    func run() {
        while true {
            guard let message = readMessage() else {
                break
            }
            
            let response = processMessage(message)
            writeMessage(response)
        }
    }
    
    private func readMessage() -> Data? {
        let lengthData = inputHandle.readData(ofLength: 4)
        guard lengthData.count == 4 else { return nil }
        
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard length > 0, length < 1024 * 1024 else { return nil }
        
        let messageData = inputHandle.readData(ofLength: Int(length))
        guard messageData.count == Int(length) else { return nil }
        
        return messageData
    }
    
    private func writeMessage(_ data: Data) {
        var length = UInt32(data.count)
        let lengthData = Data(bytes: &length, count: 4)
        outputHandle.write(lengthData)
        outputHandle.write(data)
    }
    
    private func processMessage(_ data: Data) -> Data {
        do {
            let request = try JSONDecoder().decode(DownloadRequest.self, from: data)
            
            // Handle ping request
            if request.ping == true {
                let response = DownloadResponse(
                    success: true,
                    message: "Nexus is running",
                    taskId: nil
                )
                return try JSONEncoder().encode(response)
            }
            
            // Handle download request
            guard let url = request.url, !url.isEmpty else {
                let response = DownloadResponse(
                    success: false,
                    message: "No URL provided",
                    taskId: nil
                )
                return try JSONEncoder().encode(response)
            }
            
            // Send to main app via distributed notification or file-based IPC
            let success = sendToMainApp(request: request)
            
            let response = DownloadResponse(
                success: success,
                message: success ? "Download added to Nexus" : "Failed to communicate with Nexus",
                taskId: success ? UUID().uuidString : nil
            )
            
            return try JSONEncoder().encode(response)
        } catch {
            let response = DownloadResponse(
                success: false,
                message: "Invalid request: \(error.localizedDescription)",
                taskId: nil
            )
            return (try? JSONEncoder().encode(response)) ?? Data()
        }
    }
    
    private func sendToMainApp(request: DownloadRequest) -> Bool {
        guard let url = request.url else { return false }
        
        // Write request to a shared location that main app monitors
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nexusDir = appSupport.appendingPathComponent("Nexus")
        let pendingDir = nexusDir.appendingPathComponent("PendingDownloads")
        
        do {
            try fileManager.createDirectory(at: pendingDir, withIntermediateDirectories: true)
            
            // Create a simple request structure for the main app
            struct BrowserRequest: Codable {
                let url: String
                let cookies: String?
                let referrer: String?
                let userAgent: String?
                let filename: String?
            }
            
            let browserRequest = BrowserRequest(
                url: url,
                cookies: request.cookies,
                referrer: request.referrer,
                userAgent: request.userAgent,
                filename: request.filename
            )
            
            let requestFile = pendingDir.appendingPathComponent("\(UUID().uuidString).json")
            let data = try JSONEncoder().encode(browserRequest)
            try data.write(to: requestFile)
            
            // Post distributed notification
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.nexus.newDownload"),
                object: nil,
                userInfo: ["file": requestFile.path],
                deliverImmediately: true
            )
            
            return true
        } catch {
            return false
        }
    }
}

// Entry point
let host = NativeMessagingHost()
host.run()
