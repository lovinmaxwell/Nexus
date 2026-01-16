import Foundation
import XCTest

@testable import NexusApp

@MainActor
final class SiteGrabberTests: XCTestCase {
    func testAssetTypeDetection() {
        // Use real image URLs for better testing
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400&q=80")!), .image)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://link.testfile.org/1MB")!), .other) // testfile.org doesn't specify extension
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://cdn.pixabay.com/photo/2015/04/23/22/00/tree-736885_1280.jpg")!), .image)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://link.testfile.org/500MB")!), .other)
        // Keep some example.com for testing edge cases
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://example.com/doc.pdf")!), .document)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://example.com/audio.mp3")!), .audio)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://example.com/video.mp4")!), .video)
    }
    
    func testGrabbedAssetEquality() {
        // Use real image URLs
        let url1 = URL(string: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400&q=80")!
        let url2 = URL(string: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400&q=80")!
        let url3 = URL(string: "https://cdn.pixabay.com/photo/2015/04/23/22/00/tree-736885_1280.jpg")!
        
        let asset1 = SiteGrabber.GrabbedAsset(url: url1, type: .image)
        let asset2 = SiteGrabber.GrabbedAsset(url: url2, type: .image)
        let asset3 = SiteGrabber.GrabbedAsset(url: url3, type: .image)
        
        XCTAssertEqual(asset1, asset2, "Assets with same URL should be equal")
        XCTAssertNotEqual(asset1, asset3, "Assets with different URLs should not be equal")
    }
    
    func testSiteGrabberInitialization() {
        let grabber = SiteGrabber.shared
        XCTAssertNotNil(grabber, "SiteGrabber should be initialized")
    }
}
