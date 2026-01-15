import Foundation
import SwiftData

public enum TaskStatus: Int, Codable {
    case paused = 0
    case running = 1
    case complete = 2
    case error = 3
    case pending = 4
    case extracting = 5  // Extracting media info (YouTube, etc.)
}

@Model
public final class DownloadTask {
    public var id: UUID
    public var sourceURL: URL
    public var destinationPath: String
    public var totalSize: Int64
    public var status: TaskStatus
    public var eTag: String?
    public var lastModified: Date?
    public var httpCookies: Data?
    public var createdDate: Date
    public var priority: Int

    @Relationship(deleteRule: .cascade, inverse: \FileSegment.downloadTask)
    public var segments: [FileSegment] = []

    public var queue: DownloadQueue?
    
    /// Display name for the task (used during extraction before real title is known)
    public var displayName: String?
    
    /// Error message if status is .error
    public var errorMessage: String?

    public init(
        id: UUID = UUID(), sourceURL: URL, destinationPath: String, totalSize: Int64 = 0,
        status: TaskStatus = .paused, createdDate: Date = Date(), priority: Int = 0
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.totalSize = totalSize
        self.status = status
        self.createdDate = createdDate
        self.priority = priority
    }
    
    /// Returns the best available name for display
    public var effectiveDisplayName: String {
        if let name = displayName, !name.isEmpty {
            return name
        }
        return sourceURL.lastPathComponent
    }
}
