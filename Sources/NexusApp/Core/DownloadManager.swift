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
}
