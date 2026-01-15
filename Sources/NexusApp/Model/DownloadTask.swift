import Foundation
import SwiftData

public enum TaskStatus: Int, Codable {
    case paused = 0
    case running = 1
    case complete = 2
    case error = 3
    case pending = 4
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

    @Relationship(deleteRule: .cascade, inverse: \FileSegment.downloadTask)
    public var segments: [FileSegment] = []

    public var queue: DownloadQueue?

    public init(
        id: UUID = UUID(), sourceURL: URL, destinationPath: String, totalSize: Int64 = 0,
        status: TaskStatus = .paused, createdDate: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.totalSize = totalSize
        self.status = status
        self.createdDate = createdDate
    }
}
