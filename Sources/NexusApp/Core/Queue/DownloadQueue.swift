import Foundation
import SwiftData

public enum QueueMode: Int, Codable {
    case sequential = 0
    case parallel = 1
}

/// Post-process actions that can be executed when a queue completes.
public enum PostProcessAction: Int, Codable {
    case none = 0
    case systemSleep = 1
    case systemShutdown = 2
    case runScript = 3
    case sendNotification = 4
}

@Model
public final class DownloadQueue {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var maxConcurrentDownloads: Int
    public var isActive: Bool
    public var mode: QueueMode
    public var createdDate: Date
    
    // Synchronization queue properties
    public var isSynchronizationQueue: Bool
    public var checkInterval: TimeInterval  // Interval in seconds for periodic checks
    public var lastCheckDate: Date?
    
    // Post-process action properties
    public var postProcessAction: PostProcessAction
    public var postProcessScriptPath: String?  // Path to script for .runScript action
    public var postProcessExecuted: Bool  // Track if action has been executed for this completion

    // Relationship to tasks
    @Relationship(deleteRule: .nullify, inverse: \DownloadTask.queue)
    public var tasks: [DownloadTask] = []

    public init(
        name: String, maxConcurrentDownloads: Int = 3, isActive: Bool = true,
        mode: QueueMode = .parallel, isSynchronizationQueue: Bool = false,
        checkInterval: TimeInterval = 3600.0,  // Default: 1 hour
        postProcessAction: PostProcessAction = .none
    ) {
        self.id = UUID()
        self.name = name
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.isActive = isActive
        self.mode = mode
        self.createdDate = Date()
        self.isSynchronizationQueue = isSynchronizationQueue
        self.checkInterval = checkInterval
        self.lastCheckDate = nil
        self.postProcessAction = postProcessAction
        self.postProcessScriptPath = nil
        self.postProcessExecuted = false
    }

    public var pendingTasks: [DownloadTask] {
        tasks.filter { $0.status == .pending || $0.status == .paused }
    }

    public var activeTasks: [DownloadTask] {
        tasks.filter { $0.status == .running || $0.status == .connecting }
    }
    
    /// Returns true if all tasks in the queue are complete (no pending or running tasks).
    public var isComplete: Bool {
        let hasIncomplete = tasks.contains { task in
            task.status == .pending || task.status == .running || task.status == .paused
        }
        return !hasIncomplete && !tasks.isEmpty
    }
    
    /// Returns the count of completed tasks.
    public var completedTasksCount: Int {
        tasks.filter { $0.status == .complete }.count
    }
}
