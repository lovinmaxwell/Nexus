import Foundation
import SwiftData

enum TaskStatus: Int, Codable {
    case paused = 0
    case running = 1
    case complete = 2
    case error = 3
}

@Model
final class DownloadTask {
    var id: UUID
    var sourceURL: URL
    var destinationPath: String
    var totalSize: Int64
    var status: TaskStatus
    var eTag: String?
    var lastModified: Date?
    var httpCookies: Data?
    var createdDate: Date
    
    @Relationship(deleteRule: .cascade, inverse: \FileSegment.downloadTask)
    var segments: [FileSegment] = []
    
    var queue: DownloadQueue?
    
    init(id: UUID = UUID(), sourceURL: URL, destinationPath: String, totalSize: Int64 = 0, status: TaskStatus = .paused, createdDate: Date = Date()) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.totalSize = totalSize
        self.status = status
        self.createdDate = createdDate
    }
}
