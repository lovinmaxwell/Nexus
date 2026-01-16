import SwiftData
import XCTest

@testable import NexusApp

/// Tests for downloading images from free image websites.
@MainActor
final class ImageDownloadTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([DownloadTask.self, FileSegment.self, DownloadQueue.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = container.mainContext
        
        DownloadManager.shared.setModelContainer(container)
    }
    
    /// Test downloading a small image from Unsplash.
    func testDownloadImageFromUnsplash() async throws {
        // Using a real Unsplash image URL for testing
        let imageURL = URL(string: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400&q=80")!
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NexusTests")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Use directory path, DownloadManager will append filename
        let taskID = await DownloadManager.shared.addDownload(
            url: imageURL,
            destinationPath: tempDir.path
        )
        
        XCTAssertNotNil(taskID, "Task should be created")
        
        if let taskID = taskID {
            // Start the download
            await DownloadManager.shared.startDownload(taskID: taskID)
            
            // Wait a bit for download to progress
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Check task status
            let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
            if let task = try? context.fetch(descriptor).first {
                // Task should be running or complete
                XCTAssertTrue(
                    task.status == .running || task.status == .complete,
                    "Task should be running or complete"
                )
            }
        }
    }
    
    /// Test downloading an image from Pixabay.
    func testDownloadImageFromPixabay() async throws {
        // Using a real Pixabay image URL for testing
        let imageURL = URL(string: "https://cdn.pixabay.com/photo/2015/04/23/22/00/tree-736885_1280.jpg")!
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NexusTests")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Use directory path, DownloadManager will append filename
        let taskID = await DownloadManager.shared.addDownload(
            url: imageURL,
            destinationPath: tempDir.path
        )
        
        XCTAssertNotNil(taskID, "Task should be created")
        
        if let taskID = taskID {
            // Start the download
            await DownloadManager.shared.startDownload(taskID: taskID)
            
            // Wait a bit for download to progress
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Check task status
            let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
            if let task = try? context.fetch(descriptor).first {
                // Task should be running or complete
                XCTAssertTrue(
                    task.status == .running || task.status == .complete,
                    "Task should be running or complete"
                )
            }
        }
    }
    
    /// Test downloading multiple images concurrently.
    func testConcurrentImageDownloads() async throws {
        let imageURLs = [
            URL(string: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400&q=80")!,
            URL(string: "https://cdn.pixabay.com/photo/2015/04/23/22/00/tree-736885_640.jpg")!,
        ]
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NexusTests")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        var taskIDs: [UUID] = []
        
        for url in imageURLs {
            // Use directory path, DownloadManager will append filename
            if let taskID = await DownloadManager.shared.addDownload(
                url: url,
                destinationPath: tempDir.path
            ) {
                taskIDs.append(taskID)
            }
        }
        
        XCTAssertEqual(taskIDs.count, imageURLs.count, "All tasks should be created")
        
        // Start all downloads
        for taskID in taskIDs {
            await DownloadManager.shared.startDownload(taskID: taskID)
        }
        
        // Wait for downloads to progress
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Verify all tasks are running or complete
        for taskID in taskIDs {
            let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })
            if let task = try? context.fetch(descriptor).first {
                XCTAssertTrue(
                    task.status == .running || task.status == .complete,
                    "Task \(taskID) should be running or complete"
                )
            }
        }
    }
}
