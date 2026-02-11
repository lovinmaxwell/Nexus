import Combine
import Foundation

/// Real-time progress snapshot for a download task.
struct DownloadProgressSnapshot {
    let downloadedBytes: Int64
    let totalBytes: Int64
    let speed: Double
    
    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(downloadedBytes) / Double(totalBytes))
    }
    
    var timeRemaining: TimeInterval? {
        guard speed > 0, totalBytes > 0, downloadedBytes < totalBytes else { return nil }
        let remaining = Double(totalBytes - downloadedBytes) / speed
        return remaining > 0 ? remaining : 0
    }
}

/// Broadcasts real-time download progress for snappy UI updates.
/// Decouples TaskCoordinator (actor) from SwiftUI for immediate feedback.
@MainActor
@Observable
final class DownloadProgressBroadcaster {
    static let shared = DownloadProgressBroadcaster()
    
    /// Cached progress per task ID for instant UI reads.
    private(set) var snapshots: [UUID: DownloadProgressSnapshot] = [:]
    
    /// Minimum interval between broadcasts per task (throttle for performance).
    private let broadcastInterval: TimeInterval = 0.05
    private var lastBroadcastTime: [UUID: Date] = [:]
    
    private init() {}
    
    /// Update progress for a task. Called from TaskCoordinator via MainActor.run.
    func update(taskID: UUID, downloadedBytes: Int64, totalBytes: Int64, speed: Double) {
        let now = Date()
        if let last = lastBroadcastTime[taskID], now.timeIntervalSince(last) < broadcastInterval {
            return
        }
        lastBroadcastTime[taskID] = now
        
        let snapshot = DownloadProgressSnapshot(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            speed: speed
        )
        snapshots[taskID] = snapshot
    }
    
    /// Remove task from cache when complete/paused/error.
    func remove(taskID: UUID) {
        snapshots.removeValue(forKey: taskID)
        lastBroadcastTime.removeValue(forKey: taskID)
    }
    
    /// Get cached progress for a task.
    func snapshot(for taskID: UUID) -> DownloadProgressSnapshot? {
        snapshots[taskID]
    }
}
