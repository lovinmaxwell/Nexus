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
    private func resolveDownloadURL(_ url: URL, suggestedFilename: String? = nil) async -> (URL, String)? {
        var currentURL = url
        let preferredFilename = sanitizeSuggestedFilename(suggestedFilename)
        
        // First, follow all redirects manually to get the final URL
        let maxRedirects = 10
        for redirectCount in 0..<maxRedirects {
            var request = URLRequest(url: currentURL)
            request.httpMethod = "HEAD"
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            
            // Use a session that doesn't follow redirects automatically
            let config = URLSessionConfiguration.default
            let delegate = RedirectBlockingDelegate()
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            
            do {
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    break
                }
                
                print("DownloadManager: Request to \(currentURL) returned status \(httpResponse.statusCode)")
                
                // Check for redirect (3xx)
                if (300...399).contains(httpResponse.statusCode) {
                    if let location = httpResponse.value(forHTTPHeaderField: "Location") {
                        // Handle both absolute and relative URLs
                        if let redirectURL = URL(string: location, relativeTo: currentURL)?.absoluteURL {
                            print("DownloadManager: Following redirect (\(redirectCount + 1)/\(maxRedirects)) to \(redirectURL)")
                            currentURL = redirectURL
                            continue
                        }
                    }
                    // No location header, break
                    print("DownloadManager: Redirect without Location header")
                    break
                }
                
                // Not a redirect, we've reached the final URL
                break
                
            } catch {
                print("DownloadManager: HEAD request failed: \(error), trying with default session...")
                // If HEAD fails, try with default session that follows redirects
                break
            }
        }
        
        print("DownloadManager: Final URL after redirects: \(currentURL)")
        
        // Now get the actual file info from the final URL
        var lastStatusCode: Int = 0
        for attempt in 0..<2 {
            var request = URLRequest(url: currentURL)
            let useGET = (attempt == 1)
            request.httpMethod = useGET ? "GET" : "HEAD"
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
            if useGET {
                request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            }

            do {
                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    break
                }
                
                lastStatusCode = httpResponse.statusCode
                
                // Check if URLSession followed any additional redirects
                if let finalURL = response.url, finalURL != currentURL {
                    print("DownloadManager: URLSession auto-redirected to \(finalURL)")
                    currentURL = finalURL
                }

                // If we get an error status (4xx/5xx), don't try to parse as file
                // This likely means we need authentication (cookies)
                if httpResponse.statusCode >= 400 {
                    print("DownloadManager: Server returned error \(httpResponse.statusCode) - may need authentication/cookies")
                    if !useGET {
                        continue  // Try GET
                    }
                    // Still error on GET - return nil to indicate failure
                    print("DownloadManager: Cannot resolve URL - server requires authentication. Use browser extension for cookie-protected sites.")
                    return nil
                }

                // Extract filename from Content-Disposition header if available
                var filename: String? = nil
                if let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") {
                    print("DownloadManager: Content-Disposition: \(contentDisposition)")
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
                    // Try to get filename from the final URL path
                    let urlFilename = currentURL.lastPathComponent
                    if !urlFilename.isEmpty && urlFilename != "/" && hasReasonableExtension(urlFilename) {
                        filename = urlFilename
                        print("DownloadManager: Using filename from URL path: \(filename!)")
                    } else {
                        filename = response.suggestedFilename ?? urlFilename
                    }
                    
                    if filename == nil || filename!.isEmpty || filename == "/" {
                        let pathComponents = currentURL.pathComponents.filter { $0 != "/" }
                        if let lastComponent = pathComponents.last, !lastComponent.isEmpty {
                            filename = lastComponent
                        } else {
                            filename = "download"
                        }
                    }
                }
                
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType
                print("DownloadManager: Content-Type: \(contentType ?? "nil")")
                
                let isHTML = contentType?.lowercased().contains("text/html") == true ||
                    contentType?.lowercased().contains("application/xhtml+xml") == true
                let hasExtension = hasReasonableExtension(filename ?? "")

                // If HEAD returned HTML for an extensionless URL, try GET range for real headers
                if !useGET && !hasExtension && isHTML {
                    print("DownloadManager: HEAD returned HTML for extensionless URL, trying GET range...")
                    continue
                }

                var finalFilename = filename!
                if !hasExtension, let preferredFilename, hasReasonableExtension(preferredFilename) {
                    finalFilename = preferredFilename
                }

                // If filename still doesn't have an extension, try to determine it from Content-Type
                // But DON'T add .html for error pages or generic responses
                if !hasReasonableExtension(finalFilename) {
                    if let contentType {
                        let extensionFromMIME = getFileExtension(from: contentType)
                        if !extensionFromMIME.isEmpty {
                            finalFilename = "\(finalFilename).\(extensionFromMIME)"
                            print("DownloadManager: Added extension '\(extensionFromMIME)' from Content-Type '\(contentType)'")
                        }
                    }
                }

                print("DownloadManager: Resolved URL: \(currentURL), Filename: \(finalFilename)")
                return (currentURL, finalFilename)

            } catch {
                print("DownloadManager: Error resolving URL: \(error)")
                // If HEAD failed, loop will try GET on next attempt
                continue
            }
        }
        
        // If we got error responses, return nil to indicate failure
        if lastStatusCode >= 400 {
            print("DownloadManager: Failed to resolve URL - server returned \(lastStatusCode). For protected sites, use browser extension.")
            return nil
        }
        
        // If we hit max redirects or other failure, return original
        let fallbackFilename = sanitizeSuggestedFilename(suggestedFilename)
            ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
        return (url, fallbackFilename)
    }
    
    /// Delegate that blocks automatic redirect following
    private class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            // Don't follow redirects - return nil to stop
            completionHandler(nil)
        }
    }
    
    /// Maps MIME types to file extensions
    private func getFileExtension(from mimeType: String) -> String {
        let mimeToExt: [String: String] = [
            // Images
            "image/jpeg": "jpg",
            "image/jpg": "jpg",
            "image/png": "png",
            "image/gif": "gif",
            "image/webp": "webp",
            "image/svg+xml": "svg",
            "image/bmp": "bmp",
            "image/tiff": "tiff",
            // Videos
            "video/mp4": "mp4",
            "video/mpeg": "mpg",
            "video/quicktime": "mov",
            "video/x-msvideo": "avi",
            "video/x-matroska": "mkv",
            "video/webm": "webm",
            "video/x-flv": "flv",
            "video/x-ms-wmv": "wmv",
            // Audio
            "audio/mpeg": "mp3",
            "audio/mp3": "mp3",
            "audio/wav": "wav",
            "audio/x-wav": "wav",
            "audio/flac": "flac",
            "audio/aac": "aac",
            "audio/ogg": "ogg",
            "audio/webm": "webm",
            "audio/x-m4a": "m4a",
            // Documents
            "application/pdf": "pdf",
            "application/msword": "doc",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
            "application/vnd.ms-excel": "xls",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
            "application/vnd.ms-powerpoint": "ppt",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
            "text/plain": "txt",
            "text/html": "html",
            "text/css": "css",
            "text/javascript": "js",
            "application/json": "json",
            "application/xml": "xml",
            // Archives
            "application/zip": "zip",
            "application/x-rar-compressed": "rar",
            "application/x-7z-compressed": "7z",
            "application/x-tar": "tar",
            "application/gzip": "gz",
            "application/x-bzip2": "bz2",
            "application/x-xz": "xz",
            // Executables
            "application/x-msdownload": "exe",
            "application/x-msi": "msi",
            "application/x-apple-diskimage": "dmg",
            "application/x-install-instructions": "pkg",
            "application/vnd.android.package-archive": "apk",
            // Other
            "application/octet-stream": "bin",
            "application/x-iso9660-image": "iso"
        ]
        
        // Extract base MIME type (remove charset, etc.)
        let baseMIME = mimeType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? mimeType
        let lowerMIME = baseMIME.lowercased()
        if lowerMIME == "text/html" || lowerMIME == "application/xhtml+xml" {
            return ""
        }
        return mimeToExt[lowerMIME] ?? ""
    }

    private func sanitizeSuggestedFilename(_ suggested: String?) -> String? {
        guard let suggested, !suggested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private func hasReasonableExtension(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension
        return !ext.isEmpty && ext.count <= 5
    }

    func addDownload(
        url: URL, destinationPath: String, connectionCount: Int = 8,
        queueID: UUID? = nil, startPaused: Bool = false, requireExtension: Bool = true,
        suggestedFilename: String? = nil
    ) async -> UUID? {
        guard let container = modelContainer else {
            print("DownloadManager: modelContainer is nil")
            return nil
        }
        let context = container.mainContext

        // For manual downloads, check if URL has a file extension
        if requireExtension {
            let hasExtension = hasReasonableExtension(url.lastPathComponent)
            
            if !hasExtension {
                print("DownloadManager: URL does not have a file extension: \(url.absoluteString)")
                // Try to resolve and check again
                if let resolved = await resolveDownloadURL(url, suggestedFilename: suggestedFilename) {
                    let resolvedFilename = resolved.1
                    let resolvedHasExtension = hasReasonableExtension(resolvedFilename)
                    
                    if !resolvedHasExtension {
                        print("DownloadManager: Resolved URL also lacks extension, rejecting download")
                        return nil
                    }
                } else {
                    print("DownloadManager: Could not resolve URL and no extension found, rejecting download")
                    return nil
                }
            }
        }

        // Resolve redirects and get actual filename BEFORE creating task
        let (finalURL, filename): (URL, String)
        if let resolved = await resolveDownloadURL(url, suggestedFilename: suggestedFilename) {
            finalURL = resolved.0
            filename = resolved.1
            print("DownloadManager: Resolved URL to \(finalURL.absoluteString), filename: \(filename)")
        } else {
            // Resolution failed - likely authentication required
            // For browser downloads (requireExtension=false), proceed anyway as cookies will help
            if requireExtension {
                print("DownloadManager: Could not resolve URL - site may require authentication. Use browser extension.")
                return nil
            }
            // For browser downloads, use the suggested filename or URL path
            finalURL = url
            filename = suggestedFilename ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
            print("DownloadManager: Resolution failed, proceeding with original URL and suggested filename: \(filename)")
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
        
        // Force UI update by posting notification
        NotificationCenter.default.post(name: NSNotification.Name("DownloadTaskAdded"), object: task.id)

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
