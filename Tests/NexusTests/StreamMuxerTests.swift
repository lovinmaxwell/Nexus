import XCTest

@testable import NexusApp

/// Unit tests for the StreamMuxer.
///
/// These tests verify:
/// - ffmpeg availability detection
/// - Muxing configuration
/// - Error handling for missing files
final class StreamMuxerTests: XCTestCase {

    // MARK: - Availability Tests

    func test_isAvailable_checksFFmpegPath() async {
        let muxer = StreamMuxer.shared

        // This will be true if ffmpeg is installed (e.g., via Homebrew)
        // The test just verifies the check runs without error
        let _ = await muxer.isAvailable
    }

    // MARK: - Configuration Tests

    func test_muxingConfig_defaultHasCopyStreams() {
        let config = StreamMuxer.MuxingConfig.default

        XCTAssertEqual(config.outputFormat, "mp4")
        XCTAssertTrue(config.copyStreams)
        XCTAssertNil(config.videoCodec)
        XCTAssertNil(config.audioCodec)
    }

    func test_muxingConfig_h264AACHasCorrectCodecs() {
        let config = StreamMuxer.MuxingConfig.h264AAC

        XCTAssertEqual(config.outputFormat, "mp4")
        XCTAssertFalse(config.copyStreams)
        XCTAssertEqual(config.videoCodec, "libx264")
        XCTAssertEqual(config.audioCodec, "aac")
    }

    // MARK: - Error Handling Tests

    func test_mux_throwsErrorForMissingVideoFile() async {
        let muxer = StreamMuxer.shared

        // Skip if ffmpeg not available
        guard await muxer.isAvailable else { return }

        do {
            _ = try await muxer.mux(
                videoPath: "/nonexistent/video.mp4",
                audioPath: "/nonexistent/audio.m4a",
                outputPath: "/tmp/output.mp4"
            )
            XCTFail("Should have thrown an error")
        } catch let error as StreamMuxerError {
            if case .inputFileNotFound(let path) = error {
                XCTAssertEqual(path, "/nonexistent/video.mp4")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_concatenate_throwsErrorForEmptyInputList() async {
        let muxer = StreamMuxer.shared

        // Skip if ffmpeg not available
        guard await muxer.isAvailable else { return }

        do {
            _ = try await muxer.concatenate(
                inputPaths: [],
                outputPath: "/tmp/output.mp4"
            )
            XCTFail("Should have thrown an error")
        } catch let error as StreamMuxerError {
            if case .noInputFiles = error {
                // Expected error
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Error Description Tests

    func test_streamMuxerError_hasDescriptions() {
        let errors: [StreamMuxerError] = [
            .ffmpegNotFound,
            .inputFileNotFound("/path/to/file.mp4"),
            .noInputFiles,
            .muxingFailed("codec error"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func test_ffmpegNotFoundError_suggestsBrew() {
        let error = StreamMuxerError.ffmpegNotFound
        XCTAssertTrue(error.errorDescription?.contains("brew install ffmpeg") ?? false)
    }

    // MARK: - MuxingResult Tests

    func test_muxingResult_tracksSuccess() {
        let successResult = StreamMuxer.MuxingResult(
            outputPath: "/tmp/output.mp4",
            duration: 2.5,
            success: true,
            errorMessage: nil
        )

        XCTAssertTrue(successResult.success)
        XCTAssertNil(successResult.errorMessage)
        XCTAssertEqual(successResult.outputPath, "/tmp/output.mp4")
        XCTAssertEqual(successResult.duration, 2.5, accuracy: 0.1)
    }

    func test_muxingResult_tracksFailure() {
        let failResult = StreamMuxer.MuxingResult(
            outputPath: "/tmp/output.mp4",
            duration: 0.5,
            success: false,
            errorMessage: "Invalid codec"
        )

        XCTAssertFalse(failResult.success)
        XCTAssertEqual(failResult.errorMessage, "Invalid codec")
    }

    // MARK: - Metadata Tests

    func test_mediaMetadata_emptyByDefault() {
        let metadata = StreamMuxer.MediaMetadata()

        XCTAssertNil(metadata.title)
        XCTAssertNil(metadata.artist)
        XCTAssertNil(metadata.album)
        XCTAssertTrue(metadata.customTags.isEmpty)
    }

    func test_mediaMetadata_parsesYtdlpInfo() {
        let ytdlpInfo: [String: Any] = [
            "title": "Test Video",
            "uploader": "Test Channel",
            "album": "Test Album",
            "upload_date": "20251215",
            "description": "Test description",
            "genre": "Music",
        ]

        let metadata = StreamMuxer.MediaMetadata(from: ytdlpInfo)

        XCTAssertEqual(metadata.title, "Test Video")
        XCTAssertEqual(metadata.artist, "Test Channel")
        XCTAssertEqual(metadata.album, "Test Album")
        XCTAssertEqual(metadata.year, "2025")
        XCTAssertEqual(metadata.description, "Test description")
        XCTAssertEqual(metadata.genre, "Music")
    }

    func test_mediaMetadata_toFFmpegArgs_generatesCorrectArgs() {
        var metadata = StreamMuxer.MediaMetadata()
        metadata.title = "My Title"
        metadata.artist = "My Artist"
        metadata.year = "2025"

        let args = metadata.toFFmpegArgs()

        XCTAssertTrue(args.contains("-metadata"))
        XCTAssertTrue(args.contains("title=My Title"))
        XCTAssertTrue(args.contains("artist=My Artist"))
        XCTAssertTrue(args.contains("year=2025"))
    }

    func test_mediaMetadata_toFFmpegArgs_includesCustomTags() {
        var metadata = StreamMuxer.MediaMetadata()
        metadata.customTags = [
            "custom_tag": "custom_value",
            "another_tag": "another_value",
        ]

        let args = metadata.toFFmpegArgs()

        XCTAssertTrue(args.contains("custom_tag=custom_value"))
        XCTAssertTrue(args.contains("another_tag=another_value"))
    }

    func test_mediaMetadata_toFFmpegArgs_emptyForNoMetadata() {
        let metadata = StreamMuxer.MediaMetadata()
        let args = metadata.toFFmpegArgs()

        XCTAssertTrue(args.isEmpty)
    }

    func test_embedMetadata_throwsErrorForMissingFile() async {
        let muxer = StreamMuxer.shared

        // Skip if ffmpeg not available
        guard await muxer.isAvailable else { return }

        var metadata = StreamMuxer.MediaMetadata()
        metadata.title = "Test"

        do {
            _ = try await muxer.embedMetadata(
                inputPath: "/nonexistent/video.mp4",
                outputPath: "/tmp/output.mp4",
                metadata: metadata
            )
            XCTFail("Should have thrown an error")
        } catch let error as StreamMuxerError {
            if case .inputFileNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_embedThumbnail_throwsErrorForMissingInput() async {
        let muxer = StreamMuxer.shared

        // Skip if ffmpeg not available
        guard await muxer.isAvailable else { return }

        do {
            _ = try await muxer.embedThumbnail(
                inputPath: "/nonexistent/video.mp4",
                thumbnailPath: "/nonexistent/thumb.jpg",
                outputPath: "/tmp/output.mp4"
            )
            XCTFail("Should have thrown an error")
        } catch let error as StreamMuxerError {
            if case .inputFileNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
