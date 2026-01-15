import XCTest
@testable import NexusApp

final class ytDlpUpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(ytDlpUpdater.isVersion("2024.01.01", newerThan: "2023.12.31"))
        XCTAssertTrue(ytDlpUpdater.isVersion("2024.02.01", newerThan: "2024.01.31"))
        XCTAssertFalse(ytDlpUpdater.isVersion("2023.12.31", newerThan: "2024.01.01"))
        XCTAssertFalse(ytDlpUpdater.isVersion("2024.01.01", newerThan: "2024.01.01"))
    }
}
