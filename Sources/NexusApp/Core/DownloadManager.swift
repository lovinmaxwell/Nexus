import Combine
import Foundation
import SwiftData

@MainActor
@Observable
class DownloadManager {
    static let shared = DownloadManager()

    private var coordinators: [UUID: TaskCoordinator] = [:]
    private var modelContainer: ModelContainer?

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

    func addDownload(url: URL, destinationPath: String) -> UUID? {
        guard let container = modelContainer else { return nil }
        let context = container.mainContext

        var isDir: ObjCBool = false
        var finalPath = destinationPath

        if FileManager.default.fileExists(atPath: destinationPath, isDirectory: &isDir) {
            if isDir.boolValue {
                finalPath = (destinationPath as NSString).appendingPathComponent(
                    url.lastPathComponent)
            }
        } else {
            // Path doesn't exist. If it looks like a directory (no extension?), maybe treat as file?
            // Or maybe we should assume it IS the full path desired.
            // BUT, coming from addMediaDownload fallback, it passes destinationFolder which is likely a directory.

            // Simple heuristic: if destinationPath ends in /, it's a dir (though strings usually don't).
            // Better: Check if the user INTENDED a folder.
            // For now, let's assume if it is existing directory, we append.
            // If it doesn't exist, we use it as the file path.
        }

        // Get Default Queue
        guard let defaultQueue = QueueManager.shared.getDefaultQueue() else { return nil }

        let task = DownloadTask(sourceURL: url, destinationPath: finalPath)
        task.status = .pending
        task.queue = defaultQueue

        context.insert(task)
        try? context.save()

        // Trigger queue check
        Task { @MainActor in
            QueueManager.shared.processAllQueues()
        }

        return task.id
    }

    func addMediaDownload(urlString: String, destinationFolder: String) async throws -> UUID? {
        guard let container = modelContainer else { return nil }

        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        let extractor = MediaExtractor.shared

        if await extractor.isMediaURL(trimmedURLString) {
            let info = try await extractor.extractMediaInfo(from: trimmedURLString)
            let sanitizedTitle = info.title.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let filename = "\(sanitizedTitle).\(info.fileExtension)"
            let destinationPath = (destinationFolder as NSString).appendingPathComponent(filename)

            guard let directURL = URL(string: info.directURL) else {
                throw MediaExtractorError.noDirectURL
            }

            let context = container.mainContext
            let task = DownloadTask(sourceURL: directURL, destinationPath: destinationPath)
            task.totalSize = info.fileSize ?? 0

            // Assign to default queue
            if let defaultQueue = QueueManager.shared.getDefaultQueue() {
                task.queue = defaultQueue
                task.status = .pending
            }

            context.insert(task)
            try? context.save()

            Task { @MainActor in
                QueueManager.shared.processAllQueues()
            }

            return task.id
        } else {
            guard let url = URL(string: trimmedURLString) else { return nil }
            return addDownload(url: url, destinationPath: destinationFolder)
        }
    }
}
