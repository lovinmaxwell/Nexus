import Foundation
import SwiftData

@MainActor
class QueueManager: ObservableObject {
    static let shared = QueueManager()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Trigger processing of all active queues
    func processAllQueues() {
        guard let context = modelContext else { return }

        do {
            let activeQueuesDescriptor = FetchDescriptor<DownloadQueue>(
                predicate: #Predicate { $0.isActive })
            let activeQueues = try context.fetch(activeQueuesDescriptor)

            for queue in activeQueues {
                try processQueue(queue, context: context)
            }
        } catch {
            print("QueueManager: Failed to fetch queues - \(error)")
        }
    }

    private func processQueue(_ queue: DownloadQueue, context: ModelContext) throws {
        // Refresh queue tasks logic
        let runningCount = queue.activeTasks.count
        let effectiveLimit = queue.mode == .sequential ? 1 : queue.maxConcurrentDownloads

        if runningCount < effectiveLimit {
            let slotsAvailable = effectiveLimit - runningCount
            if slotsAvailable > 0 {
                // Find pending tasks in this queue
                // Sort by priority (high to low), then by createdDate (old to new)
                let pendingTasks = queue.tasks
                    .filter { $0.status == .pending }
                    .sorted { (t1, t2) -> Bool in
                        if t1.priority != t2.priority {
                            return t1.priority > t2.priority
                        }
                        return t1.createdDate < t2.createdDate
                    }
                    .prefix(slotsAvailable)

                for task in pendingTasks {
                    print("QueueManager: Starting task \(task.id) in queue \(queue.name)")
                    Task {
                        await DownloadManager.shared.startDownload(taskID: task.id)
                    }
                }
            }
        }
    }

    func createQueue(name: String, maxConcurrent: Int = 3) -> DownloadQueue? {
        guard let context = modelContext else { return nil }
        let queue = DownloadQueue(name: name, maxConcurrentDownloads: maxConcurrent)
        context.insert(queue)
        try? context.save()
        return queue
    }

    func getDefaultQueue() -> DownloadQueue? {
        guard let context = modelContext else { return nil }
        // Note: predicate string matching might be finicky, filtering in memory for safety given previous issues
        // or trying exact predicate.
        // #Predicate { $0.name == "Default" }
        // Let's try standard fetch
        do {
            let descriptor = FetchDescriptor<DownloadQueue>(
                predicate: #Predicate { $0.name == "Default" })
            if let existing = try context.fetch(descriptor).first {
                return existing
            }
        } catch {
            print("QueueManager: Error fetching default queue: \(error)")
        }

        return createQueue(name: "Default", maxConcurrent: 3)
    }

    func taskDidComplete(_ task: DownloadTask) {
        Task { @MainActor in
            processAllQueues()
            checkQueueCompletion(task: task)
        }
    }

    func taskDidFail(_ task: DownloadTask) {
        Task { @MainActor in processAllQueues() }
    }
    
    /// Checks if the queue containing the task is complete and executes post-process actions.
    ///
    /// - Parameter task: The task that just completed
    private func checkQueueCompletion(task: DownloadTask) {
        guard let context = modelContext else { return }
        guard let queue = task.queue else { return }
        
        // Check if queue is complete (all tasks done)
        if queue.isComplete && !queue.postProcessExecuted {
            print("QueueManager: Queue '\(queue.name)' is complete. Executing post-process action...")
            PostProcessActionExecutor.shared.executePostProcessAction(for: queue, context: context)
        }
    }
}
