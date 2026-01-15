import Foundation

/// Handles automatic updates for the yt-dlp binary.
actor ytDlpUpdater {
    static let shared = ytDlpUpdater()
    
    private let githubReleaseURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
    
    private init() {}
    
    /// Checks for and installs updates for yt-dlp.
    func checkForUpdates() async {
        do {
            guard let latestRelease = try await fetchLatestReleaseInfo() else { return }
            let currentVersion = await getCurrentVersion()
            
            if ytDlpUpdater.isVersion(latestRelease.tagName, newerThan: currentVersion) {
                print("ytDlpUpdater: New version available: \(latestRelease.tagName) (current: \(currentVersion))")
                try await downloadAndInstall(release: latestRelease)
            } else {
                print("ytDlpUpdater: yt-dlp is up to date (\(currentVersion))")
            }
        } catch {
            print("ytDlpUpdater: Failed to check for updates: \(error)")
        }
    }
    
    private struct ReleaseInfo: Codable {
        let tagName: String
        let assets: [Asset]
        
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }
    
    private struct Asset: Codable {
        let name: String
        let browserDownloadURL: URL
        
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
    
    private func fetchLatestReleaseInfo() async throws -> ReleaseInfo? {
        var request = URLRequest(url: githubReleaseURL)
        request.setValue("ProjectNexus/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }
    
    private func getCurrentVersion() async -> String {
        let process = Process()
        // We need to get the current path from MediaExtractor or duplicate logic
        // For simplicity in this actor, we'll just try to run it.
        // We'll use a simplified version check.
        
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nexusDir = appSupport.appendingPathComponent("Nexus")
        let updatedYtDlp = nexusDir.appendingPathComponent("bin/yt-dlp")
        
        let executableURL: URL
        if fileManager.fileExists(atPath: updatedYtDlp.path) {
            executableURL = updatedYtDlp
        } else if let bundlePath = Bundle.main.url(forResource: "yt-dlp", withExtension: nil, subdirectory: "bin") {
            executableURL = bundlePath
        } else {
            return "0.0.0"
        }
        
        process.executableURL = executableURL
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.0.0"
        } catch {
            return "0.0.0"
        }
    }
    
    static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        // Simple comparison for yt-dlp versioning (usually YYYY.MM.DD)
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
    
    private func downloadAndInstall(release: ReleaseInfo) async throws {
        // Find the macOS binary. Usually named 'yt-dlp_macos' or 'yt-dlp'
        // For now, let's assume 'yt-dlp' is what we want if it's there, 
        // or we might need to handle the python version.
        // On macOS, often the 'yt-dlp' asset is the one.
        
        guard let asset = release.assets.first(where: { $0.name == "yt-dlp" }) else {
            print("ytDlpUpdater: Could not find 'yt-dlp' asset in release")
            return
        }
        
        print("ytDlpUpdater: Downloading \(asset.browserDownloadURL)...")
        let (tempURL, _) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let binDir = appSupport.appendingPathComponent("Nexus/bin")
        
        try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
        let destinationURL = binDir.appendingPathComponent("yt-dlp")
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        
        // Make it executable
        var attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let permissions = attributes[.posixPermissions] as? UInt16 ?? 0o644
        attributes[.posixPermissions] = permissions | 0o111 // Add execute bits
        try fileManager.setAttributes(attributes, ofItemAtPath: destinationURL.path)
        
        print("ytDlpUpdater: Successfully installed yt-dlp version \(release.tagName)")
    }
}
