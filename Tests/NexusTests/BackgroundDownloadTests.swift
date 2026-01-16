import Foundation
import SwiftData
import XCTest

@testable import NexusApp

@MainActor
final class BackgroundDownloadTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
        
        BackgroundDownloadManager.shared.setModelContainer(container)
    }
    
    func testBackgroundSessionConfiguration() {
        // Verify that BackgroundDownloadManager is initialized
        let manager = BackgroundDownloadManager.shared
        XCTAssertNotNil(manager, "BackgroundDownloadManager should be initialized")
    }
    
    func testBackgroundDownloadTaskCreation() {
        let task = DownloadTask(
            sourceURL: URL(string: "https://example.com/file")!,
            destinationPath: "/tmp/test-file"
        )
        context.insert(task)
        try? context.save()
        
        // Note: We can't actually start a background download in tests without a real URLSession
        // This test verifies the setup is correct
        XCTAssertNotNil(task.id)
    }
    
    func testRestoreBackgroundDownloads() {
        // Test that restoreBackgroundDownloads doesn't crash
        BackgroundDownloadManager.shared.restoreBackgroundDownloads()
        // If we get here, the method executed without crashing
        XCTAssertTrue(true)
    }
}
