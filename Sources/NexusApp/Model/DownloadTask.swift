import Foundation
import SwiftData

public enum TaskStatus: Int, Codable {
    case paused = 0
    case running = 1
    case complete = 2
    case error = 3
    case pending = 4
    case extracting = 5  // Extracting media info (YouTube, etc.)
    case connecting = 6  // Connection/initialization phase (HEAD request, validation)
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

    /// Original media URL for streaming downloads
    public var originalURLString: String?
    
    /// Selected format ID for media downloads (yt-dlp format id or stream URL)
    public var selectedFormatID: String?
    
    /// Suggested filename derived from media metadata
    public var derivedFilename: String?
    
    /// Indicates this task needs audio/video muxing
    public var requiresMuxing: Bool = false
    
    /// Direct URL for the video-only stream (if muxing)
    public var mediaVideoURLString: String?
    
    /// Direct URL for the audio-only stream (if muxing)
    public var mediaAudioURLString: String?

    public init(
        id: UUID = UUID(), sourceURL: URL, destinationPath: String, totalSize: Int64 = 0,
        status: TaskStatus = .paused, createdDate: Date = Date(), priority: Int = 0,
        originalURLString: String? = nil,
        selectedFormatID: String? = nil,
        derivedFilename: String? = nil,
        requiresMuxing: Bool = false,
        mediaVideoURLString: String? = nil,
        mediaAudioURLString: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.totalSize = totalSize
        self.status = status
        self.createdDate = createdDate
        self.priority = priority
        self.originalURLString = originalURLString
        self.selectedFormatID = selectedFormatID
        self.derivedFilename = derivedFilename
        self.requiresMuxing = requiresMuxing
        self.mediaVideoURLString = mediaVideoURLString
        self.mediaAudioURLString = mediaAudioURLString
    }
    
    /// Returns the best available name for display
    public var effectiveDisplayName: String {
        if let name = displayName, !name.isEmpty {
            return name
        }
        return sourceURL.lastPathComponent
    }
    
    /// Current download speed in bytes per second (computed from segments)
    public var currentSpeed: Double {
        guard status == .running else { return 0 }
        // Speed is tracked in TaskCoordinator, but we can estimate from segment progress
        // For now, return 0 - will be updated via DownloadManager
        return 0
    }
    
    /// Calculates downloaded bytes from segments
    public var downloadedBytes: Int64 {
        segments.reduce(0) { $0 + max(0, $1.currentOffset - $1.startOffset) }
    }
    
    /// Calculates time remaining in seconds based on current speed and remaining bytes
    public var timeRemaining: TimeInterval? {
        guard status == .running, totalSize > 0 else { return nil }
        let remaining = totalSize - downloadedBytes
        guard remaining > 0 else { return 0 }
        
        // If we have segments with progress, estimate speed from recent progress
        // For now, return nil if speed is unknown
        // Speed will be updated via periodic refresh from TaskCoordinator
        return nil
    }
    
    /// Checks if the server supports resume (has Accept-Ranges header)
    /// This is determined by having segments with saved state
    public var supportsResume: Bool {
        // If we have segments, it means the server supports range requests
        return !segments.isEmpty
    }
}
