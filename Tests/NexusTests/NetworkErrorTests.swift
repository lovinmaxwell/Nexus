import SwiftData
import XCTest

@testable import NexusApp

class MockNetworkHandler: NetworkHandler {
    var shouldFailWith503 = false
    var failureCount = 0
    var successAfterFailures = 0

    func headRequest(url: URL) async throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        return (1024, true, Date(), "etag")
    }

    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<
        Data, Error
    > {
        if shouldFailWith503 {
            if failureCount < successAfterFailures {
                failureCount += 1
                throw NetworkError.serviceUnavailable
            }
        }

        return AsyncThrowingStream { continuation in
            let data = Data(count: Int(end - start + 1))
            continuation.yield(data)
            continuation.finish()
        }
    }
}

final class NetworkErrorTests: XCTestCase {

    @MainActor
    func testBackoffRetryLogic() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let task = DownloadTask(
            sourceURL: URL(string: "https://link.testfile.org/1MB")!, destinationPath: "/tmp/test")
        context.insert(task)

        let mockHandler = MockNetworkHandler()
        mockHandler.shouldFailWith503 = true
        mockHandler.successAfterFailures = 2  // Fail 2 times, then succeed

        let coordinator = TaskCoordinator(
            taskID: task.id, container: container, networkHandler: mockHandler)

        // We need to run this asynchronously and allow it to finish
        // Since `start()` runs until completion, it should eventually succeed after retries.
        // To verify retries happened, we can check the mock's state after.

        await coordinator.start()

        let taskID = task.id
        let fetchedTask = try context.fetch(
            FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
        ).first!
        XCTAssertEqual(fetchedTask.status, .complete)

        // Since we cannot easily inspect the actor's internal state or print logs in test assertions,
        // we assume success via `.complete` status means it overcame the errors.
        // Theoretically we could inspect `mockHandler.failureCount` but it is a class, so reference semantics work!
        XCTAssertEqual(mockHandler.failureCount, 2)
    }
}
