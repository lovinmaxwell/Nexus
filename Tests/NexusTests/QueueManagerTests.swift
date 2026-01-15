import SwiftData
import XCTest

@testable import NexusApp

@MainActor
final class QueueManagerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var queueManager: QueueManager!

    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext

        queueManager = QueueManager.shared
        queueManager.setModelContext(context)

        // Ensure DownloadManager also has context (mocking not fully possible without protocol, but we test QueueManager logic directly mainly)
        DownloadManager.shared.setModelContainer(container)
    }

    func testDefaultQueueCreation() {
        let queue = queueManager.getDefaultQueue()
        XCTAssertNotNil(queue)
        XCTAssertEqual(queue?.name, "Default")
        XCTAssertEqual(queue?.maxConcurrentDownloads, 3)
    }

    func testQueueConcurrencyLimit() throws {
        guard let queue = queueManager.getDefaultQueue() else {
            XCTFail("Default queue not found")
            return
        }

        // Set limit to 2 for testing
        queue.maxConcurrentDownloads = 2
        try context.save()

        // Create 3 tasks
        let task1 = DownloadTask(
            sourceURL: URL(string: "https://example.com/1")!, destinationPath: "/tmp/1")
        let task2 = DownloadTask(
            sourceURL: URL(string: "https://example.com/2")!, destinationPath: "/tmp/2")
        let task3 = DownloadTask(
            sourceURL: URL(string: "https://example.com/3")!, destinationPath: "/tmp/3")

        task1.queue = queue
        task2.queue = queue
        task3.queue = queue

        task1.status = .pending
        task2.status = .pending
        task3.status = .pending

        context.insert(task1)
        context.insert(task2)
        context.insert(task3)
        try context.save()

        // Process Queues
        // Note: verify that processAllQueues actually starts tasks.
        // It calls DownloadManager.startDownload -> TaskCoordinator.start
        // Since we didn't mock NetworkHandler, TaskCoordinator might fail or network access.
        // But status change to .running happens early in TaskCoordinator.start()

        // Mock NetworkHandlerFactory or catch errors?
        // Actually, without network, start() -> updateTaskStatus(.running) -> then network init.
        // So status should change to running instantly?
        // Wait, TaskCoordinator.start is async.

        // We can inspect if QueueManager *attempts* to start them.
        // Or we can just check logic:
        // `pendingTasks` property works?

        XCTAssertEqual(queue.pendingTasks.count, 3)

        // We'll rely on testing the QueueManager logic's *intended effect* or mocks.
        // Since we can't easily check side effects on DownloadManager singleton in this integration test without causing real downloads,
        // we might just check that QueueManager identifies correctly what needs starting.

        // Let's modify valid test:
        // Create 2 running tasks, 1 pending.
        task1.status = .running
        task2.status = .running
        try context.save()

        // QueueManager.processQueue logic:
        // runningCount = 2, max = 2. slots = 0.
        // Should NOT start task3.

        // Call internals if possible? methods are private.
        // But we can check behavior if we trigger it.
        // `processAllQueues` is public.

        // But how do we know if it was started?
        // Monitor task3.status.
        // If it starts, it becomes .running.
        // If it doesn't, it stays .pending.

        // Problem: TaskCoordinator needs to exist to run.
        // DownloadManager.startDownload creates Coordinator.
        // Coordinator starts.

        // If we run `queueManager.processAllQueues()`, logic checks limits.
        // 2 running, limit 2 -> status of task3 should Remain pending.

        queueManager.processAllQueues()

        // Allow async loop to maybe run?
        let expectation = XCTestExpectation(description: "Wait")
        _ = XCTWaiter.wait(for: [expectation], timeout: 0.1)

        // Refresh
        context.processPendingChanges()  // or fetch fresh
        let task3ID = task3.id
        let freshTask3 = try context.fetch(
            FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == task3ID })
        ).first!

        XCTAssertEqual(
            freshTask3.status, .pending, "Task 3 should remain pending because queue is full")

        // Now finish task 1
        task1.status = .complete
        try context.save()

        // Trigger completion logic
        queueManager.taskDidComplete(task1)

        // Wait for async processing
        let expectation2 = XCTestExpectation(description: "Wait for auto-start")
        _ = XCTWaiter.wait(for: [expectation2], timeout: 1.0)

        let freshTask3ID = task3.id
        let freshTask3After = try context.fetch(
            FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == freshTask3ID })
        ).first!

        // Since we are not mocking network, it might fail immediately to .error
        // Proof that it started is that it is NOT pending anymore.
        XCTAssertTrue(
            freshTask3After.status == .running || freshTask3After.status == .error,
            "Task 3 should have auto-started (status is \(freshTask3After.status))")
    }
}
