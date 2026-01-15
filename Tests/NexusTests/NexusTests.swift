import XCTest
import SwiftData
@testable import NexusApp

final class NexusTests: XCTestCase {
    
    @MainActor
    func testDownloadWithSegmentation() async throws {
        // Setup SwiftData container in memory
        let schema = Schema([DownloadTask.self, FileSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent("test_1MB.zip")
        let destPath = destURL.path
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: destPath)
        
        let sourceURL = URL(string: "http://speedtest.tele2.net/1MB.zip")!
        let task = DownloadTask(sourceURL: sourceURL, destinationPath: destPath)
        context.insert(task)
        
        let id = task.id
        
        // Start Coordinator
        let coordinator = TaskCoordinator(taskID: id, container: container)
        await coordinator.start()
        
        // Verify
        let fetchedTask = try context.fetch(FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == id })).first!
        XCTAssertEqual(fetchedTask.status, .complete)
        XCTAssertEqual(fetchedTask.totalSize, 1048576) // 1MB
        
        // Verify File
        let attr = try FileManager.default.attributesOfItem(atPath: destPath)
        let fileSize = attr[.size] as? Int64 ?? 0
        XCTAssertEqual(fileSize, 1048576)
        
        // Verify Segments created
        XCTAssertEqual(fetchedTask.segments.count, 4) // We hardcoded 4 segments
    }
}
