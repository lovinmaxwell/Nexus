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
    private let persistenceInterval: TimeInterval = 30.0
    private var persistenceTask: Task<Void, Never>?

    struct SegmentProgress {
        var bytesDownloaded: Int64
        var startTime: Date
        var lastUpdateTime: Date
        var currentSpeed: Double
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

        await updateTaskStatus(.running)

        let context = ModelContext(modelContainer)
        let id = taskID
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })

        guard let task = try? context.fetch(descriptor).first else {
            print("Task not found")
            isRunning = false
            return
        }

        do {
            fileHandler = try SparseFileHandler(path: task.destinationPath)

            // Use NetworkHandlerFactory to get appropriate handler if not already injected
            if networkHandler == nil {
                networkHandler = NetworkHandlerFactory.handler(for: task.sourceURL)
            }
            guard let handler = networkHandler else {
                throw NetworkError.connectionFailed
            }

            let meta = try await handler.headRequest(url: task.sourceURL)

            task.totalSize = meta.contentLength
            task.eTag = meta.eTag
            task.lastModified = meta.lastModified
            try context.save()

            try await fileHandler?.setFileSize(meta.contentLength)

            startPeriodicPersistence()

            if meta.acceptsRanges && meta.contentLength > 0 {
                print("Server supports ranges. Starting dynamic segmentation...")
                await downloadWithSegmentation(
                    task: task, context: context, totalSize: meta.contentLength)
            } else {
                print("Server does not support ranges. Single connection download.")
                await downloadSingleConnection(
                    task: task, context: context, totalSize: meta.contentLength)
            }

            stopPeriodicPersistence()

            if !isPaused {
                task.status = .complete
                try context.save()
                print("Download complete!")
            }

        } catch {
            print("Download error: \(error)")
            task.status = .error
            try? context.save()
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
                    await self.downloadSegmentWithInHalf(
                        segmentID: segment.id,
                        url: task.sourceURL,
                        context: context
                    )
                }
            }

            await group.waitForAll()
        }
    }

    private func downloadSegmentWithInHalf(segmentID: UUID, url: URL, context: ModelContext) async {
        guard !isPaused else { return }

        let segDescriptor = FetchDescriptor<FileSegment>(
            predicate: #Predicate { $0.id == segmentID })
        guard let segment = try? context.fetch(segDescriptor).first else { return }

        let start = segment.currentOffset
        let end = segment.endOffset

        guard start <= end else {
            segment.isComplete = true
            try? context.save()
            return
        }

        segmentProgress[segmentID] = SegmentProgress(
            bytesDownloaded: 0,
            startTime: Date(),
            lastUpdateTime: Date(),
            currentSpeed: 0
        )

        var retryDelay: TimeInterval = 1.0
        let maxRetryDelay: TimeInterval = 60.0
        var attempt = 0
        let maxAttempts = 10

        while !isPaused {
            do {
                guard let handler = networkHandler else {
                    throw NetworkError.connectionFailed
                }

                // Fetch fresh offset in case it changed (though usually this actor owns it)
                let currentStart = segment.currentOffset
                if currentStart > end {
                    segment.isComplete = true
                    try? context.save()
                    break
                }

                let stream = try await handler.downloadRange(
                    url: url, start: currentStart, end: end)
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

                    if var progress = segmentProgress[segmentID] {
                        progress.bytesDownloaded += Int64(chunk.count)
                        progress.lastUpdateTime = Date()
                        let elapsed = progress.lastUpdateTime.timeIntervalSince(progress.startTime)
                        if elapsed > 0 {
                            progress.currentSpeed = Double(progress.bytesDownloaded) / elapsed
                        }
                        segmentProgress[segmentID] = progress
                    }

                    if currentOffset > end {
                        segment.isComplete = true
                        break
                    }
                }

                if currentOffset > end {
                    segment.isComplete = true
                }

                try? context.save()

                if !isPaused && segment.isComplete {
                    await tryInHalfSplit(context: context, url: url)
                    break
                } else if isPaused {
                    break
                }

                // If stream finished without error but not complete, loop again to resume

            } catch NetworkError.serviceUnavailable {
                attempt += 1
                if attempt > maxAttempts {
                    print("Segment \(segmentID) failed: Max retries reached for 503")
                    break
                }
                print("Segment \(segmentID) 503 Service Unavailable. Retrying in \(retryDelay)s...")
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                retryDelay = min(retryDelay * 2, maxRetryDelay)
                continue

            } catch NetworkError.rangeNotSatisfiable {
                print("Segment \(segmentID) 416 Range Not Satisfiable. Stopping segment.")
                // Potentially mark as error or complete depending on logic.
                // For now, stop to avoid infinite loop.
                break

            } catch {
                if !isPaused {
                    print("Segment \(segmentID) error: \(error)")
                }
                break
            }
        }

        segmentProgress.removeValue(forKey: segmentID)
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
            await downloadSegmentWithInHalf(segmentID: newSegment.id, url: url, context: context)
        }
    }

    private func downloadSingleConnection(
        task: DownloadTask, context: ModelContext, totalSize: Int64
    ) async {
        let segment: FileSegment
        if let existing = task.segments.first {
            segment = existing
        } else {
            segment = FileSegment(startOffset: 0, endOffset: totalSize - 1, currentOffset: 0)
            task.segments.append(segment)
            try? context.save()
        }

        await downloadSegmentWithInHalf(
            segmentID: segment.id, url: task.sourceURL, context: context)
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
            print("State persisted for task \(id)")
        }
    }

    func getProgress() -> (totalBytes: Int64, downloadedBytes: Int64, speed: Double) {
        let downloaded = segmentProgress.values.reduce(0) { $0 + $1.bytesDownloaded }
        let speed = segmentProgress.values.reduce(0.0) { $0 + $1.currentSpeed }
        return (0, downloaded, speed)
    }
}
