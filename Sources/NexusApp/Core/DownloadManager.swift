import Combine
import Foundation
import SwiftData

@MainActor
@Observable
class DownloadManager {
    static let shared = DownloadManager()

    private var coordinators: [UUID: TaskCoordinator] = [:]
    private(set) var modelContainer: ModelContainer?

    var maxConnectionsPerDownload: Int = 8
    var maxConcurrentDownloads: Int = 3

    private init() {}

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        QueueManager.shared.setModelContext(container.mainContext)
    }

    func startDownload(taskID: UUID) async {
        guard let container = modelContainer else { return }

        if coordinators[taskID] == nil {
            let coordinator = TaskCoordinator(
                taskID: taskID,
                container: container,
                maxConnections: maxConnectionsPerDownload
            )
            coordinators[taskID] = coordinator
        }

        if let coordinator = coordinators[taskID] {
            await coordinator.start()
        }
    }

    func pauseDownload(taskID: UUID) async {
        await coordinators[taskID]?.pause()
    }

    func resumeDownload(taskID: UUID) async {
        await coordinators[taskID]?.resume()
    }

    func notifyTaskComplete(taskID: UUID) {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        if let task = try? context.fetch(descriptor).first {
            QueueManager.shared.taskDidComplete(task)
        }

        // Cleanup coordinator
        coordinators.removeValue(forKey: taskID)
    }

    func notifyTaskFailed(taskID: UUID) {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        if let task = try? context.fetch(descriptor).first {
            QueueManager.shared.taskDidFail(task)
        }

        // Cleanup coordinator? Maybe keep it for retry?
        // For now remove to free resources.
        coordinators.removeValue(forKey: taskID)
    }

    func cancelDownload(taskID: UUID) async {
        await coordinators[taskID]?.pause()
        coordinators.removeValue(forKey: taskID)
    }

    func getProgress(taskID: UUID) async -> (
        totalBytes: Int64, downloadedBytes: Int64, speed: Double
    )? {
        return await coordinators[taskID]?.getProgress()
    }

    /// Resolves redirects and extracts the actual download URL and filename.
    ///
    /// - Parameter url: The initial URL that may redirect.
    /// - Returns: Tuple of (final URL, filename) or nil if resolution fails.
    private func resolveDownloadURL(_ url: URL) async -> (URL, String)? {
        var currentURL = url
        
        // Try up to two attempts: first with HEAD, then fallback to GET if needed
        for attempt in 0..<2 {
            var request = URLRequest(url: currentURL)
            let useGET = (attempt == 1)
            request.httpMethod = useGET ? "GET" : "HEAD"
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")

            do {
                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    break
                }

                // URLSession follows redirects automatically, so response.url is the final URL
                if let finalURL = response.url, finalURL != currentURL {
                    print("DownloadManager: URLSession auto-redirected to \(finalURL)")
                    currentURL = finalURL
                }

                // If HEAD returns 403/405, try GET instead
                if !useGET && (httpResponse.statusCode == 403 || httpResponse.statusCode == 405) {
                    print("DownloadManager: HEAD not allowed (status \(httpResponse.statusCode)), trying GET request...")
                    continue
                }

                // Extract filename from Content-Disposition header if available
                var filename: String? = nil
                if let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") {
                    if let filenameMatch = contentDisposition.range(of: #"filename\*?=(['"]?)([^'";\n]+)\1"#, options: .regularExpression) {
                        let filenamePart = String(contentDisposition[filenameMatch])
                        if let equalsIndex = filenamePart.firstIndex(of: "=") {
                            var name = String(filenamePart[filenamePart.index(after: equalsIndex)...])
                            name = name.trimmingCharacters(in: .whitespaces)
                            if name.hasPrefix("\"") && name.hasSuffix("\"") {
                                name = String(name.dropFirst().dropLast())
                            } else if name.hasPrefix("'") && name.hasSuffix("'") {
                                name = String(name.dropFirst().dropLast())
                            }
                            if name.hasPrefix("UTF-8''") {
                                name = String(name.dropFirst(7))
                                if let decoded = name.removingPercentEncoding {
                                    name = decoded
                                }
                            }
                            filename = name
                        }
                    }
                }

                if filename == nil || filename!.isEmpty {
                    filename = currentURL.lastPathComponent
                    if filename == nil || filename!.isEmpty || filename == "/" {
                        let pathComponents = currentURL.pathComponents.filter { $0 != "/" }
                        if let lastComponent = pathComponents.last, !lastComponent.isEmpty {
                            filename = lastComponent
                        } else {
                            filename = "download"
                        }
                    }
                }

                print("DownloadManager: Resolved URL: \(currentURL), Filename: \(filename!)")
                return (currentURL, filename!)

            } catch {
                print("DownloadManager: Error resolving URL: \(error)")
                // If HEAD failed, loop will try GET on next attempt
                continue
            }
        }
        
        // If we hit max redirects or failed, return original
        let fallbackFilename = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        return (url, fallbackFilename)
    }

    func addDownload(
        url: URL, destinationPath: String, connectionCount: Int = 8,
        queueID: UUID? = nil, startPaused: Bool = false
    ) async -> UUID? {
        guard let container = modelContainer else {
            print("DownloadManager: modelContainer is nil")
            return nil
        }
        let context = container.mainContext

        // Resolve redirects and get actual filename BEFORE creating task
        let (finalURL, filename): (URL, String)
        if let resolved = await resolveDownloadURL(url) {
            finalURL = resolved.0
            filename = resolved.1
            print("DownloadManager: Resolved URL to \(finalURL.absoluteString), filename: \(filename)")
        } else {
            finalURL = url
            filename = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
            print("DownloadManager: Could not resolve redirects, using original URL")
        }

        var isDir: ObjCBool = false
        var finalPath = destinationPath

        if FileManager.default.fileExists(atPath: destinationPath, isDirectory: &isDir) {
            if isDir.boolValue {
                finalPath = (destinationPath as NSString).appendingPathComponent(filename)
            } else {
                // If destinationPath is a file, use its directory + new filename
                let dir = (destinationPath as NSString).deletingLastPathComponent
                finalPath = (dir as NSString).appendingPathComponent(filename)
            }
        } else {
            // Path doesn't exist - assume it's a directory path and append filename
            finalPath = (destinationPath as NSString).appendingPathComponent(filename)
        }

        // Get queue (selected or default)
        let queue: DownloadQueue
        if let queueID = queueID {
            let descriptor = FetchDescriptor<DownloadQueue>(predicate: #Predicate { $0.id == queueID })
            if let foundQueue = try? context.fetch(descriptor).first {
                queue = foundQueue
            } else {
                // Fallback to default if queue not found
                queue = QueueManager.shared.getDefaultQueue() ?? DownloadQueue(name: "Default", maxConcurrentDownloads: 3)
                context.insert(queue)
            }
        } else {
            if let existingQueue = QueueManager.shared.getDefaultQueue() {
                queue = existingQueue
            } else {
                print("DownloadManager: Creating default queue directly")
                queue = DownloadQueue(name: "Default", maxConcurrentDownloads: 3)
                context.insert(queue)
            }
        }

        let task = DownloadTask(sourceURL: finalURL, destinationPath: finalPath)
        task.status = startPaused ? .paused : .pending
        task.queue = queue
        task.displayName = filename
        
        // Store cookies from HTTPCookieStorage if available
        if let cookieData = CookieStorage.serializeCookies(for: finalURL) {
            task.httpCookies = cookieData
        }
        
        // Store connection count preference (we'll use this when creating TaskCoordinator)
        // For now, we'll use the global maxConnectionsPerDownload, but could store per-task

        context.insert(task)
        
        do {
            try context.save()
            print("DownloadManager: Task saved successfully - \(task.id) with filename: \(filename)")
        } catch {
            print("DownloadManager: Failed to save task - \(error)")
            return nil
        }

        // Trigger queue check (only if not paused)
        if !startPaused {
            Task { @MainActor in
                QueueManager.shared.processAllQueues()
            }
        }

        return task.id
    }

    func addMediaDownload(urlString: String, destinationFolder: String) async throws -> UUID? {
        guard let container = modelContainer else {
            print("DownloadManager: modelContainer is nil in addMediaDownload")
            return nil
        }

        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        print("DownloadManager: Adding download for URL: \(trimmedURLString)")

        let extractor = MediaExtractor.shared

        // isMediaURL is nonisolated, no await needed
        if extractor.isMediaURL(trimmedURLString) {
            print("DownloadManager: Detected as media URL")
            
            // Create task IMMEDIATELY with placeholder info so it shows in UI
            guard let placeholderURL = URL(string: trimmedURLString) else {
                return nil
            }
            
            let context = container.mainContext
            let task = DownloadTask(
                sourceURL: placeholderURL,
                destinationPath: destinationFolder,
                status: .extracting  // New status for extracting
            )
            task.displayName = "Extracting: \(placeholderURL.host ?? "media")..."
            
            // Get or create Default Queue
            let defaultQueue: DownloadQueue
            if let existingQueue = QueueManager.shared.getDefaultQueue() {
                defaultQueue = existingQueue
            } else {
                defaultQueue = DownloadQueue(name: "Default", maxConcurrentDownloads: 3)
                context.insert(defaultQueue)
            }
            task.queue = defaultQueue

            context.insert(task)
            try? context.save()
            
            let taskID = task.id
            print("DownloadManager: Task added to UI immediately - \(taskID)")
            
            // Extract media info in background, then update the task
            Task { @MainActor in
                do {
                    // Check if yt-dlp is available
                    let isAvailable = await extractor.isYtDlpAvailable
                    if !isAvailable {
                        task.status = .error
                        task.errorMessage = "yt-dlp not found. Please install it with: brew install yt-dlp"
                        try? context.save()
                        print("DownloadManager: yt-dlp not available")
                        return
                    }
                    
                    print("DownloadManager: Starting media extraction...")
                    let info = try await extractor.extractMediaInfo(from: trimmedURLString)
                    
                    // Update task with real info
                    let sanitizedTitle = info.title
                        .replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: ":", with: "-")
                        .replacingOccurrences(of: "\"", with: "'")
                        .replacingOccurrences(of: "\n", with: " ")
                    let filename = "\(sanitizedTitle).\(info.fileExtension)"
                    let destinationPath = (destinationFolder as NSString).appendingPathComponent(filename)
                    
                    // For YouTube videos, the directURL might be the original URL
                    // We'll use yt-dlp to download it directly
                    let downloadURL: URL
                    if info.directURL == trimmedURLString || info.directURL.isEmpty {
                        // No direct URL available - use original URL
                        downloadURL = placeholderURL
                        print("DownloadManager: No direct URL, will use yt-dlp for download")
                    } else {
                        guard let url = URL(string: info.directURL) else {
                            task.status = .error
                            task.errorMessage = "Could not parse download URL"
                            try? context.save()
                            return
                        }
                        downloadURL = url
                    }
                    
                    // Update task properties
                    task.sourceURL = downloadURL
                    task.destinationPath = destinationPath
                    task.totalSize = info.fileSize ?? 0
                    task.displayName = sanitizedTitle
                    task.status = .pending
                    
                    // Store original URL in a way we can detect it's a YouTube video
                    // We'll check this in TaskCoordinator to use yt-dlp for download
                    if trimmedURLString.contains("youtube.com") || trimmedURLString.contains("youtu.be") {
                        // Mark this as needing yt-dlp download
                        task.httpCookies = trimmedURLString.data(using: .utf8) // Temporary storage for original URL
                    }
                    
                    try? context.save()
                    print("DownloadManager: Media info extracted, starting download - \(taskID)")
                    
                    // Start the download
                    await self.startDownload(taskID: taskID)
                    
                } catch let error as MediaExtractorError {
                    print("DownloadManager: Media extraction failed - \(error)")
                    task.status = .error
                    task.errorMessage = error.errorDescription ?? "Extraction failed"
                    try? context.save()
                } catch {
                    print("DownloadManager: Media extraction failed - \(error)")
                    task.status = .error
                    task.errorMessage = error.localizedDescription
                    try? context.save()
                }
            }
            
            return taskID
            
        } else {
            print("DownloadManager: Regular URL, using addDownload")
            // Try to create URL, handling spaces and special characters
            var urlToUse: URL?
            if let url = URL(string: trimmedURLString) {
                urlToUse = url
            } else if let encoded = trimmedURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: encoded) {
                urlToUse = url
            }
            
            guard let url = urlToUse else {
                print("DownloadManager: Invalid URL: \(trimmedURLString)")
                return nil
            }
            return await addDownload(url: url, destinationPath: destinationFolder)
        }
    }
}
