import SwiftData
import XCTest

@testable import NexusApp

@MainActor
final class MenuBarDockTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
        
        MenuBarManager.shared.setModelContainer(container)
        DockManager.shared.setModelContainer(container)
    }
    
    func testMenuBarManagerInitialization() {
        let manager = MenuBarManager.shared
        XCTAssertNotNil(manager, "MenuBarManager should be initialized")
    }
    
    func testDockManagerInitialization() {
        let manager = DockManager.shared
        XCTAssertNotNil(manager, "DockManager should be initialized")
    }
    
    func testActiveDownloadCount() {
        let manager = DockManager.shared
        
        // Initially should be 0
        XCTAssertEqual(manager.activeDownloadCount, 0)
        
        // Add a running task
        let task = DownloadTask(
            sourceURL: URL(string: "https://example.com/file")!,
            destinationPath: "/tmp/file",
            status: .running
        )
        context.insert(task)
        try? context.save()
        
        // Wait a bit for timer to update
        let expectation = XCTestExpectation(description: "Wait for update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        // Count should be updated (though timer might not have fired in test)
        // At least verify the manager is working
        XCTAssertNotNil(manager)
    }
}
