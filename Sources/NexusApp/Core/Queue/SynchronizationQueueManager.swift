import Foundation
import SwiftData
import BackgroundTasks

/// Manages synchronization queues that periodically check for file updates on the server.
///
/// Synchronization queues monitor completed downloads and automatically re-download files
/// if they have been modified on the server (detected via HEAD requests comparing
/// Last-Modified or Content-Length headers).
@MainActor
class SynchronizationQueueManager: ObservableObject {
    static let shared = SynchronizationQueueManager()
    
    private var modelContext: ModelContext?
    private var foregroundTimer: Timer?
    private let backgroundTaskIdentifier = "com.projectnexus.sync.check"
    
    private init() {
        registerBackgroundTask()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    /// Registers the background task for periodic synchronization checks.
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleBackgroundSync(task: task as! BGAppRefreshTask)
            }
        }
    }
    
    /// Starts periodic synchronization checks for all active synchronization queues.
    ///
    /// When the app is running, this uses a Timer. When the app is in the background,
    /// it schedules BGAppRefreshTask.
    func startSynchronizationChecks() {
        stopSynchronizationChecks()
        
        guard let context = modelContext else { return }
        
        // Check if we have any active synchronization queues
        do {
            let syncQueuesDescriptor = FetchDescriptor<DownloadQueue>(
                predicate: #Predicate { $0.isSynchronizationQueue && $0.isActive }
            )
            let syncQueues = try context.fetch(syncQueuesDescriptor)
            
            guard !syncQueues.isEmpty else { return }
            
            // Schedule background task
            scheduleBackgroundTask()
            
            // Start foreground timer (checks every 5 minutes minimum, or queue's checkInterval)
            let minInterval = syncQueues.map { $0.checkInterval }.min() ?? 3600.0
            let timerInterval = max(minInterval, 300.0)  // At least 5 minutes
            
            foregroundTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.checkAllSynchronizationQueues()
                }
            }
            
            // Perform initial check
            Task {
                await checkAllSynchronizationQueues()
            }
        } catch {
            print("SynchronizationQueueManager: Failed to fetch sync queues - \(error)")
        }
    }
    
    /// Stops all synchronization checks.
    func stopSynchronizationChecks() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
    }
    
    /// Schedules a background app refresh task for synchronization checks.
    private func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)  // Schedule for 1 hour from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("SynchronizationQueueManager: Background task scheduled")
        } catch {
            print("SynchronizationQueueManager: Failed to schedule background task - \(error)")
        }
    }
    
    /// Handles background synchronization when the app is not running.
    private func handleBackgroundSync(task: BGAppRefreshTask) async {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        await checkAllSynchronizationQueues()
        
        // Schedule next background check
        scheduleBackgroundTask()
        
        task.setTaskCompleted(success: true)
    }
    
    /// Checks all active synchronization queues for file updates.
    private func checkAllSynchronizationQueues() async {
        guard let context = modelContext else { return }
        
        do {
            let syncQueuesDescriptor = FetchDescriptor<DownloadQueue>(
                predicate: #Predicate { $0.isSynchronizationQueue && $0.isActive }
            )
            let syncQueues = try context.fetch(syncQueuesDescriptor)
            
            for queue in syncQueues {
                // Check if it's time to check this queue
                if let lastCheck = queue.lastCheckDate {
                    let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
                    if timeSinceLastCheck < queue.checkInterval {
                        continue  // Not time to check yet
                    }
                }
                
                await checkQueueForUpdates(queue: queue, context: context)
                queue.lastCheckDate = Date()
                try? context.save()
            }
        } catch {
            print("SynchronizationQueueManager: Failed to fetch sync queues - \(error)")
        }
    }
    
    /// Checks a specific queue for file updates and triggers re-downloads if needed.
    ///
    /// - Parameters:
    ///   - queue: The synchronization queue to check
    ///   - context: The model context for database operations
    private func checkQueueForUpdates(queue: DownloadQueue, context: ModelContext) async {
        // Get all completed tasks in this queue
        let completedTasks = queue.tasks.filter { $0.status == .complete }
        
        guard !completedTasks.isEmpty else { return }
        
        print("SynchronizationQueueManager: Checking \(completedTasks.count) completed tasks in queue '\(queue.name)'")
        
        for task in completedTasks {
            await checkTaskForUpdates(task: task, context: context)
        }
    }
    
    /// Checks a single task for server-side updates.
    ///
    /// Performs a HEAD request and compares Last-Modified/Content-Length with stored metadata.
    /// If the file has changed, triggers a re-download.
    ///
    /// - Parameters:
    ///   - task: The completed task to check
    ///   - context: The model context for database operations
    private func checkTaskForUpdates(task: DownloadTask, context: ModelContext) async {
        let url = task.sourceURL
        
        // Get appropriate network handler
        let handler = NetworkHandlerFactory.handler(for: url)
        
        do {
            // Perform HEAD request
            let meta = try await handler.headRequest(url: url)
            
            // Compare with stored metadata
            var needsRedownload = false
            var reason: String = ""
            
            // Check Last-Modified
            if let serverLastModified = meta.lastModified,
               let storedLastModified = task.lastModified {
                if serverLastModified > storedLastModified {
                    needsRedownload = true
                    reason = "Last-Modified changed: \(storedLastModified) -> \(serverLastModified)"
                }
            }
            
            // Check Content-Length (file size changed)
            if meta.contentLength > 0 && task.totalSize > 0 {
                if meta.contentLength != task.totalSize {
                    needsRedownload = true
                    reason = "Content-Length changed: \(task.totalSize) -> \(meta.contentLength)"
                }
            }
            
            // Check ETag if available
            if let serverETag = meta.eTag, let storedETag = task.eTag {
                if serverETag != storedETag {
                    needsRedownload = true
                    reason = "ETag changed: \(storedETag) -> \(serverETag)"
                }
            }
            
            if needsRedownload {
                print("SynchronizationQueueManager: File changed for task \(task.id): \(reason)")
                
                // Create a new task for re-download
                let newTask = DownloadTask(
                    sourceURL: task.sourceURL,
                    destinationPath: task.destinationPath,
                    totalSize: meta.contentLength,
                    status: .pending,
                    priority: task.priority
                )
                newTask.queue = task.queue
                newTask.displayName = task.displayName ?? task.effectiveDisplayName
                
                // Update metadata
                newTask.eTag = meta.eTag
                newTask.lastModified = meta.lastModified
                
                context.insert(newTask)
                try? context.save()
                
                // Trigger queue processing
                QueueManager.shared.processAllQueues()
                
                print("SynchronizationQueueManager: Created new download task \(newTask.id) for updated file")
            }
        } catch {
            print("SynchronizationQueueManager: Failed to check task \(task.id) - \(error)")
        }
    }
}
