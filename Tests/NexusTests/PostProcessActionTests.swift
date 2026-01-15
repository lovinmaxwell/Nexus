import SwiftData
import XCTest

@testable import NexusApp

@MainActor
final class PostProcessActionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
    }
    
    func testPostProcessActionEnum() {
        XCTAssertEqual(PostProcessAction.none.rawValue, 0)
        XCTAssertEqual(PostProcessAction.systemSleep.rawValue, 1)
        XCTAssertEqual(PostProcessAction.systemShutdown.rawValue, 2)
        XCTAssertEqual(PostProcessAction.runScript.rawValue, 3)
        XCTAssertEqual(PostProcessAction.sendNotification.rawValue, 4)
    }
    
    func testQueueIsComplete() {
        let queue = DownloadQueue(name: "Test Queue")
        
        // Empty queue should not be complete
        XCTAssertFalse(queue.isComplete)
        
        // Add a pending task
        let task1 = DownloadTask(
            sourceURL: URL(string: "https://example.com/1")!,
            destinationPath: "/tmp/1",
            status: .pending
        )
        task1.queue = queue
        context.insert(task1)
        
        XCTAssertFalse(queue.isComplete, "Queue with pending task should not be complete")
        
        // Complete the task
        task1.status = .complete
        try? context.save()
        
        XCTAssertTrue(queue.isComplete, "Queue with all tasks complete should be complete")
        
        // Add a running task
        let task2 = DownloadTask(
            sourceURL: URL(string: "https://example.com/2")!,
            destinationPath: "/tmp/2",
            status: .running
        )
        task2.queue = queue
        context.insert(task2)
        
        XCTAssertFalse(queue.isComplete, "Queue with running task should not be complete")
    }
    
    func testPostProcessActionProperties() {
        let queue = DownloadQueue(
            name: "Test Queue",
            postProcessAction: .sendNotification
        )
        
        XCTAssertEqual(queue.postProcessAction, .sendNotification)
        XCTAssertFalse(queue.postProcessExecuted)
        XCTAssertNil(queue.postProcessScriptPath)
    }
    
    func testPostProcessScriptPath() {
        let queue = DownloadQueue(
            name: "Test Queue",
            postProcessAction: .runScript
        )
        queue.postProcessScriptPath = "/usr/local/bin/my-script.sh"
        
        XCTAssertEqual(queue.postProcessAction, .runScript)
        XCTAssertEqual(queue.postProcessScriptPath, "/usr/local/bin/my-script.sh")
    }
    
    func testCompletedTasksCount() {
        let queue = DownloadQueue(name: "Test Queue")
        
        XCTAssertEqual(queue.completedTasksCount, 0)
        
        let task1 = DownloadTask(
            sourceURL: URL(string: "https://example.com/1")!,
            destinationPath: "/tmp/1",
            status: .complete
        )
        task1.queue = queue
        context.insert(task1)
        
        let task2 = DownloadTask(
            sourceURL: URL(string: "https://example.com/2")!,
            destinationPath: "/tmp/2",
            status: .running
        )
        task2.queue = queue
        context.insert(task2)
        
        let task3 = DownloadTask(
            sourceURL: URL(string: "https://example.com/3")!,
            destinationPath: "/tmp/3",
            status: .complete
        )
        task3.queue = queue
        context.insert(task3)
        
        try? context.save()
        
        XCTAssertEqual(queue.completedTasksCount, 2)
    }
}
