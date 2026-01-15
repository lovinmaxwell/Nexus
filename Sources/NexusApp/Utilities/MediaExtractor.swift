import Foundation

actor MediaExtractor {
    static let shared = MediaExtractor()

    struct MediaInfo {
        let directURL: String
        let title: String
        let fileExtension: String
        let fileSize: Int64?
    }

    func isMediaURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaHosts = ["youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv"]
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return false
        }
        return mediaHosts.contains { host.contains($0) }
    }

    private var ytDlpPath: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nexusDir = appSupport.appendingPathComponent("Nexus")
        let updatedYtDlp = nexusDir.appendingPathComponent("bin/yt-dlp")

        if fileManager.fileExists(atPath: updatedYtDlp.path) {
            return updatedYtDlp
        }

        if let bundlePath = Bundle.main.url(
            forResource: "yt-dlp", withExtension: nil, subdirectory: "bin")
        {
            return bundlePath
        }

        // Development fallback: Check known local paths
        let localPaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            // Fallback to the dummy script in source during development if accessible
            URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/bin/yt-dlp").path,
        ]

        for path in localPaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return URL(fileURLWithPath: "/usr/bin/false")
    }

    func extractMediaInfo(from urlString: String) async throws -> MediaInfo {
        let process = Process()
        process.executableURL = ytDlpPath
        process.arguments = [
            "-j",
            "--no-warnings",
            urlString,
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0,
            let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any]
        else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw MediaExtractorError.extractionFailed(errorString)
        }

        guard let directURL = json["url"] as? String else {
            throw MediaExtractorError.noDirectURL
        }

        let title = json["title"] as? String ?? "video"
        let ext = json["ext"] as? String ?? "mp4"
        let fileSize = json["filesize"] as? Int64 ?? json["filesize_approx"] as? Int64

        return MediaInfo(directURL: directURL, title: title, fileExtension: ext, fileSize: fileSize)
    }

    func getDirectURL(from urlString: String, format: String = "best") async throws -> String {
        let process = Process()
        process.executableURL = ytDlpPath
        process.arguments = [
            "-f", format,
            "-g",
            "--no-warnings",
            urlString,
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0,
            let urlOutput = String(data: outputData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            !urlOutput.isEmpty
        else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw MediaExtractorError.extractionFailed(errorString)
        }

        return urlOutput.components(separatedBy: "\n").first ?? urlOutput
    }
}

enum MediaExtractorError: Error, LocalizedError {
    case extractionFailed(String)
    case noDirectURL
    case ytdlpNotFound

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Media extraction failed: \(msg)"
        case .noDirectURL: return "Could not get direct download URL"
        case .ytdlpNotFound: return "yt-dlp not found. Please install it with: brew install yt-dlp"
        }
    }
}
