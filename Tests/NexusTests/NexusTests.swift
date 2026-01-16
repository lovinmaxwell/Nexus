import XCTest
import SwiftData
@testable import NexusApp

final class NexusTests: XCTestCase {

    @MainActor
    func testDownloadWithSegmentation() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent("test_1MB.zip")
        let destPath = destURL.path

        try? FileManager.default.removeItem(atPath: destPath)

        // Use testfile.org for reliable test downloads
        let sourceURL = URL(string: "https://link.testfile.org/1MB")!
        let task = DownloadTask(sourceURL: sourceURL, destinationPath: destPath)
        context.insert(task)

        let id = task.id

        let coordinator = TaskCoordinator(taskID: id, container: container)
        await coordinator.start()

        let fetchedTask = try context.fetch(FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })).first!
        XCTAssertEqual(fetchedTask.status, .complete)
        XCTAssertEqual(fetchedTask.totalSize, 1048576)

        let attr = try FileManager.default.attributesOfItem(atPath: destPath)
        let fileSize = attr[.size] as? Int64 ?? 0
        XCTAssertEqual(fileSize, 1048576)

        XCTAssertGreaterThanOrEqual(fetchedTask.segments.count, 4)
    }

    @MainActor
    func testDownloadWith16Connections() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent("test_10MB.zip")
        let destPath = destURL.path

        try? FileManager.default.removeItem(atPath: destPath)

        // Use testfile.org for reliable test downloads
        let sourceURL = URL(string: "https://link.testfile.org/10MB")!
        let task = DownloadTask(sourceURL: sourceURL, destinationPath: destPath)
        context.insert(task)

        let id = task.id

        let coordinator = TaskCoordinator(taskID: id, container: container, maxConnections: 16)
        await coordinator.start()

        let fetchedTask = try context.fetch(FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })).first!
        XCTAssertEqual(fetchedTask.status, .complete)

        let attr = try FileManager.default.attributesOfItem(atPath: destPath)
        let fileSize = attr[.size] as? Int64 ?? 0
        XCTAssertEqual(fileSize, 10485760)

        print("Total segments created (with In-Half): \(fetchedTask.segments.count)")
        XCTAssertGreaterThanOrEqual(fetchedTask.segments.count, 4)
    }

    func testFileSegmentModel() throws {
        let segment = FileSegment(startOffset: 0, endOffset: 1000, currentOffset: 500)
        XCTAssertEqual(segment.startOffset, 0)
        XCTAssertEqual(segment.endOffset, 1000)
        XCTAssertEqual(segment.currentOffset, 500)
        XCTAssertFalse(segment.isComplete)
    }

    func testDownloadTaskModel() throws {
        let url = URL(string: "https://link.testfile.org/1MB")!
        let task = DownloadTask(sourceURL: url, destinationPath: "/tmp/file.zip")

        XCTAssertEqual(task.sourceURL, url)
        XCTAssertEqual(task.destinationPath, "/tmp/file.zip")
        XCTAssertEqual(task.status, .paused)
        XCTAssertEqual(task.totalSize, 0)
        XCTAssertTrue(task.segments.isEmpty)
    }
}
