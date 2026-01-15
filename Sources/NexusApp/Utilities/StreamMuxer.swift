import Foundation

/// Actor responsible for muxing (combining) separate audio and video streams.
///
/// Uses ffmpeg for stream muxing operations. This is needed because many video
/// platforms serve audio and video as separate streams that need to be combined.
actor StreamMuxer {
    static let shared = StreamMuxer()

    // MARK: - Muxing Configuration

    /// Configuration options for muxing operations.
    struct MuxingConfig {
        /// Output container format (e.g., "mp4", "mkv", "webm").
        let outputFormat: String

        /// Whether to copy streams without re-encoding (faster but may fail with incompatible codecs).
        let copyStreams: Bool

        /// Video codec to use for re-encoding (nil for copy).
        let videoCodec: String?

        /// Audio codec to use for re-encoding (nil for copy).
        let audioCodec: String?

        /// Additional ffmpeg arguments.
        let extraArgs: [String]

        /// Default configuration: copy streams to MP4 container.
        static let `default` = MuxingConfig(
            outputFormat: "mp4",
            copyStreams: true,
            videoCodec: nil,
            audioCodec: nil,
            extraArgs: []
        )

        /// Configuration for re-encoding to H.264/AAC (maximum compatibility).
        static let h264AAC = MuxingConfig(
            outputFormat: "mp4",
            copyStreams: false,
            videoCodec: "libx264",
            audioCodec: "aac",
            extraArgs: ["-preset", "medium", "-crf", "23"]
        )
    }

    /// Result of a muxing operation.
    struct MuxingResult {
        let outputPath: String
        let duration: TimeInterval
        let success: Bool
        let errorMessage: String?
    }

    // MARK: - ffmpeg Path Resolution

    private var ffmpegPath: URL {
        // Check bundled location first
        if let bundlePath = Bundle.main.url(
            forResource: "ffmpeg", withExtension: nil, subdirectory: "bin")
        {
            return bundlePath
        }

        // Development fallback: Check known local paths
        let localPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]

        for path in localPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return URL(fileURLWithPath: "/usr/bin/false")
    }

    /// Checks if ffmpeg is available.
    var isAvailable: Bool {
        let path = ffmpegPath.path
        return FileManager.default.isExecutableFile(atPath: path) && path != "/usr/bin/false"
    }

    // MARK: - Muxing Operations

    /// Muxes (combines) separate audio and video streams into a single file.
    ///
    /// - Parameters:
    ///   - videoPath: Path to the video-only file.
    ///   - audioPath: Path to the audio-only file.
    ///   - outputPath: Path for the combined output file.
    ///   - config: Muxing configuration options.
    ///   - progressHandler: Callback for progress updates (0.0 to 1.0).
    /// - Returns: Result of the muxing operation.
    func mux(
        videoPath: String,
        audioPath: String,
        outputPath: String,
        config: MuxingConfig = .default,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> MuxingResult {
        guard isAvailable else {
            throw StreamMuxerError.ffmpegNotFound
        }

        // Verify input files exist
        guard FileManager.default.fileExists(atPath: videoPath) else {
            throw StreamMuxerError.inputFileNotFound(videoPath)
        }
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw StreamMuxerError.inputFileNotFound(audioPath)
        }

        // Get duration for progress calculation
        let duration = try await getMediaDuration(path: videoPath) ?? 0

        // Build ffmpeg arguments
        var args: [String] = [
            "-y",  // Overwrite output file
            "-i", videoPath,
            "-i", audioPath,
        ]

        if config.copyStreams {
            args.append(contentsOf: ["-c:v", "copy", "-c:a", "copy"])
        } else {
            if let videoCodec = config.videoCodec {
                args.append(contentsOf: ["-c:v", videoCodec])
            }
            if let audioCodec = config.audioCodec {
                args.append(contentsOf: ["-c:a", audioCodec])
            }
        }

        args.append(contentsOf: config.extraArgs)
        args.append(contentsOf: ["-f", config.outputFormat, outputPath])

        let startTime = Date()

        // Run ffmpeg
        let process = Process()
        process.executableURL = ffmpegPath
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        // Monitor progress by reading stderr (ffmpeg outputs progress there)
        if let handler = progressHandler, duration > 0 {
            await monitorProgress(
                errorPipe: errorPipe,
                totalDuration: duration,
                progressHandler: handler
            )
        }

        process.waitUntilExit()

        let elapsedTime = Date().timeIntervalSince(startTime)

        if process.terminationStatus == 0 {
            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: true,
                errorMessage: nil
            )
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: false,
                errorMessage: errorString
            )
        }
    }

    /// Remuxes a single file to a different container format.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the input file.
    ///   - outputPath: Path for the output file.
    ///   - outputFormat: Target container format.
    /// - Returns: Result of the muxing operation.
    func remux(
        inputPath: String,
        outputPath: String,
        outputFormat: String = "mp4"
    ) async throws -> MuxingResult {
        guard isAvailable else {
            throw StreamMuxerError.ffmpegNotFound
        }

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw StreamMuxerError.inputFileNotFound(inputPath)
        }

        let args = [
            "-y",
            "-i", inputPath,
            "-c", "copy",
            "-f", outputFormat,
            outputPath,
        ]

        let startTime = Date()

        let process = Process()
        process.executableURL = ffmpegPath
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let elapsedTime = Date().timeIntervalSince(startTime)

        if process.terminationStatus == 0 {
            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: true,
                errorMessage: nil
            )
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: false,
                errorMessage: errorString
            )
        }
    }

    /// Concatenates multiple video files into one.
    ///
    /// Useful for combining HLS/DASH segments.
    ///
    /// - Parameters:
    ///   - inputPaths: Paths to input files (in order).
    ///   - outputPath: Path for the output file.
    ///   - outputFormat: Target container format.
    /// - Returns: Result of the concatenation.
    func concatenate(
        inputPaths: [String],
        outputPath: String,
        outputFormat: String = "mp4"
    ) async throws -> MuxingResult {
        guard isAvailable else {
            throw StreamMuxerError.ffmpegNotFound
        }

        guard !inputPaths.isEmpty else {
            throw StreamMuxerError.noInputFiles
        }

        // Create a temporary file list for ffmpeg concat demuxer
        let listFilePath = NSTemporaryDirectory() + "concat_\(UUID().uuidString).txt"
        let listContent = inputPaths.map { "file '\($0)'" }.joined(separator: "\n")

        try listContent.write(toFile: listFilePath, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: listFilePath)
        }

        let args = [
            "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", listFilePath,
            "-c", "copy",
            "-f", outputFormat,
            outputPath,
        ]

        let startTime = Date()

        let process = Process()
        process.executableURL = ffmpegPath
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let elapsedTime = Date().timeIntervalSince(startTime)

        if process.terminationStatus == 0 {
            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: true,
                errorMessage: nil
            )
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: false,
                errorMessage: errorString
            )
        }
    }

    // MARK: - Metadata Embedding

    /// Metadata tags that can be embedded in media files.
    struct MediaMetadata {
        var title: String?
        var artist: String?
        var album: String?
        var year: String?
        var comment: String?
        var genre: String?
        var track: String?
        var description: String?
        var copyright: String?
        var customTags: [String: String] = [:]

        /// Creates metadata from yt-dlp JSON output.
        init(from ytdlpInfo: [String: Any]) {
            title = ytdlpInfo["title"] as? String
            artist = ytdlpInfo["uploader"] as? String ?? ytdlpInfo["artist"] as? String
            album = ytdlpInfo["album"] as? String
            year = ytdlpInfo["upload_date"] as? String
            description = ytdlpInfo["description"] as? String
            genre = ytdlpInfo["genre"] as? String

            // Extract year from upload_date if available (format: YYYYMMDD)
            if let uploadDate = ytdlpInfo["upload_date"] as? String, uploadDate.count >= 4 {
                year = String(uploadDate.prefix(4))
            }
        }

        /// Empty metadata.
        init() {}

        /// Converts metadata to ffmpeg -metadata arguments.
        func toFFmpegArgs() -> [String] {
            var args: [String] = []

            if let title = title { args.append(contentsOf: ["-metadata", "title=\(title)"]) }
            if let artist = artist { args.append(contentsOf: ["-metadata", "artist=\(artist)"]) }
            if let album = album { args.append(contentsOf: ["-metadata", "album=\(album)"]) }
            if let year = year { args.append(contentsOf: ["-metadata", "year=\(year)"]) }
            if let comment = comment { args.append(contentsOf: ["-metadata", "comment=\(comment)"]) }
            if let genre = genre { args.append(contentsOf: ["-metadata", "genre=\(genre)"]) }
            if let track = track { args.append(contentsOf: ["-metadata", "track=\(track)"]) }
            if let description = description { args.append(contentsOf: ["-metadata", "description=\(description)"]) }
            if let copyright = copyright { args.append(contentsOf: ["-metadata", "copyright=\(copyright)"]) }

            for (key, value) in customTags {
                args.append(contentsOf: ["-metadata", "\(key)=\(value)"])
            }

            return args
        }
    }

    /// Embeds metadata into a media file.
    ///
    /// Creates a new file with the embedded metadata (ffmpeg doesn't modify in-place).
    ///
    /// - Parameters:
    ///   - inputPath: Path to the input file.
    ///   - outputPath: Path for the output file with metadata.
    ///   - metadata: Metadata to embed.
    /// - Returns: Result of the metadata embedding operation.
    func embedMetadata(
        inputPath: String,
        outputPath: String,
        metadata: MediaMetadata
    ) async throws -> MuxingResult {
        guard isAvailable else {
            throw StreamMuxerError.ffmpegNotFound
        }

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw StreamMuxerError.inputFileNotFound(inputPath)
        }

        var args = [
            "-y",
            "-i", inputPath,
            "-c", "copy",  // Don't re-encode
        ]

        args.append(contentsOf: metadata.toFFmpegArgs())
        args.append(outputPath)

        let startTime = Date()

        let process = Process()
        process.executableURL = ffmpegPath
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let elapsedTime = Date().timeIntervalSince(startTime)

        if process.terminationStatus == 0 {
            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: true,
                errorMessage: nil
            )
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: false,
                errorMessage: errorString
            )
        }
    }

    /// Reads existing metadata from a media file.
    ///
    /// - Parameter path: Path to the media file.
    /// - Returns: Metadata dictionary with tag names and values.
    func readMetadata(from path: String) async throws -> [String: String] {
        let ffprobePath = ffmpegPath.deletingLastPathComponent().appendingPathComponent("ffprobe")

        guard FileManager.default.isExecutableFile(atPath: ffprobePath.path) else {
            throw StreamMuxerError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = ffprobePath
        process.arguments = [
            "-v", "error",
            "-show_entries", "format_tags",
            "-of", "json",
            path,
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return [:]
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let tags = format["tags"] as? [String: String] else {
            return [:]
        }

        return tags
    }

    /// Embeds thumbnail/cover art into a media file.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the input media file.
    ///   - thumbnailPath: Path to the thumbnail image (JPEG/PNG).
    ///   - outputPath: Path for the output file with thumbnail.
    /// - Returns: Result of the thumbnail embedding operation.
    func embedThumbnail(
        inputPath: String,
        thumbnailPath: String,
        outputPath: String
    ) async throws -> MuxingResult {
        guard isAvailable else {
            throw StreamMuxerError.ffmpegNotFound
        }

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw StreamMuxerError.inputFileNotFound(inputPath)
        }

        guard FileManager.default.fileExists(atPath: thumbnailPath) else {
            throw StreamMuxerError.inputFileNotFound(thumbnailPath)
        }

        // For MP4: use -disposition:v:1 attached_pic
        // For MP3: use different method
        let args = [
            "-y",
            "-i", inputPath,
            "-i", thumbnailPath,
            "-map", "0",
            "-map", "1",
            "-c", "copy",
            "-disposition:v:1", "attached_pic",
            outputPath,
        ]

        let startTime = Date()

        let process = Process()
        process.executableURL = ffmpegPath
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let elapsedTime = Date().timeIntervalSince(startTime)

        if process.terminationStatus == 0 {
            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: true,
                errorMessage: nil
            )
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            return MuxingResult(
                outputPath: outputPath,
                duration: elapsedTime,
                success: false,
                errorMessage: errorString
            )
        }
    }

    // MARK: - Helper Methods

    /// Gets the duration of a media file using ffprobe.
    ///
    /// - Parameter path: Path to the media file.
    /// - Returns: Duration in seconds, or nil if unavailable.
    func getMediaDuration(path: String) async throws -> TimeInterval? {
        // Use ffprobe (usually installed with ffmpeg)
        let ffprobePath = ffmpegPath.deletingLastPathComponent().appendingPathComponent("ffprobe")

        guard FileManager.default.isExecutableFile(atPath: ffprobePath.path) else {
            return nil
        }

        let process = Process()
        process.executableURL = ffprobePath
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            path,
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let duration = TimeInterval(outputString) else {
            return nil
        }

        return duration
    }

    /// Monitors ffmpeg progress output and reports to handler.
    private func monitorProgress(
        errorPipe: Pipe,
        totalDuration: TimeInterval,
        progressHandler: @escaping (Double) -> Void
    ) async {
        let fileHandle = errorPipe.fileHandleForReading

        // Read in chunks and parse time progress
        while true {
            let availableData = fileHandle.availableData
            if availableData.isEmpty {
                break
            }

            if let output = String(data: availableData, encoding: .utf8) {
                // Parse ffmpeg progress: "time=00:01:23.45"
                if let timeMatch = output.range(of: #"time=(\d+):(\d+):(\d+\.?\d*)"#, options: .regularExpression) {
                    let timeString = String(output[timeMatch])
                    if let currentTime = parseFFmpegTime(timeString) {
                        let progress = min(currentTime / totalDuration, 1.0)
                        progressHandler(progress)
                    }
                }
            }

            // Small delay to avoid busy-waiting
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }
    }

    /// Parses ffmpeg time format (HH:MM:SS.ms) to seconds.
    private func parseFFmpegTime(_ timeString: String) -> TimeInterval? {
        // Extract time components from "time=HH:MM:SS.ms"
        let pattern = #"time=(\d+):(\d+):(\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: timeString, range: NSRange(timeString.startIndex..., in: timeString)),
              match.numberOfRanges == 4 else {
            return nil
        }

        let nsString = timeString as NSString
        let hours = Double(nsString.substring(with: match.range(at: 1))) ?? 0
        let minutes = Double(nsString.substring(with: match.range(at: 2))) ?? 0
        let seconds = Double(nsString.substring(with: match.range(at: 3))) ?? 0

        return hours * 3600 + minutes * 60 + seconds
    }
}

// MARK: - Errors

/// Errors that can occur during stream muxing.
enum StreamMuxerError: Error, LocalizedError {
    case ffmpegNotFound
    case inputFileNotFound(String)
    case noInputFiles
    case muxingFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Please install it with: brew install ffmpeg"
        case .inputFileNotFound(let path):
            return "Input file not found: \(path)"
        case .noInputFiles:
            return "No input files provided for concatenation"
        case .muxingFailed(let message):
            return "Muxing failed: \(message)"
        }
    }
}
