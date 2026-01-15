import Foundation
import SwiftData

@Model
final class FileSegment {
    var id: UUID
    var startOffset: Int64
    var endOffset: Int64
    var currentOffset: Int64
    var isComplete: Bool
    
    // Inverse relationship
    var downloadTask: DownloadTask?
    
    init(id: UUID = UUID(), startOffset: Int64, endOffset: Int64, currentOffset: Int64 = 0, isComplete: Bool = false) {
        self.id = id
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.currentOffset = currentOffset
        self.isComplete = isComplete
    }
}
