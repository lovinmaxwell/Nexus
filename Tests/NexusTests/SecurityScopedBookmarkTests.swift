import Foundation
import XCTest

@testable import NexusApp

@MainActor
final class SecurityScopedBookmarkTests: XCTestCase {
    func testSaveAndResolveBookmark() {
        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Save bookmark
            let saved = SecurityScopedBookmark.saveBookmark(for: tempDir)
            XCTAssertTrue(saved, "Should save bookmark successfully")
            
            // Resolve bookmark
            if let resolved = SecurityScopedBookmark.resolveBookmark() {
                XCTAssertEqual(resolved.path, tempDir.path, "Resolved URL should match original")
                SecurityScopedBookmark.stopAccessing(resolved)
            } else {
                XCTFail("Should resolve bookmark")
            }
            
            // Clean up
            try FileManager.default.removeItem(at: tempDir)
            UserDefaults.standard.removeObject(forKey: "defaultDownloadDirectoryBookmark")
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    func testGetDefaultDownloadDirectoryPath() {
        let path = SecurityScopedBookmark.getDefaultDownloadDirectoryPath()
        XCTAssertFalse(path.isEmpty, "Should return a valid path")
        // Should return Downloads directory or /tmp as fallback
        XCTAssertTrue(path.contains("Downloads") || path == "/tmp", "Should return Downloads or /tmp")
    }
}
