import Foundation
import SwiftData

@Model
final class DownloadQueue {
    var id: UUID
    var name: String
    var maxConcurrentDownloads: Int
    var isActive: Bool
    var createdDate: Date
    
    @Relationship(deleteRule: .nullify, inverse: \DownloadTask.queue)
    var tasks: [DownloadTask]
    
    init(name: String, maxConcurrentDownloads: Int = 3) {
        self.id = UUID()
        self.name = name
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.isActive = true
        self.createdDate = Date()
        self.tasks = []
    }
    
    var pendingTasks: [DownloadTask] {
        tasks.filter { $0.status == .paused }
    }
    
    var activeTasks: [DownloadTask] {
        tasks.filter { $0.status == .running }
    }
    
    var completedTasks: [DownloadTask] {
        tasks.filter { $0.status == .complete }
    }
}

@MainActor
@Observable
class QueueManager {
    static let shared = QueueManager()
    
    private var modelContainer: ModelContainer?
    private var processingTimer: Timer?
    
    private init() {}
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }
    
    func startProcessing() {
        processingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.processQueues()
            }
        }
    }
    
    func stopProcessing() {
        processingTimer?.invalidate()
        processingTimer = nil
    }
    
    private func processQueues() {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        
        let descriptor = FetchDescriptor<DownloadQueue>(predicate: #Predicate { $0.isActive })
        guard let queues = try? context.fetch(descriptor) else { return }
        
        for queue in queues {
            processQueue(queue)
        }
    }
    
    private func processQueue(_ queue: DownloadQueue) {
        let activeCount = queue.activeTasks.count
        let slotsAvailable = queue.maxConcurrentDownloads - activeCount
        
        guard slotsAvailable > 0 else { return }
        
        let pendingTasks = queue.pendingTasks.sorted { $0.createdDate < $1.createdDate }
        let tasksToStart = pendingTasks.prefix(slotsAvailable)
        
        for task in tasksToStart {
            Task {
                await DownloadManager.shared.startDownload(taskID: task.id)
            }
        }
    }
    
    func createQueue(name: String, maxConcurrent: Int = 3) -> DownloadQueue? {
        guard let container = modelContainer else { return nil }
        let context = container.mainContext
        
        let queue = DownloadQueue(name: name, maxConcurrentDownloads: maxConcurrent)
        context.insert(queue)
        try? context.save()
        
        return queue
    }
    
    func deleteQueue(_ queue: DownloadQueue) {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        
        context.delete(queue)
        try? context.save()
    }
    
    func addTaskToQueue(_ task: DownloadTask, queue: DownloadQueue) {
        task.queue = queue
        try? modelContainer?.mainContext.save()
    }
    
    func removeTaskFromQueue(_ task: DownloadTask) {
        task.queue = nil
        try? modelContainer?.mainContext.save()
    }
    
    func getDefaultQueue() -> DownloadQueue? {
        guard let container = modelContainer else { return nil }
        let context = container.mainContext
        
        let descriptor = FetchDescriptor<DownloadQueue>(predicate: #Predicate { $0.name == "Default" })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        return createQueue(name: "Default", maxConcurrent: 3)
    }
}
