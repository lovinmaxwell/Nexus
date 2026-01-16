import Foundation
import XCTest

@testable import NexusApp

@MainActor
final class SiteGrabberTests: XCTestCase {
    func testAssetTypeDetection() {
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://example.com/image.jpg")!), .image)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://example.com/doc.pdf")!), .document)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://example.com/audio.mp3")!), .audio)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://example.com/video.mp4")!), .video)
        XCTAssertEqual(SiteGrabber.AssetType.from(url: URL(string: "https://example.com/file.xyz")!), .other)
    }
    
    func testGrabbedAssetEquality() {
        let url1 = URL(string: "https://example.com/file.jpg")!
        let url2 = URL(string: "https://example.com/file.jpg")!
        let url3 = URL(string: "https://example.com/other.jpg")!
        
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
