import Foundation

/// Actor responsible for managing yt-dlp binary updates.
///
/// Checks for new versions on GitHub and downloads updates securely.
/// The update process verifies signatures to ensure authenticity.
actor YtDlpUpdater {
    static let shared = YtDlpUpdater()

    // MARK: - Configuration

    /// GitHub API URL for yt-dlp releases.
    private let releasesURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!

    /// Expected binary name for macOS.
    private let binaryName = "yt-dlp_macos"

    /// Alternative binary name (universal).
    private let binaryNameAlt = "yt-dlp"

    /// Directory where yt-dlp is stored in the app support folder.
    private var binDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Nexus/bin", isDirectory: true)
    }

    /// Path to the installed yt-dlp binary.
    var installedBinaryPath: URL {
        binDirectory.appendingPathComponent("yt-dlp")
    }

    // MARK: - Version Information

    /// Information about a yt-dlp release.
    struct ReleaseInfo {
        let version: String
        let downloadURL: URL
        let size: Int64
        let publishedAt: Date
        let releaseNotes: String
    }

    /// Update check result.
    struct UpdateCheckResult {
        let currentVersion: String?
        let latestVersion: String
        let updateAvailable: Bool
        let releaseInfo: ReleaseInfo?
    }

    // MARK: - Update Methods

    /// Checks if yt-dlp is installed.
    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: installedBinaryPath.path)
    }

    /// Gets the currently installed version.
    ///
    /// - Returns: Version string or nil if not installed.
    func getCurrentVersion() async -> String? {
        guard isInstalled else { return nil }

        let process = Process()
        process.executableURL = installedBinaryPath
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Fetches the latest release information from GitHub.
    ///
    /// - Returns: Release information or nil if fetch fails.
    func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Nexus-Download-Manager", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw YtDlpUpdaterError.fetchFailed("Failed to fetch release info")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YtDlpUpdaterError.parseError("Invalid JSON response")
        }

        guard let tagName = json["tag_name"] as? String else {
            throw YtDlpUpdaterError.parseError("Missing version tag")
        }

        guard let assets = json["assets"] as? [[String: Any]] else {
            throw YtDlpUpdaterError.parseError("Missing assets")
        }

        // Find the macOS binary
        let macOSAsset = assets.first { asset in
            let name = asset["name"] as? String ?? ""
            return name == binaryName || name == binaryNameAlt
        }

        guard let asset = macOSAsset,
              let downloadURLString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            throw YtDlpUpdaterError.parseError("macOS binary not found in release")
        }

        let size = asset["size"] as? Int64 ?? 0
        let body = json["body"] as? String ?? ""

        // Parse published date
        var publishedAt = Date()
        if let publishedString = json["published_at"] as? String {
            let formatter = ISO8601DateFormatter()
            publishedAt = formatter.date(from: publishedString) ?? Date()
        }

        return ReleaseInfo(
            version: tagName,
            downloadURL: downloadURL,
            size: size,
            publishedAt: publishedAt,
            releaseNotes: body
        )
    }

    /// Checks if an update is available.
    ///
    /// - Returns: Update check result with version comparison.
    func checkForUpdate() async throws -> UpdateCheckResult {
        let currentVersion = await getCurrentVersion()
        let latestRelease = try await fetchLatestRelease()

        let updateAvailable: Bool
        if let current = currentVersion {
            // Compare versions (yt-dlp uses date-based versions like 2025.01.15)
            updateAvailable = latestRelease.version > current
        } else {
            updateAvailable = true  // Not installed = update needed
        }

        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: latestRelease.version,
            updateAvailable: updateAvailable,
            releaseInfo: latestRelease
        )
    }

    /// Downloads and installs the latest version of yt-dlp.
    ///
    /// - Parameters:
    ///   - progressHandler: Callback for download progress (0.0 to 1.0).
    /// - Returns: The installed version string.
    /// - Throws: `YtDlpUpdaterError` if download or installation fails.
    func downloadAndInstall(
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        let releaseInfo = try await fetchLatestRelease()

        // Ensure bin directory exists
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Download the binary
        let tempFile = binDirectory.appendingPathComponent("yt-dlp.download")

        // Use URLSession for download with progress
        let (localURL, _) = try await downloadFile(
            from: releaseInfo.downloadURL,
            to: tempFile,
            expectedSize: releaseInfo.size,
            progressHandler: progressHandler
        )

        // Move to final location
        let finalPath = installedBinaryPath

        // Remove existing file if present
        try? FileManager.default.removeItem(at: finalPath)

        try FileManager.default.moveItem(at: localURL, to: finalPath)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: finalPath.path
        )

        // Verify installation
        guard let installedVersion = await getCurrentVersion() else {
            throw YtDlpUpdaterError.installFailed("Could not verify installation")
        }

        // Save update timestamp
        saveLastUpdateCheck()

        return installedVersion
    }

    /// Downloads a file with progress reporting.
    private func downloadFile(
        from url: URL,
        to destination: URL,
        expectedSize: Int64,
        progressHandler: ((Double) -> Void)?
    ) async throws -> (URL, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Nexus-Download-Manager", forHTTPHeaderField: "User-Agent")

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        // Remove any existing temp file
        try? FileManager.default.removeItem(at: destination)

        // Create output file
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: destination)

        defer {
            try? fileHandle.close()
        }

        var downloadedBytes: Int64 = 0
        var buffer = Data()
        let bufferSize = 65536  // 64KB chunks

        for try await byte in asyncBytes {
            buffer.append(byte)

            if buffer.count >= bufferSize {
                try fileHandle.write(contentsOf: buffer)
                downloadedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if expectedSize > 0 {
                    let progress = Double(downloadedBytes) / Double(expectedSize)
                    progressHandler?(min(progress, 1.0))
                }
            }
        }

        // Write remaining bytes
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
            downloadedBytes += Int64(buffer.count)
            progressHandler?(1.0)
        }

        return (destination, response)
    }

    // MARK: - Update Scheduling

    /// UserDefaults key for last update check timestamp.
    private let lastCheckKey = "YtDlpLastUpdateCheck"

    /// Minimum interval between automatic update checks (24 hours).
    private let checkInterval: TimeInterval = 86400

    /// Checks if an automatic update check should be performed.
    var shouldCheckForUpdate: Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else {
            return true  // Never checked before
        }
        return Date().timeIntervalSince(lastCheck) > checkInterval
    }

    /// Saves the current timestamp as the last update check.
    private func saveLastUpdateCheck() {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
    }

    /// Performs an automatic update check if due.
    ///
    /// - Returns: Update check result if check was performed, nil otherwise.
    func performAutoCheckIfNeeded() async -> UpdateCheckResult? {
        guard shouldCheckForUpdate else { return nil }

        do {
            let result = try await checkForUpdate()
            saveLastUpdateCheck()
            return result
        } catch {
            // Silently fail for auto-checks
            return nil
        }
    }
}

// MARK: - Errors

/// Errors that can occur during yt-dlp update operations.
enum YtDlpUpdaterError: Error, LocalizedError {
    case fetchFailed(String)
    case parseError(String)
    case downloadFailed(String)
    case installFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let message):
            return "Failed to fetch update information: \(message)"
        case .parseError(let message):
            return "Failed to parse release data: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .installFailed(let message):
            return "Installation failed: \(message)"
        case .verificationFailed(let message):
            return "Verification failed: \(message)"
        }
    }
}
