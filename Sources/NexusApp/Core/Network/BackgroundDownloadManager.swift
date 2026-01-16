import Foundation
import SwiftData

/// Manages background downloads using URLSessionConfiguration.background.
///
/// This allows downloads to continue even when the app is not in the foreground
/// or has been terminated. On macOS, this is particularly useful for large downloads
/// that should continue after the user closes the app.
class BackgroundDownloadManager: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    static let shared = BackgroundDownloadManager()
    
    private var backgroundSession: URLSession!
    private var activeDownloads: [URL: UUID] = [:]  // Maps download URL to task ID
    private var modelContainer: ModelContainer?
    
    private override init() {
        super.init()
        setupBackgroundSession()
    }
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }
    
    /// Sets up the background URLSession with proper configuration.
    private func setupBackgroundSession() {
        let identifier = "com.projectnexus.background.downloads"
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false  // Start immediately
        configuration.sessionSendsLaunchEvents = true  // Notify app when download completes
        configuration.allowsCellularAccess = true
        configuration.waitsForConnectivity = true
        
        backgroundSession = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }
    
    /// Starts a background download for a task.
    ///
    /// - Parameters:
    ///   - taskID: The download task ID
    ///   - url: The URL to download
    /// - Returns: The URLSessionDownloadTask, or nil if creation fails
    @MainActor
    func startBackgroundDownload(taskID: UUID, url: URL) -> URLSessionDownloadTask? {
        guard let container = modelContainer else {
            print("BackgroundDownloadManager: modelContainer not set")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        // Load cookies if available
        let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        if let task = try? context.fetch(descriptor).first,
           let cookieData = task.httpCookies {
            CookieStorage.storeCookies(cookieData, for: url)
        }
        
        let downloadTask = backgroundSession.downloadTask(with: request)
        activeDownloads[url] = taskID
        
        // Store task ID in userInfo for restoration
        downloadTask.taskDescription = taskID.uuidString
        
        downloadTask.resume()
        print("BackgroundDownloadManager: Started background download for task \(taskID)")
        
        return downloadTask
    }
    
    /// Cancels a background download.
    ///
    /// - Parameter url: The URL of the download to cancel
    func cancelBackgroundDownload(url: URL) {
        // Find the task and cancel it
        backgroundSession.getAllTasks { tasks in
            for task in tasks {
                if let taskURL = task.originalRequest?.url, taskURL == url {
                    task.cancel()
                    self.activeDownloads.removeValue(forKey: url)
                    print("BackgroundDownloadManager: Cancelled background download for \(url)")
                }
            }
        }
    }
    
    // MARK: - URLSessionDelegate
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("BackgroundDownloadManager: Background session finished events")
        // Notify app that background downloads completed
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("BackgroundDownloadsCompleted"), object: nil)
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let url = task.originalRequest?.url else { return }
        
        if let error = error {
            print("BackgroundDownloadManager: Download failed for \(url): \(error)")
            if let taskID = activeDownloads[url] {
                handleDownloadError(taskID: taskID, error: error)
            }
        }
        
        activeDownloads.removeValue(forKey: url)
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let url = downloadTask.originalRequest?.url,
              let taskID = activeDownloads[url] ?? (downloadTask.taskDescription.flatMap { UUID(uuidString: $0) }) else {
            print("BackgroundDownloadManager: Could not find task ID for completed download")
            return
        }
        
        print("BackgroundDownloadManager: Download completed for task \(taskID)")
        
        guard let container = modelContainer else {
            print("BackgroundDownloadManager: modelContainer not set")
            return
        }
        
        Task { @MainActor in
            let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        
        guard let task = try? context.fetch(descriptor).first else {
            print("BackgroundDownloadManager: Task not found: \(taskID)")
            return
        }
        
        // Move file from temporary location to destination
        let fileManager = FileManager.default
        let destinationURL = URL(fileURLWithPath: task.destinationPath)
        
        do {
            // Create destination directory if needed
            let destinationDir = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            
            // Remove existing file if present
            if fileManager.fileExists(atPath: task.destinationPath) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Move downloaded file to destination
            try fileManager.moveItem(at: location, to: destinationURL)
            
            // Update task status
            task.status = .complete
            try context.save()
            
            print("BackgroundDownloadManager: File moved to \(task.destinationPath)")
            
            // Notify DownloadManager
            DownloadManager.shared.notifyTaskComplete(taskID: taskID)
            
        } catch {
            print("BackgroundDownloadManager: Failed to move file: \(error)")
            task.status = .error
            task.errorMessage = "Failed to save file: \(error.localizedDescription)"
            try? context.save()
            DownloadManager.shared.notifyTaskFailed(taskID: taskID)
        }
        }
        
        Task { @MainActor in
            activeDownloads.removeValue(forKey: url)
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let url = downloadTask.originalRequest?.url,
              let taskID = activeDownloads[url] ?? (downloadTask.taskDescription.flatMap { UUID(uuidString: $0) }) else {
            return
        }
        
        // Update task progress
        guard let container = modelContainer else { return }
        
        Task { @MainActor in
            let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        
        if let task = try? context.fetch(descriptor).first {
            // Update segments if they exist, or create a single segment
            if task.segments.isEmpty && totalBytesExpectedToWrite > 0 {
                let segment = FileSegment(
                    startOffset: 0,
                    endOffset: totalBytesExpectedToWrite - 1,
                    currentOffset: totalBytesWritten
                )
                task.segments.append(segment)
            } else if let segment = task.segments.first {
                segment.currentOffset = totalBytesWritten
            }
            
            task.totalSize = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : task.totalSize
            try? context.save()
        }
        }
    }
    
    /// Handles download errors.
    private func handleDownloadError(taskID: UUID, error: Error) {
        guard let container = modelContainer else { return }
        
        Task { @MainActor in
            let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        
        if let task = try? context.fetch(descriptor).first {
            task.status = .error
            task.errorMessage = error.localizedDescription
            try? context.save()
            DownloadManager.shared.notifyTaskFailed(taskID: taskID)
        }
        }
    }
    
    /// Restores background downloads when app launches.
    ///
    /// This should be called on app startup to handle downloads that completed
    /// while the app was terminated.
    @MainActor
    func restoreBackgroundDownloads() {
        guard modelContainer != nil else { return }
        
        backgroundSession.getAllTasks { [weak self] tasks in
            print("BackgroundDownloadManager: Restoring \(tasks.count) background download tasks")
            
            Task { @MainActor in
                guard let self = self else { return }
                for task in tasks {
                    if let taskDescription = task.taskDescription,
                       let taskID = UUID(uuidString: taskDescription) {
                        // Task is still active, update activeDownloads
                        if let url = task.originalRequest?.url {
                            self.activeDownloads[url] = taskID
                        }
                    }
                }
            }
        }
    }
}
