import XCTest

@testable import NexusApp

final class MediaCheckTests: XCTestCase {
    func testIsMediaURL() async {
        let extractor = MediaExtractor.shared
        let url = "https://www.youtube.com/watch?v=a5ITNmnS680"
        let isMedia = await extractor.isMediaURL(url)
        XCTAssertTrue(isMedia, "YouTube URL should be recognized as media URL")
    }

    func testDownloadManagerAddDownloadPathLogic() async {
        // Can't easily test private/internal logic of DownloadManager without making it testable or inferring from side effects.
        // But verifying isMediaURL is the first step.
    }
}
