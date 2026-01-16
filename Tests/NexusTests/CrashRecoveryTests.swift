import SwiftData
import XCTest

@testable import NexusApp

@MainActor
final class CrashRecoveryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
    }
    
    func testIncompleteTaskRecovery() {
        // Create a task with incomplete segments (simulating crash)
        let task = DownloadTask(
            sourceURL: URL(string: "https://link.testfile.org/1MB")!,
            destinationPath: "/tmp/file",
            totalSize: 1000,
            status: .running
        )
        
        // Add segments with partial progress
        let segment1 = FileSegment(startOffset: 0, endOffset: 499, currentOffset: 250)
        let segment2 = FileSegment(startOffset: 500, endOffset: 999, currentOffset: 500)
        
        task.segments.append(segment1)
        task.segments.append(segment2)
        
        context.insert(task)
        try? context.save()
        
        // Simulate app restart - query all tasks and filter incomplete ones
        let descriptor = FetchDescriptor<DownloadTask>()
        let allTasks = try? context.fetch(descriptor)
        let incompleteTasks = allTasks?.filter { $0.status != .complete }
        
        XCTAssertNotNil(incompleteTasks)
        XCTAssertTrue(incompleteTasks?.contains { $0.id == task.id } ?? false)
    }
    
    func testSegmentValidation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://link.testfile.org/1MB")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        
        let segment = FileSegment(startOffset: 0, endOffset: 999, currentOffset: 500)
        task.segments.append(segment)
        
        // Validate segment data
        XCTAssertEqual(segment.startOffset, 0)
        XCTAssertEqual(segment.endOffset, 999)
        XCTAssertEqual(segment.currentOffset, 500)
        XCTAssertFalse(segment.isComplete)
        
        // Simulate resume - should continue from currentOffset
        XCTAssertTrue(segment.currentOffset > segment.startOffset, "Should resume from current offset")
    }
    
    func testETagValidation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://link.testfile.org/1MB")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        task.eTag = "original-etag"
        
        // Simulate resume validation
        let savedETag = task.eTag
        XCTAssertNotNil(savedETag)
        XCTAssertEqual(savedETag, "original-etag")
    }
}
