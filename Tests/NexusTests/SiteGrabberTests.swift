import XCTest
@testable import NexusApp

final class SiteGrabberTests: XCTestCase {
    func testAssetTypeFromURL() {
        let imageURL = URL(string: "https://example.com/image.jpg")!
        let docURL = URL(string: "https://example.com/file.pdf")!
        let audioURL = URL(string: "https://example.com/song.mp3")!
        let videoURL = URL(string: "https://example.com/movie.mp4")!
        let otherURL = URL(string: "https://example.com/page.html")!
        
        XCTAssertEqual(SiteGrabber.AssetType.from(url: imageURL), .image)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: docURL), .document)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: audioURL), .audio)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: videoURL), .video)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: otherURL), .other)
    }
}
