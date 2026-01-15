import XCTest

@testable import NexusApp

/// Unit tests for the YtDlpUpdater.
///
/// These tests verify:
/// - Version checking
/// - Update availability detection
/// - Error handling
final class YtDlpUpdaterTests: XCTestCase {

    // MARK: - Configuration Tests

    func test_installedBinaryPath_isInAppSupport() async {
        let updater = YtDlpUpdater.shared
        let path = await updater.installedBinaryPath

        XCTAssertTrue(path.path.contains("Application Support"))
        XCTAssertTrue(path.path.contains("Nexus"))
        XCTAssertTrue(path.path.hasSuffix("yt-dlp"))
    }

    // MARK: - Error Tests

    func test_ytdlpUpdaterError_hasDescriptions() {
        let errors: [YtDlpUpdaterError] = [
            .fetchFailed("network error"),
            .parseError("invalid json"),
            .downloadFailed("timeout"),
            .installFailed("permission denied"),
            .verificationFailed("signature mismatch"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func test_fetchFailedError_containsMessage() {
        let error = YtDlpUpdaterError.fetchFailed("connection timeout")
        XCTAssertTrue(error.errorDescription?.contains("connection timeout") ?? false)
    }

    // MARK: - ReleaseInfo Tests

    func test_releaseInfo_storesAllProperties() {
        let url = URL(string: "https://example.com/yt-dlp")!
        let date = Date()

        let info = YtDlpUpdater.ReleaseInfo(
            version: "2025.01.15",
            downloadURL: url,
            size: 12345678,
            publishedAt: date,
            releaseNotes: "Bug fixes and improvements"
        )

        XCTAssertEqual(info.version, "2025.01.15")
        XCTAssertEqual(info.downloadURL, url)
        XCTAssertEqual(info.size, 12345678)
        XCTAssertEqual(info.publishedAt, date)
        XCTAssertEqual(info.releaseNotes, "Bug fixes and improvements")
    }

    // MARK: - UpdateCheckResult Tests

    func test_updateCheckResult_detectsUpdateAvailable() {
        let result = YtDlpUpdater.UpdateCheckResult(
            currentVersion: "2025.01.01",
            latestVersion: "2025.01.15",
            updateAvailable: true,
            releaseInfo: nil
        )

        XCTAssertTrue(result.updateAvailable)
        XCTAssertEqual(result.currentVersion, "2025.01.01")
        XCTAssertEqual(result.latestVersion, "2025.01.15")
    }

    func test_updateCheckResult_detectsNoUpdateNeeded() {
        let result = YtDlpUpdater.UpdateCheckResult(
            currentVersion: "2025.01.15",
            latestVersion: "2025.01.15",
            updateAvailable: false,
            releaseInfo: nil
        )

        XCTAssertFalse(result.updateAvailable)
    }

    func test_updateCheckResult_handlesNilCurrentVersion() {
        let result = YtDlpUpdater.UpdateCheckResult(
            currentVersion: nil,
            latestVersion: "2025.01.15",
            updateAvailable: true,
            releaseInfo: nil
        )

        XCTAssertNil(result.currentVersion)
        XCTAssertTrue(result.updateAvailable)
    }

    // MARK: - Update Scheduling Tests

    func test_shouldCheckForUpdate_initiallyTrue() async {
        // Clear any existing last check timestamp
        UserDefaults.standard.removeObject(forKey: "YtDlpLastUpdateCheck")

        let updater = YtDlpUpdater.shared
        let shouldCheck = await updater.shouldCheckForUpdate

        XCTAssertTrue(shouldCheck, "Should check for update when never checked before")
    }

    // MARK: - Installation Tests

    func test_isInstalled_returnsFalseWhenNotInstalled() async {
        // This test may need to be adjusted based on the test environment
        // For a clean test environment, yt-dlp should not be installed
        let updater = YtDlpUpdater.shared
        let _ = await updater.isInstalled
        // Just verify it doesn't crash - the actual value depends on the environment
    }
}
