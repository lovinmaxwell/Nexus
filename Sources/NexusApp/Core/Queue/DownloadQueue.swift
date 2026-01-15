import Foundation
import SwiftData

public enum QueueMode: Int, Codable {
    case sequential = 0
    case parallel = 1
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

    // Relationship to tasks
    @Relationship(deleteRule: .nullify, inverse: \DownloadTask.queue)
    public var tasks: [DownloadTask] = []

    public init(
        name: String, maxConcurrentDownloads: Int = 3, isActive: Bool = true,
        mode: QueueMode = .parallel, isSynchronizationQueue: Bool = false,
        checkInterval: TimeInterval = 3600.0  // Default: 1 hour
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
    }

    public var pendingTasks: [DownloadTask] {
        tasks.filter { $0.status == .pending || $0.status == .paused }
    }

    public var activeTasks: [DownloadTask] {
        tasks.filter { $0.status == .running }
    }
}
