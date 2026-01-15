import SwiftData
import XCTest

@testable import NexusApp

class MockValidationNetworkHandler: NetworkHandler {
    var eTag: String? = "original_etag"
    var lastModified: Date? = Date(timeIntervalSince1970: 1000)

    func headRequest(url: URL) async throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        return (1024, true, lastModified, eTag)
    }

    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<
        Data, Error
    > {
        return AsyncThrowingStream { continuation in
            continuation.yield(Data())
            continuation.finish()
        }
    }
}

final class ResumeValidationTests: XCTestCase {

    @MainActor
    func testResumeWithMatchingHeaders() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let task = DownloadTask(
            sourceURL: URL(string: "http://example.com")!, destinationPath: "/tmp/test_match")
        task.eTag = "original_etag"
        task.lastModified = Date(timeIntervalSince1970: 1000)
        task.totalSize = 1024
        task.segments.append(FileSegment(startOffset: 0, endOffset: 1023, currentOffset: 0))
        context.insert(task)

        let mockHandler = MockValidationNetworkHandler()
        // Headers match by default in mock

        let coordinator = TaskCoordinator(
            taskID: task.id, container: container, networkHandler: mockHandler)
        await coordinator.start()

        // Use local var for predicate safety
        let taskID = task.id
        let fetchedTask = try context.fetch(
            FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        ).first!
        XCTAssertEqual(fetchedTask.status, .complete)
    }

    @MainActor
    func testResumeWithMismatchedETag() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let task = DownloadTask(
            sourceURL: URL(string: "http://example.com")!,
            destinationPath: "/tmp/test_etag_mismatch")
        task.eTag = "original_etag"
        task.totalSize = 1024
        task.segments.append(FileSegment(startOffset: 0, endOffset: 1023, currentOffset: 0))
        context.insert(task)

        let mockHandler = MockValidationNetworkHandler()
        mockHandler.eTag = "new_etag"  // Mismatch

        let coordinator = TaskCoordinator(
            taskID: task.id, container: container, networkHandler: mockHandler)
        await coordinator.start()

        // Use local var for predicate safety
        let taskID = task.id
        let fetchedTask = try context.fetch(
            FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        ).first!
        XCTAssertEqual(fetchedTask.status, .error)
    }

    @MainActor
    func testResumeWithMismatchedLastModified() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let task = DownloadTask(
            sourceURL: URL(string: "http://example.com")!, destinationPath: "/tmp/test_lm_mismatch")
        task.lastModified = Date(timeIntervalSince1970: 1000)
        task.totalSize = 1024
        task.segments.append(FileSegment(startOffset: 0, endOffset: 1023, currentOffset: 0))
        context.insert(task)

        let mockHandler = MockValidationNetworkHandler()
        mockHandler.lastModified = Date(timeIntervalSince1970: 2000)  // Mismatch

        let coordinator = TaskCoordinator(
            taskID: task.id, container: container, networkHandler: mockHandler)
        await coordinator.start()

        // Use local var for predicate safety
        let taskID = task.id
        let fetchedTask = try context.fetch(
            FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        ).first!
        XCTAssertEqual(fetchedTask.status, .error)
    }
}
