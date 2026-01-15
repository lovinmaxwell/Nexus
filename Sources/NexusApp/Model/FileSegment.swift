import Foundation
import SwiftData

@Model
public final class FileSegment {
    public var id: UUID
    public var startOffset: Int64
    public var endOffset: Int64
    public var currentOffset: Int64
    public var isComplete: Bool

    // Inverse relationship
    public var downloadTask: DownloadTask?

    public init(
        id: UUID = UUID(), startOffset: Int64, endOffset: Int64, currentOffset: Int64 = 0,
        isComplete: Bool = false
    ) {
        self.id = id
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.currentOffset = currentOffset
        self.isComplete = isComplete
    }
}
