import Foundation
import SwiftData

actor MediaDownloadCoordinator {
    let taskID: UUID
    let modelContainer: ModelContainer
    
    private var isRunning = false
    private var isPaused = false
    private var downloadedBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    private let minSaveInterval: TimeInterval = 0.5
    private var lastSaveTime: Date = Date()
    
    init(taskID: UUID, container: ModelContainer) {
        self.taskID = taskID
        self.modelContainer = container
    }
    
    @MainActor
    private func fetchTask() -> DownloadTask? {
        let context = modelContainer.mainContext
        let id = taskID
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
    
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        
        let context = ModelContext(modelContainer)
        let id = taskID
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })
        
        guard let task = try? context.fetch(descriptor).first else {
            isRunning = false
            return
        }
        
        task.status = .running
        try? context.save()
        
        guard let videoURLString = task.mediaVideoURLString,
              let audioURLString = task.mediaAudioURLString,
              let videoURL = URL(string: videoURLString),
              let audioURL = URL(string: audioURLString) else {
            task.status = .error
            task.errorMessage = "Missing media URLs for muxing"
            try? context.save()
            isRunning = false
            return
        }

        if let cookieData = task.httpCookies {
            CookieStorage.storeCookies(cookieData, for: videoURL)
            CookieStorage.storeCookies(cookieData, for: audioURL)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempVideoURL = tempDir.appendingPathComponent("video_\(taskID).tmp")
        let tempAudioURL = tempDir.appendingPathComponent("audio_\(taskID).tmp")
        
        defer {
            try? FileManager.default.removeItem(at: tempVideoURL)
            try? FileManager.default.removeItem(at: tempAudioURL)
        }
        
        do {
            let (videoSize, audioSize) = try await estimateSizes(videoURL: videoURL, audioURL: audioURL)
            totalBytes = videoSize + audioSize
            task.totalSize = totalBytes
            let segment = ensureProgressSegment(task: task, totalBytes: totalBytes)
            try? context.save()
            
            let videoBytes = try await downloadStream(
                url: videoURL,
                destination: tempVideoURL,
                startingOffset: 0,
                task: task,
                segment: segment,
                context: context
            )
            
            let audioBytes = try await downloadStream(
                url: audioURL,
                destination: tempAudioURL,
                startingOffset: videoBytes,
                task: task,
                segment: segment,
                context: context
            )
            
            downloadedBytes = videoBytes + audioBytes
            if totalBytes <= 0 {
                totalBytes = downloadedBytes
            }
            task.totalSize = totalBytes
            segment.endOffset = totalBytes > 0 ? totalBytes - 1 : Int64.max - 1
            try? context.save()
            
            guard await StreamMuxer.shared.isAvailable else {
                task.status = .error
                task.errorMessage = "ffmpeg not found. Please install it with: brew install ffmpeg"
                try? context.save()
                isRunning = false
                return
            }
            
            let outputExtension = (task.destinationPath as NSString).pathExtension
            let muxConfig = StreamMuxer.MuxingConfig(
                outputFormat: outputExtension.isEmpty ? "mp4" : outputExtension,
                copyStreams: true,
                videoCodec: nil,
                audioCodec: nil,
                extraArgs: []
            )
            
            let result = try await StreamMuxer.shared.mux(
                videoPath: tempVideoURL.path,
                audioPath: tempAudioURL.path,
                outputPath: task.destinationPath,
                config: muxConfig
            )
            
            if result.success {
                task.status = .complete
                try? context.save()
                await DownloadManager.shared.notifyTaskComplete(taskID: taskID)
            } else {
                task.status = .error
                task.errorMessage = result.errorMessage ?? "Muxing failed"
                try? context.save()
                await DownloadManager.shared.notifyTaskFailed(taskID: taskID)
            }
        } catch {
            task.status = .error
            task.errorMessage = error.localizedDescription
            try? context.save()
            await DownloadManager.shared.notifyTaskFailed(taskID: taskID)
        }
        
        isRunning = false
    }
    
    func pause() async {
        isPaused = true
    }
    
    func resume() async {
        guard isPaused else { return }
        isPaused = false
        await start()
    }
    
    func getProgress() -> (totalBytes: Int64, downloadedBytes: Int64, speed: Double) {
        return (totalBytes, downloadedBytes, 0)
    }
    
    private func ensureProgressSegment(task: DownloadTask, totalBytes: Int64) -> FileSegment {
        if let existing = task.segments.first {
            existing.endOffset = totalBytes > 0 ? totalBytes - 1 : Int64.max - 1
            return existing
        }
        let endOffset = totalBytes > 0 ? totalBytes - 1 : Int64.max - 1
        let segment = FileSegment(startOffset: 0, endOffset: endOffset, currentOffset: 0)
        task.segments = [segment]
        return segment
    }
    
    private func estimateSizes(videoURL: URL, audioURL: URL) async throws -> (Int64, Int64) {
        let videoHandler = NetworkHandlerFactory.handler(for: videoURL)
        let audioHandler = NetworkHandlerFactory.handler(for: audioURL)
        let videoSize: Int64
        do {
            let videoMeta = try await videoHandler.headRequest(url: videoURL)
            videoSize = max(videoMeta.contentLength, 0)
        } catch {
            videoSize = 0
        }
        
        let audioSize: Int64
        do {
            let audioMeta = try await audioHandler.headRequest(url: audioURL)
            audioSize = max(audioMeta.contentLength, 0)
        } catch {
            audioSize = 0
        }
        return (videoSize, audioSize)
    }
    
    private func downloadStream(
        url: URL,
        destination: URL,
        startingOffset: Int64,
        task: DownloadTask,
        segment: FileSegment,
        context: ModelContext
    ) async throws -> Int64 {
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        
        let handler = NetworkHandlerFactory.handler(for: url)
        let stream = try await handler.downloadRange(url: url, start: 0, end: Int64.max - 1)
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer { try? fileHandle.close() }
        
        var bytesWritten: Int64 = 0
        
        for try await chunk in stream {
            if isPaused {
                throw CancellationError()
            }
            try fileHandle.write(contentsOf: chunk)
            bytesWritten += Int64(chunk.count)
            downloadedBytes = startingOffset + bytesWritten
            segment.currentOffset = downloadedBytes
            
            let now = Date()
            if now.timeIntervalSince(lastSaveTime) >= minSaveInterval {
                try? context.save()
                lastSaveTime = now
            }
        }
        
        try? context.save()
        return bytesWritten
    }
}
