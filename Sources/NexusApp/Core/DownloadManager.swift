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
        guard let container = modelContainer else {
            print("DownloadManager: modelContainer is nil")
            return nil
        }
        let context = container.mainContext

        var isDir: ObjCBool = false
        var finalPath = destinationPath

        if FileManager.default.fileExists(atPath: destinationPath, isDirectory: &isDir) {
            if isDir.boolValue {
                finalPath = (destinationPath as NSString).appendingPathComponent(
                    url.lastPathComponent)
            }
        } else {
            // Path doesn't exist - assume it's a directory path and append filename
            finalPath = (destinationPath as NSString).appendingPathComponent(
                url.lastPathComponent)
        }

        // Get or create Default Queue
        let defaultQueue: DownloadQueue
        if let existingQueue = QueueManager.shared.getDefaultQueue() {
            defaultQueue = existingQueue
        } else {
            // Create queue directly if QueueManager fails
            print("DownloadManager: Creating default queue directly")
            defaultQueue = DownloadQueue(name: "Default", maxConcurrentDownloads: 3)
            context.insert(defaultQueue)
        }

        let task = DownloadTask(sourceURL: url, destinationPath: finalPath)
        task.status = .pending
        task.queue = defaultQueue

        context.insert(task)
        
        do {
            try context.save()
            print("DownloadManager: Task saved successfully - \(task.id)")
        } catch {
            print("DownloadManager: Failed to save task - \(error)")
            return nil
        }

        // Trigger queue check
        Task { @MainActor in
            QueueManager.shared.processAllQueues()
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
                    print("DownloadManager: Starting media extraction...")
                    let info = try await extractor.extractMediaInfo(from: trimmedURLString)
                    
                    // Update task with real info
                    let sanitizedTitle = info.title
                        .replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: ":", with: "-")
                    let filename = "\(sanitizedTitle).\(info.fileExtension)"
                    let destinationPath = (destinationFolder as NSString).appendingPathComponent(filename)
                    
                    guard let directURL = URL(string: info.directURL) else {
                        task.status = .error
                        task.errorMessage = "Could not get direct download URL"
                        try? context.save()
                        return
                    }
                    
                    // Update task properties
                    task.sourceURL = directURL
                    task.destinationPath = destinationPath
                    task.totalSize = info.fileSize ?? 0
                    task.displayName = sanitizedTitle
                    task.status = .pending
                    
                    try? context.save()
                    print("DownloadManager: Media info extracted, starting download - \(taskID)")
                    
                    // Start the download
                    await self.startDownload(taskID: taskID)
                    
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
            return addDownload(url: url, destinationPath: destinationFolder)
        }
    }
}
