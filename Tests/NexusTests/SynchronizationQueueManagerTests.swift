import SwiftData
import XCTest

@testable import NexusApp

@MainActor
final class SynchronizationQueueManagerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var syncManager: SynchronizationQueueManager!
    
    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
        
        syncManager = SynchronizationQueueManager.shared
        syncManager.setModelContext(context)
    }
    
    func testSynchronizationQueueProperties() {
        let queue = DownloadQueue(
            name: "Sync Queue",
            maxConcurrentDownloads: 2,
            isActive: true,
            mode: .parallel,
            isSynchronizationQueue: true,
            checkInterval: 1800.0  // 30 minutes
        )
        
        XCTAssertTrue(queue.isSynchronizationQueue)
        XCTAssertEqual(queue.checkInterval, 1800.0)
        XCTAssertNil(queue.lastCheckDate)
    }
    
    func testSynchronizationQueueCreation() {
        let queue = DownloadQueue(
            name: "Nightly Sync",
            isSynchronizationQueue: true,
            checkInterval: 3600.0
        )
        
        context.insert(queue)
        try? context.save()
        
        XCTAssertTrue(queue.isSynchronizationQueue)
        XCTAssertEqual(queue.checkInterval, 3600.0)
    }
    
    func testRegularQueueIsNotSynchronization() {
        let queue = DownloadQueue(name: "Regular Queue")
        
        XCTAssertFalse(queue.isSynchronizationQueue)
        XCTAssertEqual(queue.checkInterval, 3600.0)  // Default value
    }
}
