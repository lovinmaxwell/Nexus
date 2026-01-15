import Foundation

/// Actor responsible for extracting media information from URLs.
///
/// Supports YouTube, Vimeo, and other video sites via yt-dlp integration,
/// as well as HLS/M3U8 adaptive bitrate streams.
actor MediaExtractor {
    static let shared = MediaExtractor()

    // MARK: - Data Types

    /// Information about an extracted media file.
    struct MediaInfo {
        let directURL: String
        let title: String
        let fileExtension: String
        let fileSize: Int64?
        let isHLS: Bool
        let availableFormats: [MediaFormat]

        init(
            directURL: String,
            title: String,
            fileExtension: String,
            fileSize: Int64?,
            isHLS: Bool = false,
            availableFormats: [MediaFormat] = []
        ) {
            self.directURL = directURL
            self.title = title
            self.fileExtension = fileExtension
            self.fileSize = fileSize
            self.isHLS = isHLS
            self.availableFormats = availableFormats
        }
    }

    /// Represents a media format/quality option.
    struct MediaFormat: Identifiable, Equatable {
        let id: String
        let resolution: String?
        let fileExtension: String
        let fileSize: Int64?
        let bitrate: Int64?
        let isAudioOnly: Bool
        let isVideoOnly: Bool
        let description: String

        var displayName: String {
            var parts: [String] = []
            if let res = resolution {
                parts.append(res)
            }
            parts.append(fileExtension.uppercased())
            if isAudioOnly {
                parts.append("(Audio)")
            } else if isVideoOnly {
                parts.append("(Video)")
            }
            if let br = bitrate {
                let formattedBitrate = formatBitrate(br)
                parts.append("@ \(formattedBitrate)")
            }
            return parts.joined(separator: " ")
        }

        private func formatBitrate(_ bps: Int64) -> String {
            if bps >= 1_000_000 {
                return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
            } else {
                return String(format: "%d Kbps", bps / 1000)
            }
        }
    }

    /// HLS stream information parsed from M3U8 playlist.
    struct HLSStreamInfo {
        let bandwidth: Int64
        let resolution: String?
        let codecs: String?
        let url: String
    }

    // MARK: - URL Detection (nonisolated for performance)

    /// Checks if the URL is a supported media URL.
    ///
    /// - Parameter urlString: The URL to check.
    /// - Returns: `true` if the URL is a media site, HLS, or DASH stream.
    nonisolated func isMediaURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaHosts = ["youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv"]
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            // Check if it's an adaptive streaming URL even without host
            return isAdaptiveStreamURL(trimmed)
        }
        return mediaHosts.contains { host.contains($0) } || isAdaptiveStreamURL(trimmed)
    }

    /// Checks if the URL is an HLS/M3U8 stream.
    ///
    /// - Parameter urlString: The URL to check.
    /// - Returns: `true` if the URL ends with .m3u8 or contains m3u8 in path.
    nonisolated func isHLSURL(_ urlString: String) -> Bool {
        let lowercased = urlString.lowercased()
        return lowercased.hasSuffix(".m3u8") ||
               lowercased.contains(".m3u8?") ||
               lowercased.contains("/hls/") ||
               lowercased.contains("playlist.m3u8")
    }

    /// Checks if the URL is a DASH/MPD stream.
    ///
    /// - Parameter urlString: The URL to check.
    /// - Returns: `true` if the URL ends with .mpd or contains dash indicators.
    nonisolated func isDASHURL(_ urlString: String) -> Bool {
        let lowercased = urlString.lowercased()
        return lowercased.hasSuffix(".mpd") ||
               lowercased.contains(".mpd?") ||
               lowercased.contains("/dash/") ||
               lowercased.contains("manifest.mpd")
    }

    /// Checks if the URL is an adaptive streaming URL (HLS or DASH).
    ///
    /// - Parameter urlString: The URL to check.
    /// - Returns: `true` if the URL is HLS or DASH.
    nonisolated func isAdaptiveStreamURL(_ urlString: String) -> Bool {
        return isHLSURL(urlString) || isDASHURL(urlString)
    }

    // MARK: - yt-dlp Path Resolution

    private var ytDlpPath: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nexusDir = appSupport.appendingPathComponent("Nexus")
        let updatedYtDlp = nexusDir.appendingPathComponent("bin/yt-dlp")

        if fileManager.isExecutableFile(atPath: updatedYtDlp.path) {
            return updatedYtDlp
        }

        if let bundlePath = Bundle.main.url(
            forResource: "yt-dlp", withExtension: nil, subdirectory: "bin"),
           fileManager.isExecutableFile(atPath: bundlePath.path)
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
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return URL(fileURLWithPath: "/usr/bin/false")
    }
    
    /// Checks if yt-dlp is available.
    var isYtDlpAvailable: Bool {
        let path = ytDlpPath.path
        return path != "/usr/bin/false" && FileManager.default.isExecutableFile(atPath: path)
    }

    // MARK: - Media Extraction

    /// Extracts media information from a URL.
    ///
    /// For HLS streams, parses the M3U8 playlist to get available qualities.
    /// For DASH streams, parses the MPD manifest to get available qualities.
    /// For other media sites, uses yt-dlp for extraction.
    ///
    /// - Parameter urlString: The URL to extract from.
    /// - Returns: Media information including available formats.
    /// - Throws: `MediaExtractorError` if extraction fails.
    func extractMediaInfo(from urlString: String) async throws -> MediaInfo {
        // Check if it's an HLS stream first
        if isHLSURL(urlString) {
            return try await extractHLSInfo(from: urlString)
        }

        // Check if it's a DASH stream
        if isDASHURL(urlString) {
            return try await extractDASHInfo(from: urlString)
        }

        // Use yt-dlp for other media
        return try await extractWithYtDlp(from: urlString)
    }

    /// Extracts media info using yt-dlp.
    private func extractWithYtDlp(from urlString: String) async throws -> MediaInfo {
        // Check if yt-dlp exists
        let path = ytDlpPath.path
        guard path != "/usr/bin/false" && FileManager.default.isExecutableFile(atPath: path) else {
            throw MediaExtractorError.ytdlpNotFound
        }
        
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
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0,
            let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any]
        else {
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("MediaExtractor: yt-dlp failed - \(errorString)")
            throw MediaExtractorError.extractionFailed(errorString)
        }

        let title = json["title"] as? String ?? "video"
        let ext = json["ext"] as? String ?? "mp4"
        let fileSize = json["filesize"] as? Int64 ?? json["filesize_approx"] as? Int64
        
        // For YouTube and similar sites, there's no direct URL - we need to use yt-dlp to download
        // Store the original URL as the "directURL" and mark it as needing yt-dlp download
        let directURL = json["url"] as? String ?? urlString
        let isHLS = ext == "m3u8" || directURL.contains(".m3u8")

        // Parse available formats
        let formats = parseFormats(from: json)

        return MediaInfo(
            directURL: directURL,
            title: title,
            fileExtension: ext,
            fileSize: fileSize,
            isHLS: isHLS,
            availableFormats: formats
        )
    }

    /// Parses format list from yt-dlp JSON output.
    private func parseFormats(from json: [String: Any]) -> [MediaFormat] {
        guard let formatsArray = json["formats"] as? [[String: Any]] else {
            return []
        }

        return formatsArray.compactMap { formatDict -> MediaFormat? in
            guard let formatId = formatDict["format_id"] as? String else { return nil }

            let resolution: String?
            if let height = formatDict["height"] as? Int {
                resolution = "\(height)p"
            } else {
                resolution = nil
            }

            let ext = formatDict["ext"] as? String ?? "mp4"
            let fileSize = formatDict["filesize"] as? Int64 ?? formatDict["filesize_approx"] as? Int64
            let bitrate = formatDict["tbr"] as? Int64 ?? formatDict["vbr"] as? Int64

            let vcodec = formatDict["vcodec"] as? String ?? "none"
            let acodec = formatDict["acodec"] as? String ?? "none"

            let isVideoOnly = vcodec != "none" && acodec == "none"
            let isAudioOnly = acodec != "none" && vcodec == "none"

            let description = formatDict["format"] as? String ?? formatId

            return MediaFormat(
                id: formatId,
                resolution: resolution,
                fileExtension: ext,
                fileSize: fileSize,
                bitrate: bitrate,
                isAudioOnly: isAudioOnly,
                isVideoOnly: isVideoOnly,
                description: description
            )
        }
    }

    // MARK: - HLS/M3U8 Support

    /// Extracts information from an HLS/M3U8 stream.
    ///
    /// Parses the master playlist to get available quality options.
    ///
    /// - Parameter urlString: The M3U8 URL.
    /// - Returns: Media information with HLS streams.
    /// - Throws: `MediaExtractorError` if parsing fails.
    func extractHLSInfo(from urlString: String) async throws -> MediaInfo {
        guard let url = URL(string: urlString) else {
            throw MediaExtractorError.invalidURL
        }

        // Download the M3U8 playlist
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let playlistContent = String(data: data, encoding: .utf8) else {
            throw MediaExtractorError.extractionFailed("Could not decode M3U8 playlist")
        }

        // Parse the M3U8 playlist
        let streams = parseM3U8Playlist(playlistContent, baseURL: url)

        // Create formats from streams
        let formats = streams.map { stream -> MediaFormat in
            let resolution = stream.resolution ?? "Unknown"
            return MediaFormat(
                id: stream.url,
                resolution: resolution,
                fileExtension: "ts",
                fileSize: nil,
                bitrate: stream.bandwidth,
                isAudioOnly: false,
                isVideoOnly: false,
                description: "HLS \(resolution) @ \(formatBandwidth(stream.bandwidth))"
            )
        }

        // Use best quality as default
        let bestStream = streams.max(by: { $0.bandwidth < $1.bandwidth })
        let title = extractTitleFromURL(url)

        return MediaInfo(
            directURL: bestStream?.url ?? urlString,
            title: title,
            fileExtension: "ts",
            fileSize: nil,
            isHLS: true,
            availableFormats: formats
        )
    }

    /// Parses an M3U8 master playlist to extract stream variants.
    ///
    /// - Parameters:
    ///   - content: The playlist content.
    ///   - baseURL: Base URL for resolving relative URLs.
    /// - Returns: Array of HLS stream information.
    func parseM3U8Playlist(_ content: String, baseURL: URL) -> [HLSStreamInfo] {
        var streams: [HLSStreamInfo] = []
        let lines = content.components(separatedBy: .newlines)

        var currentBandwidth: Int64 = 0
        var currentResolution: String?
        var currentCodecs: String?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("#EXT-X-STREAM-INF:") {
                // Parse stream info
                let attributes = parseM3U8Attributes(String(trimmedLine.dropFirst("#EXT-X-STREAM-INF:".count)))
                currentBandwidth = Int64(attributes["BANDWIDTH"] ?? "") ?? 0
                currentResolution = attributes["RESOLUTION"]
                currentCodecs = attributes["CODECS"]
            } else if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                // This is a stream URL
                let streamURL: String
                if trimmedLine.hasPrefix("http://") || trimmedLine.hasPrefix("https://") {
                    streamURL = trimmedLine
                } else {
                    // Resolve relative URL
                    if let resolvedURL = URL(string: trimmedLine, relativeTo: baseURL) {
                        streamURL = resolvedURL.absoluteString
                    } else {
                        continue
                    }
                }

                if currentBandwidth > 0 {
                    streams.append(HLSStreamInfo(
                        bandwidth: currentBandwidth,
                        resolution: currentResolution,
                        codecs: currentCodecs,
                        url: streamURL
                    ))
                }

                // Reset for next stream
                currentBandwidth = 0
                currentResolution = nil
                currentCodecs = nil
            }
        }

        return streams.sorted { $0.bandwidth > $1.bandwidth }
    }

    /// Parses M3U8 attribute string into a dictionary.
    private func parseM3U8Attributes(_ attributeString: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var remaining = attributeString

        while !remaining.isEmpty {
            // Find key
            guard let equalsIndex = remaining.firstIndex(of: "=") else { break }
            let key = String(remaining[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            remaining = String(remaining[remaining.index(after: equalsIndex)...])

            // Find value
            let value: String
            if remaining.hasPrefix("\"") {
                // Quoted value
                remaining = String(remaining.dropFirst())
                if let endQuote = remaining.firstIndex(of: "\"") {
                    value = String(remaining[..<endQuote])
                    remaining = String(remaining[remaining.index(after: endQuote)...])
                } else {
                    value = remaining
                    remaining = ""
                }
            } else {
                // Unquoted value
                if let commaIndex = remaining.firstIndex(of: ",") {
                    value = String(remaining[..<commaIndex])
                    remaining = String(remaining[remaining.index(after: commaIndex)...])
                } else {
                    value = remaining
                    remaining = ""
                }
            }

            attributes[key] = value.trimmingCharacters(in: .whitespaces)
        }

        return attributes
    }

    /// Extracts a title from a URL path.
    private func extractTitleFromURL(_ url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent
        if filename.isEmpty || filename == "playlist" || filename == "master" {
            return "HLS Stream"
        }
        return filename.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    /// Formats bandwidth in human-readable form.
    private func formatBandwidth(_ bps: Int64) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else {
            return String(format: "%d Kbps", bps / 1000)
        }
    }

    // MARK: - DASH/MPD Support

    /// DASH representation information parsed from MPD manifest.
    struct DASHRepresentation {
        let id: String
        let bandwidth: Int64
        let width: Int?
        let height: Int?
        let mimeType: String
        let codecs: String?
        let baseURL: String?
        let isAudio: Bool
        let isVideo: Bool
    }

    /// Extracts information from a DASH/MPD stream.
    ///
    /// Parses the MPD manifest to get available quality options.
    ///
    /// - Parameter urlString: The MPD URL.
    /// - Returns: Media information with DASH representations.
    /// - Throws: `MediaExtractorError` if parsing fails.
    func extractDASHInfo(from urlString: String) async throws -> MediaInfo {
        guard let url = URL(string: urlString) else {
            throw MediaExtractorError.invalidURL
        }

        // Download the MPD manifest
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let mpdContent = String(data: data, encoding: .utf8) else {
            throw MediaExtractorError.extractionFailed("Could not decode MPD manifest")
        }

        // Parse the MPD manifest
        let representations = parseMPDManifest(mpdContent, baseURL: url)

        // Create formats from representations
        let formats = representations.map { rep -> MediaFormat in
            let resolution: String?
            if let _ = rep.width, let height = rep.height {
                resolution = "\(height)p"
            } else {
                resolution = nil
            }

            let ext = extractExtensionFromMimeType(rep.mimeType)

            return MediaFormat(
                id: rep.id,
                resolution: resolution,
                fileExtension: ext,
                fileSize: nil,
                bitrate: rep.bandwidth,
                isAudioOnly: rep.isAudio && !rep.isVideo,
                isVideoOnly: rep.isVideo && !rep.isAudio,
                description: "DASH \(resolution ?? "audio") @ \(formatBandwidth(rep.bandwidth))"
            )
        }

        // Use best video quality as default
        let bestVideo = representations
            .filter { $0.isVideo }
            .max(by: { $0.bandwidth < $1.bandwidth })

        let title = extractTitleFromURL(url)

        return MediaInfo(
            directURL: bestVideo?.baseURL ?? urlString,
            title: title,
            fileExtension: "mp4",
            fileSize: nil,
            isHLS: false,
            availableFormats: formats
        )
    }

    /// Parses an MPD manifest to extract representations.
    ///
    /// This is a simplified parser for common MPD structures.
    ///
    /// - Parameters:
    ///   - content: The MPD XML content.
    ///   - baseURL: Base URL for resolving relative URLs.
    /// - Returns: Array of DASH representation information.
    func parseMPDManifest(_ content: String, baseURL: URL) -> [DASHRepresentation] {
        var representations: [DASHRepresentation] = []

        // Simple XML parsing using regex patterns
        // Note: For production, consider using XMLParser or a proper XML library

        // Extract AdaptationSets
        let adaptationSetPattern = #"<AdaptationSet[^>]*>(.*?)</AdaptationSet>"#
        let adaptationSetRegex = try? NSRegularExpression(
            pattern: adaptationSetPattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )

        let nsContent = content as NSString
        let adaptationMatches = adaptationSetRegex?.matches(
            in: content,
            options: [],
            range: NSRange(location: 0, length: nsContent.length)
        ) ?? []

        for adaptationMatch in adaptationMatches {
            let adaptationSetContent = nsContent.substring(with: adaptationMatch.range)

            // Determine content type from AdaptationSet attributes
            let mimeType = extractXMLAttribute("mimeType", from: adaptationSetContent) ?? ""
            let isVideo = mimeType.contains("video") || adaptationSetContent.contains("contentType=\"video\"")
            let isAudio = mimeType.contains("audio") || adaptationSetContent.contains("contentType=\"audio\"")

            // Extract Representations within this AdaptationSet
            let representationPattern = #"<Representation[^>]*(?:/>|>.*?</Representation>)"#
            let representationRegex = try? NSRegularExpression(
                pattern: representationPattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            )

            let nsAdaptation = adaptationSetContent as NSString
            let repMatches = representationRegex?.matches(
                in: adaptationSetContent,
                options: [],
                range: NSRange(location: 0, length: nsAdaptation.length)
            ) ?? []

            for repMatch in repMatches {
                let repContent = nsAdaptation.substring(with: repMatch.range)

                guard let id = extractXMLAttribute("id", from: repContent) else { continue }

                let bandwidth = Int64(extractXMLAttribute("bandwidth", from: repContent) ?? "") ?? 0
                let width = Int(extractXMLAttribute("width", from: repContent) ?? "")
                let height = Int(extractXMLAttribute("height", from: repContent) ?? "")
                let codecs = extractXMLAttribute("codecs", from: repContent)
                let repMimeType = extractXMLAttribute("mimeType", from: repContent) ?? mimeType

                // Extract BaseURL if present
                var segmentBaseURL: String?
                if let baseURLMatch = repContent.range(of: #"<BaseURL[^>]*>([^<]+)</BaseURL>"#, options: .regularExpression) {
                    let baseURLContent = String(repContent[baseURLMatch])
                    if let urlStart = baseURLContent.firstIndex(of: ">"),
                       let urlEnd = baseURLContent.lastIndex(of: "<") {
                        let urlPart = String(baseURLContent[baseURLContent.index(after: urlStart)..<urlEnd])
                        if urlPart.hasPrefix("http") {
                            segmentBaseURL = urlPart
                        } else {
                            segmentBaseURL = URL(string: urlPart, relativeTo: baseURL)?.absoluteString
                        }
                    }
                }

                representations.append(DASHRepresentation(
                    id: id,
                    bandwidth: bandwidth,
                    width: width,
                    height: height,
                    mimeType: repMimeType,
                    codecs: codecs,
                    baseURL: segmentBaseURL,
                    isAudio: isAudio || repMimeType.contains("audio"),
                    isVideo: isVideo || repMimeType.contains("video")
                ))
            }
        }

        return representations.sorted { $0.bandwidth > $1.bandwidth }
    }

    /// Extracts an XML attribute value from a tag string.
    private func extractXMLAttribute(_ name: String, from content: String) -> String? {
        // Pattern: attribute="value" or attribute='value'
        let patterns = [
            "\(name)=\"([^\"]+)\"",
            "\(name)='([^']+)'"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: (content as NSString).length)),
               match.numberOfRanges > 1 {
                return (content as NSString).substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    /// Extracts file extension from MIME type.
    private func extractExtensionFromMimeType(_ mimeType: String) -> String {
        let mapping: [String: String] = [
            "video/mp4": "mp4",
            "video/webm": "webm",
            "audio/mp4": "m4a",
            "audio/webm": "webm",
            "audio/mpeg": "mp3",
            "video/mp2t": "ts",
        ]

        for (mime, ext) in mapping {
            if mimeType.contains(mime) {
                return ext
            }
        }
        return "mp4"
    }

    // MARK: - Direct URL Extraction

    /// Gets a direct download URL for the media.
    ///
    /// - Parameters:
    ///   - urlString: The media URL.
    ///   - format: The format ID to download (default: "best").
    /// - Returns: Direct download URL.
    /// - Throws: `MediaExtractorError` if extraction fails.
    func getDirectURL(from urlString: String, format: String = "best") async throws -> String {
        // For HLS URLs, return as-is or the format URL
        if isHLSURL(urlString) {
            if format != "best" && format.hasPrefix("http") {
                return format  // format is actually a stream URL
            }
            return urlString
        }

        // For DASH URLs, return as-is or the format URL
        if isDASHURL(urlString) {
            if format != "best" && format.hasPrefix("http") {
                return format  // format is actually a segment URL
            }
            return urlString
        }

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

    // MARK: - Format Listing

    /// Lists all available formats for a media URL.
    ///
    /// - Parameter urlString: The media URL.
    /// - Returns: Array of available formats.
    /// - Throws: `MediaExtractorError` if listing fails.
    func listFormats(from urlString: String) async throws -> [MediaFormat] {
        // For HLS, parse the playlist
        if isHLSURL(urlString) {
            let info = try await extractHLSInfo(from: urlString)
            return info.availableFormats
        }

        // For DASH, parse the manifest
        if isDASHURL(urlString) {
            let info = try await extractDASHInfo(from: urlString)
            return info.availableFormats
        }

        // Use yt-dlp to list formats
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

        return parseFormats(from: json)
    }
}

/// Errors that can occur during media extraction.
enum MediaExtractorError: Error, LocalizedError {
    case extractionFailed(String)
    case noDirectURL
    case ytdlpNotFound
    case invalidURL
    case hlsParsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg):
            return "Media extraction failed: \(msg)"
        case .noDirectURL:
            return "Could not get direct download URL"
        case .ytdlpNotFound:
            return "yt-dlp not found. Please install it with: brew install yt-dlp"
        case .invalidURL:
            return "The URL is invalid"
        case .hlsParsingFailed(let msg):
            return "Failed to parse HLS stream: \(msg)"
        }
    }
}
