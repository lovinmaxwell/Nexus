import Foundation
import SwiftData

actor TaskCoordinator {
    let taskID: UUID
    let modelContainer: ModelContainer
    private var networkHandler: NetworkHandler?
    private var fileHandler: SparseFileHandler?

    private var isRunning = false
    private var isPaused = false
    private var activeSegmentTasks: [UUID: Task<Void, Error>] = [:]
    private var segmentProgress: [UUID: SegmentProgress] = [:]

    let maxConnections: Int
    private let persistenceInterval: TimeInterval = 1.0  // Save every second for real-time UI updates
    private var persistenceTask: Task<Void, Never>?
    private var lastSaveTime: Date = Date()
    private let minSaveInterval: TimeInterval = 0.2  // Minimum 200ms between saves

    struct SegmentProgress {
        // Atomic counter for thread-safe updates (TaskCoordinator is an actor, so this is safe)
        var bytesDownloaded: Int64
        var startTime: Date
        var lastUpdateTime: Date

        var currentSpeed: Double {
            let elapsed = lastUpdateTime.timeIntervalSince(startTime)
            return elapsed > 0 ? Double(bytesDownloaded) / elapsed : 0.0
        }

        init(bytesDownloaded: Int64 = 0, startTime: Date = Date(), lastUpdateTime: Date = Date()) {
            self.bytesDownloaded = bytesDownloaded
            self.startTime = startTime
            self.lastUpdateTime = lastUpdateTime
        }

        mutating func addBytes(_ bytes: Int64) {
            bytesDownloaded += bytes
            lastUpdateTime = Date()
        }
    }

    init(
        taskID: UUID, container: ModelContainer, maxConnections: Int = 8,
        networkHandler: NetworkHandler? = nil
    ) {
        self.taskID = taskID
        self.modelContainer = container
        self.maxConnections = min(max(maxConnections, 1), 32)
        self.networkHandler = networkHandler
    }

    @MainActor
    private func fetchTask() -> DownloadTask? {
        let context = modelContainer.mainContext
        let id = taskID
        return try? context.fetch(
            FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })
        ).first
    }

    @MainActor
    private func updateTaskStatus(_ status: TaskStatus) {
        guard let task = fetchTask() else { return }
        task.status = status
        try? modelContainer.mainContext.save()
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false

        // Connection/initialization phase - immediate UX feedback
        await updateTaskStatus(.connecting)

        let context = ModelContext(modelContainer)
        let id = taskID
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })

        guard let task = try? context.fetch(descriptor).first else {
            print("Task not found")
            isRunning = false
            return
        }

        do {
            print("TaskCoordinator: Starting download for \(task.sourceURL)")
            print("TaskCoordinator: Destination: \(task.destinationPath)")

            fileHandler = try SparseFileHandler(path: task.destinationPath)

            // Load cookies from task if available
            if let cookieData = task.httpCookies {
                CookieStorage.storeCookies(cookieData, for: task.sourceURL)
                print("TaskCoordinator: Loaded cookies from task")
            }

            // Use NetworkHandlerFactory to get appropriate handler if not already injected
            if networkHandler == nil {
                networkHandler = NetworkHandlerFactory.handler(for: task.sourceURL)
            }
            guard let handler = networkHandler else {
                print("TaskCoordinator: No network handler available for \(task.sourceURL)")
                throw NetworkError.connectionFailed
            }

            // Perform HEAD request validation before resume
            // Try URLSession first, fall back to curl if server rejects URLSession's TLS fingerprint
            print("TaskCoordinator: Performing HEAD request for validation...")
            var meta:
                (contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?)
            do {
                meta = try await handler.headRequest(url: task.sourceURL)
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == -1005 {
                    // Server rejected URLSession's TLS fingerprint — fall back to curl
                    print(
                        "TaskCoordinator: URLSession rejected by server (-1005), falling back to curl..."
                    )
                    let curlHandler = CurlNetworkHandler()
                    networkHandler = curlHandler
                    meta = try await curlHandler.headRequest(url: task.sourceURL)
                } else {
                    throw error
                }
            }
            print(
                "TaskCoordinator: HEAD request successful - Size: \(meta.contentLength), Ranges: \(meta.acceptsRanges)"
            )

            // Validate resume capability
            if task.segments.count > 0 {
                // Check if server still supports range requests
                if !meta.acceptsRanges {
                    print(
                        "TaskCoordinator: Server no longer supports range requests. Restarting download."
                    )
                    // Clear segments to force full restart
                    task.segments.removeAll()
                    try context.save()
                }

                // Validate resume integrity
                if task.totalSize > 0 {
                    // Check ETag
                    if let savedETag = task.eTag, let serverETag = meta.eTag,
                        savedETag != serverETag
                    {
                        print("ETag mismatch: Saved \(savedETag), Server \(serverETag)")
                        throw NetworkError.fileModified
                    }

                    // Check Last-Modified
                    if let savedLastModified = task.lastModified,
                        let serverLastModified = meta.lastModified,
                        savedLastModified != serverLastModified
                    {
                        print(
                            "Last-Modified mismatch: Saved \(savedLastModified), Server \(serverLastModified)"
                        )
                        throw NetworkError.fileModified
                    }

                    // Check Content-Length hasn't changed
                    if meta.contentLength > 0 && task.totalSize != meta.contentLength {
                        print(
                            "Content-Length changed: Saved \(task.totalSize), Server \(meta.contentLength)"
                        )
                        throw NetworkError.fileModified
                    }
                }
            }

            task.totalSize = meta.contentLength
            task.eTag = meta.eTag
            task.lastModified = meta.lastModified
            try context.save()

            // Transition from connecting to running - segmentation ready
            await updateTaskStatus(.running)

            // Only set file size if we know it, otherwise let it grow dynamically
            if meta.contentLength > 0 {
                try await fileHandler?.setFileSize(meta.contentLength)
            } else {
                print("TaskCoordinator: Unknown file size - will determine during download")
            }

            startPeriodicPersistence()

            if meta.acceptsRanges && meta.contentLength > 0 {
                print("Server supports ranges. Starting dynamic segmentation...")
                await downloadWithSegmentation(
                    task: task, context: context, totalSize: meta.contentLength)
            } else if meta.contentLength == 0 {
                // Unknown size - use single connection and determine size during download
                print("Unknown file size. Using single connection download...")
                try await downloadSingleConnection(
                    task: task, context: context, totalSize: 0)
            } else {
                print("Server does not support ranges. Single connection download.")
                try await downloadSingleConnection(
                    task: task, context: context, totalSize: meta.contentLength)
            }

            stopPeriodicPersistence()

            if !isPaused {
                task.status = .complete
                try context.save()
                print("Download complete!")
                await DownloadManager.shared.notifyTaskComplete(taskID: taskID)
            }

        } catch {
            print("Download error: \(error)")
            task.status = .error
            // Store error message for display in UI
            if let networkError = error as? NetworkError {
                task.errorMessage = networkErrorDescription(networkError)
            } else {
                task.errorMessage = error.localizedDescription
            }
            try? context.save()
            await DownloadManager.shared.notifyTaskFailed(taskID: taskID)
        }

        try? await fileHandler?.close()
        isRunning = false
    }

    func pause() async {
        isPaused = true
        for (_, task) in activeSegmentTasks {
            task.cancel()
        }
        activeSegmentTasks.removeAll()
        stopPeriodicPersistence()
        await persistState()
        await updateTaskStatus(.paused)
    }

    func resume() async {
        guard isPaused else { return }
        isPaused = false
        await start()
    }

    private func downloadWithSegmentation(
        task: DownloadTask, context: ModelContext, totalSize: Int64
    ) async {
        let initialSegmentCount = min(maxConnections, 4)
        let segmentSize = totalSize / Int64(initialSegmentCount)

        if task.segments.isEmpty {
            for i in 0..<initialSegmentCount {
                let start = Int64(i) * segmentSize
                let end = (i == initialSegmentCount - 1) ? totalSize - 1 : (start + segmentSize - 1)
                let segment = FileSegment(startOffset: start, endOffset: end, currentOffset: start)
                task.segments.append(segment)
            }
            try? context.save()
        }

        await withTaskGroup(of: Void.self) { group in
            let incompleteSegments = task.segments.filter { !$0.isComplete }

            for segment in incompleteSegments.prefix(maxConnections) {
                group.addTask {
                    _ = await self.downloadSegmentWithInHalf(
                        segmentID: segment.id,
                        url: task.sourceURL,
                        context: context
                    )
                }
            }

            await group.waitForAll()
        }
    }

    @discardableResult
    private func downloadSegmentWithInHalf(segmentID: UUID, url: URL, context: ModelContext) async
        -> Bool
    {
        guard !isPaused else { return true }

        let segDescriptor = FetchDescriptor<FileSegment>(
            predicate: #Predicate { $0.id == segmentID })
        guard let segment = try? context.fetch(segDescriptor).first else { return false }

        let start = segment.currentOffset
        let end = segment.endOffset

        guard start <= end else {
            segment.isComplete = true
            try? context.save()
            return true
        }

        segmentProgress[segmentID] = SegmentProgress(
            bytesDownloaded: 0,
            startTime: Date(),
            lastUpdateTime: Date()
        )

        var retryDelay: TimeInterval = 1.0
        let maxRetryDelay: TimeInterval = 60.0
        var attempt = 0
        let maxAttempts = 10
        var success = false

        while !isPaused {
            do {
                guard let handler = networkHandler else {
                    throw NetworkError.connectionFailed
                }

                // Fetch fresh offset in case it changed (though usually this actor owns it)
                let currentStart = segment.currentOffset
                let isUnknownSize = (end >= Int64.max - 1000)  // Check if end is near max (unknown size)

                if !isUnknownSize && currentStart > end {
                    segment.isComplete = true
                    try? context.save()
                    success = true
                    break
                }

                // For unknown size, download from current offset without specifying end
                // For known size, use normal range request
                let stream: AsyncThrowingStream<Data, Error>
                if isUnknownSize {
                    // Download without end limit - will stop when stream ends
                    stream = try await handler.downloadRange(
                        url: url, start: currentStart, end: Int64.max)
                } else {
                    stream = try await handler.downloadRange(
                        url: url, start: currentStart, end: end)
                }
                var currentOffset = currentStart

                // Reset retry delay on successful connection
                retryDelay = 1.0
                attempt = 0

                for try await chunk in stream {
                    guard !isPaused else { break }

                    // Apply speed limiting if enabled
                    await SpeedLimiter.shared.requestPermissionToTransfer(bytes: chunk.count)

                    try await fileHandler?.write(data: chunk, at: currentOffset)
                    currentOffset += Int64(chunk.count)
                    segment.currentOffset = currentOffset

                    // Update atomic counter (thread-safe)
                    if var progress = segmentProgress[segmentID] {
                        progress.addBytes(Int64(chunk.count))
                        segmentProgress[segmentID] = progress
                    }

                    // Save more frequently for real-time UI updates (throttled)
                    let now = Date()
                    if now.timeIntervalSince(lastSaveTime) >= minSaveInterval {
                        try? context.save()
                        lastSaveTime = now
                        // Broadcast progress for real-time UI responsiveness
                        let progress = getProgress()
                        let taskID = taskID
                        Task { @MainActor in
                            DownloadProgressBroadcaster.shared.update(
                                taskID: taskID,
                                downloadedBytes: progress.downloadedBytes,
                                totalBytes: progress.totalBytes,
                                speed: progress.speed
                            )
                        }
                    }

                    // For unknown size, completion is determined by stream ending, not offset
                    if !isUnknownSize && currentOffset > end {
                        segment.isComplete = true
                        break
                    }
                }

                // If stream ended naturally and we have unknown size, mark as complete and update totalSize
                if isUnknownSize {
                    segment.isComplete = true
                    // Update task totalSize now that we know it
                    let context = ModelContext(modelContainer)
                    let taskDescriptor = FetchDescriptor<DownloadTask>(
                        predicate: #Predicate { $0.id == taskID })
                    if let task = try? context.fetch(taskDescriptor).first {
                        task.totalSize = currentOffset
                        segment.endOffset = currentOffset - 1
                        try? context.save()
                        print(
                            "TaskCoordinator: Download complete - determined file size: \(currentOffset) bytes"
                        )
                    }
                } else if currentOffset > end {
                    segment.isComplete = true
                }

                try? context.save()

                if !isPaused && segment.isComplete {
                    success = true
                    await tryInHalfSplit(context: context, url: url)
                    break
                } else if isPaused {
                    success = true
                    break
                }

                // If stream finished without error but not complete, loop again to resume

            } catch NetworkError.serviceUnavailable {
                attempt += 1
                if attempt > maxAttempts {
                    print("Segment \(segmentID) failed: Max retries reached for 503")
                    success = false
                    break
                }
                print("Segment \(segmentID) 503 Service Unavailable. Retrying in \(retryDelay)s...")
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                retryDelay = min(retryDelay * 2, maxRetryDelay)
                continue

            } catch NetworkError.rangeNotSatisfiable {
                print("Segment \(segmentID) 416 Range Not Satisfiable. Stopping segment.")
                // Potentially mark as error or complete depending on logic.
                success = false
                break

            } catch {
                if !isPaused {
                    print("Segment \(segmentID) error: \(error)")
                    success = false
                }
                break
            }
        }

        segmentProgress.removeValue(forKey: segmentID)
        return success
    }

    private func tryInHalfSplit(context: ModelContext, url: URL) async {
        let taskDescriptor = FetchDescriptor<DownloadTask>(
            predicate: #Predicate { $0.id == taskID })
        guard let task = try? context.fetch(taskDescriptor).first else { return }

        let activeCount = segmentProgress.count
        guard activeCount < maxConnections else { return }

        let incompleteSegments = task.segments.filter { !$0.isComplete }
        guard
            let largestSegment = incompleteSegments.max(by: {
                ($0.endOffset - $0.currentOffset) < ($1.endOffset - $1.currentOffset)
            })
        else { return }

        let remainingBytes = largestSegment.endOffset - largestSegment.currentOffset
        let minSplitSize: Int64 = 256 * 1024

        guard remainingBytes > minSplitSize * 2 else { return }

        let midpoint = largestSegment.currentOffset + (remainingBytes / 2)
        let newSegment = FileSegment(
            startOffset: midpoint,
            endOffset: largestSegment.endOffset,
            currentOffset: midpoint
        )
        largestSegment.endOffset = midpoint - 1
        task.segments.append(newSegment)
        try? context.save()

        print("In-Half split: created new segment from \(midpoint) to \(newSegment.endOffset)")

        Task {
            _ = await downloadSegmentWithInHalf(
                segmentID: newSegment.id, url: url, context: context)
        }
    }

    private func downloadSingleConnection(
        task: DownloadTask, context: ModelContext, totalSize: Int64
    ) async throws {
        let segment: FileSegment
        if let existing = task.segments.first {
            segment = existing
        } else {
            // For unknown size (0), use a very large end offset that we'll never reach
            // The download will stop when the stream ends
            let endOffset = totalSize > 0 ? totalSize - 1 : Int64.max - 1
            segment = FileSegment(startOffset: 0, endOffset: endOffset, currentOffset: 0)
            task.segments.append(segment)
            try? context.save()
        }

        let success = await downloadSegmentWithInHalf(
            segmentID: segment.id, url: task.sourceURL, context: context)

        if !success {
            throw NetworkError.connectionFailed
        }
    }

    private func startPeriodicPersistence() {
        persistenceTask = Task {
            while !Task.isCancelled && isRunning {
                try? await Task.sleep(for: .seconds(persistenceInterval))
                await persistState()
            }
        }
    }

    private func stopPeriodicPersistence() {
        persistenceTask?.cancel()
        persistenceTask = nil
    }

    private func persistState() async {
        let context = ModelContext(modelContainer)
        let id = taskID
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })

        if (try? context.fetch(descriptor).first) != nil {
            try? context.save()
            let progress = getProgress()
            Task { @MainActor in
                DownloadProgressBroadcaster.shared.update(
                    taskID: id,
                    downloadedBytes: progress.downloadedBytes,
                    totalBytes: progress.totalBytes,
                    speed: progress.speed
                )
            }
        }
    }

    func getProgress() -> (totalBytes: Int64, downloadedBytes: Int64, speed: Double) {
        let speed = segmentProgress.values.reduce(0.0) { $0 + $1.currentSpeed }

        // Get total size and downloaded bytes from task segments (includes completed segments)
        let context = ModelContext(modelContainer)
        let id = taskID
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })
        if let task = try? context.fetch(descriptor).first {
            let downloaded = task.downloadedBytes
            return (task.totalSize, downloaded, speed)
        }

        let downloaded = segmentProgress.values.reduce(0) { $0 + $1.bytesDownloaded }
        return (0, downloaded, speed)
    }

    /// Converts NetworkError to a user-friendly description.
    private func networkErrorDescription(_ error: NetworkError) -> String {
        switch error {
        case .invalidURL:
            return "Invalid URL"
        case .connectionFailed:
            return "Connection failed. Please check your internet connection."
        case .serverError(let code):
            return "Server error: HTTP \(code)"
        case .invalidRange:
            return "Invalid download range"
        case .serviceUnavailable:
            return "Service temporarily unavailable. Please try again later."
        case .rangeNotSatisfiable:
            return "Server does not support range requests for this file"
        case .fileModified:
            return "File has been modified on the server. Please restart the download."
        }
    }
}
