import SwiftData
import XCTest

@testable import NexusApp

@MainActor
final class DownloadTaskUITests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
    }
    
    func testDownloadedBytesCalculation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://link.testfile.org/1MB")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        
        // No segments initially
        XCTAssertEqual(task.downloadedBytes, 0)
        
        // Add segments with progress
        let segment1 = FileSegment(startOffset: 0, endOffset: 499, currentOffset: 250)
        let segment2 = FileSegment(startOffset: 500, endOffset: 999, currentOffset: 500)
        
        task.segments.append(segment1)
        task.segments.append(segment2)
        
        XCTAssertEqual(task.downloadedBytes, 250)  // 250 from segment1, 0 from segment2
    }
    
    func testSupportsResume() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://link.testfile.org/1MB")!,
            destinationPath: "/tmp/file"
        )
        
        // No segments means no resume support
        XCTAssertFalse(task.supportsResume)
        
        // Add a segment
        let segment = FileSegment(startOffset: 0, endOffset: 999, currentOffset: 0)
        task.segments.append(segment)
        
        XCTAssertTrue(task.supportsResume)
    }
    
    func testTimeRemainingCalculation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://link.testfile.org/1MB")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        
        // Not running, should return nil
        task.status = .paused
        XCTAssertNil(task.timeRemaining)
        
        // Running but no speed info, should return nil
        task.status = .running
        XCTAssertNil(task.timeRemaining)
    }
    
    func testCurrentSpeed() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://link.testfile.org/1MB")!,
            destinationPath: "/tmp/file"
        )
        
        // Speed is computed from TaskCoordinator, default is 0
        XCTAssertEqual(task.currentSpeed, 0)
    }
}
