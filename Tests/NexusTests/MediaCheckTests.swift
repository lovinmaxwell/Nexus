import XCTest

@testable import NexusApp

final class MediaCheckTests: XCTestCase {
    func testIsMediaURL() async {
        let extractor = MediaExtractor.shared
        let url = "https://www.youtube.com/watch?v=a5ITNmnS680"
        let isMedia = await extractor.isMediaURL(url)
        XCTAssertTrue(isMedia, "YouTube URL should be recognized as media URL")
    }

    /*
    func testExtractMediaInfo() async throws {
        let extractor = MediaExtractor.shared
        let url = "https://www.youtube.com/watch?v=a5ITNmnS680"
    
        // This test requires yt-dlp to be available and network access.
        // It might fail in restricted sandbox environments, but will verify the logic if environment allows.
        do {
            let info = try await extractor.extractMediaInfo(from: url)
            print("Extracted Info: \(info)")
            XCTAssertFalse(info.title.isEmpty, "Should have a title")
            XCTAssertFalse(info.directURL.isEmpty, "Should have a direct URL")
            // The title should NOT be "watch" or "video" if it works correctly
            XCTAssertNotEqual(info.title, "watch", "Title should not be generic 'watch'")
            XCTAssertNotEqual(info.title, "video", "Title should not be generic 'video'")
        } catch {
            print("Extraction failed: \(error)")
            // If failure is due to missing yt-dlp, we should note that.
            throw error
        }
    }
    */

    func testDownloadManagerAddDownloadPathLogic() async {
        // Can't easily test private/internal logic of DownloadManager without making it testable or inferring from side effects.
        // But verifying isMediaURL is the first step.
    }
}
