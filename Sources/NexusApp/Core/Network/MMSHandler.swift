import Foundation

enum MMSError: Error {
    case invalidURL
    case connectionFailed
    case commandFailed(String)
}

class MMSHandler: NetworkHandler {

    init() {}

    func headRequest(url: URL) async throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        // MMS/RTSP often doesn't give clean HEAD responses via simple HTTP-like curl -I
        // We will try standard curl -I behavior, but fallback to unknown size if it fails.
        // Many MMS streams are live or don't report size.

        // Default to unknown size/no ranges
        return (0, false, nil, nil)
    }

    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<
        Data, Error
    > {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Start download (streaming)
                    // Note: MMS typically ignores ranges or is a stream.
                    // We attempt to just dump the stream.
                    let data = try await self.downloadMMSStream(url: url)
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func downloadMMSStream(url: URL) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

        // -s: Silent
        // -L: Follow redirects
        process.arguments = [
            "-s", "-L",
            url.absoluteString,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw MMSError.connectionFailed
        }

        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}
