import SwiftData
import XCTest

@testable import NexusApp

@MainActor
final class ResumeValidationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
    }
    
    func testResumeCapabilityDetection() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://example.com/file")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        
        // No segments means no resume capability
        XCTAssertFalse(task.supportsResume)
        
        // Add segment indicates resume capability
        let segment = FileSegment(startOffset: 0, endOffset: 999, currentOffset: 500)
        task.segments.append(segment)
        
        XCTAssertTrue(task.supportsResume)
    }
    
    func testETagValidation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://example.com/file")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        task.eTag = "original-etag"
        
        // ETag should be stored
        XCTAssertEqual(task.eTag, "original-etag")
    }
    
    func testLastModifiedValidation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://example.com/file")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        let date = Date()
        task.lastModified = date
        
        // Last-Modified should be stored
        XCTAssertEqual(task.lastModified, date)
    }
    
    func testContentLengthValidation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://example.com/file")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        
        // Total size should match
        XCTAssertEqual(task.totalSize, 1000)
    }
    
    func testSegmentValidation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://example.com/file")!,
            destinationPath: "/tmp/file",
            totalSize: 1000
        )
        
        // Add segments
        let segment1 = FileSegment(startOffset: 0, endOffset: 499, currentOffset: 250)
        let segment2 = FileSegment(startOffset: 500, endOffset: 999, currentOffset: 750)
        
        task.segments.append(segment1)
        task.segments.append(segment2)
        
        // Segments should be associated
        XCTAssertEqual(task.segments.count, 2)
        XCTAssertEqual(task.segments[0].currentOffset, 250)
        XCTAssertEqual(task.segments[1].currentOffset, 750)
    }
}
