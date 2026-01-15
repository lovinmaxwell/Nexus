import Foundation
import SwiftData
import Combine

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
    
    func cancelDownload(taskID: UUID) async {
        await coordinators[taskID]?.pause()
        coordinators.removeValue(forKey: taskID)
    }
    
    func getProgress(taskID: UUID) async -> (totalBytes: Int64, downloadedBytes: Int64, speed: Double)? {
        return await coordinators[taskID]?.getProgress()
    }
    
    func addDownload(url: URL, destinationPath: String) -> UUID? {
        guard let container = modelContainer else { return nil }
        let context = container.mainContext

        let task = DownloadTask(sourceURL: url, destinationPath: destinationPath)
        context.insert(task)
        try? context.save()

        return task.id
    }

    func addMediaDownload(urlString: String, destinationFolder: String) async throws -> UUID? {
        guard let container = modelContainer else { return nil }

        let extractor = MediaExtractor.shared

        if await extractor.isMediaURL(urlString) {
            let info = try await extractor.extractMediaInfo(from: urlString)
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
            context.insert(task)
            try? context.save()

            return task.id
        } else {
            guard let url = URL(string: urlString) else { return nil }
            return addDownload(url: url, destinationPath: destinationFolder)
        }
    }
}