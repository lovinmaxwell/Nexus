import Foundation

/// A NetworkHandler that uses /usr/bin/curl as a subprocess.
/// This matches `URLSessionHandler` behavior but bypasses TLS fingerprinting issues.
class CurlNetworkHandler: NetworkHandler {

    // Wrapper to handle Swift 6 concurrency strictness for Process/Pipe
    private final class CurlContext: @unchecked Sendable {
        let process: Process
        let pipe: Pipe
        let errorPipe: Pipe?

        init(process: Process, pipe: Pipe, errorPipe: Pipe? = nil) {
            self.process = process
            self.pipe = pipe
            self.errorPipe = errorPipe
        }
    }

    func headRequest(url: URL) async throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        // Many servers (including Hetzner) don't support HEAD requests,
        // so use GET with Range: bytes=0-0 to get metadata efficiently.
        // We use -L to follow redirects, and parse the final response.
        let args = [
            "-s", "-D", "-",  // Silent mode, dump headers to stdout
            "--connect-timeout", "15",
            "--max-time", "30",
            "-L",  // Follow redirects
            "-H", "Range: bytes=0-0",
            "-H",
            "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "-H", "Accept: */*",
            "-H", "Accept-Language: en-US,en;q=0.9",
            "-H", "Accept-Encoding: identity",  // Avoid compression for metadata
            "-H", "Referer: \(url.absoluteString)",
            "-o", "/dev/null",  // Discard the body
            url.absoluteString,
        ]

        let output = try await runCurl(args)
        return parseHeaders(output)
    }

    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<
        Data, Error
    > {
        // Build the Range header
        var rangeHeader: String?
        if end >= Int64.max - 1000 {
            if start > 0 {
                rangeHeader = "bytes=\(start)-"
            }
            // If start is 0 and unknown size, no Range header
        } else {
            rangeHeader = "bytes=\(start)-\(end)"
        }

        var args = [
            "-N",  // No buffer (essential for real-time progress)
            "-s",  // Silent mode
            "--connect-timeout", "15",  // Connection timeout
            "--max-time", "0",  // No overall timeout for large downloads
            "--speed-time", "30",  // Abort if slower than speed-limit for 30s
            "--speed-limit", "1",  // 1 byte/sec
            "-L",  // Follow redirects
            "-H",
            "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "-H", "Accept: */*",
            "-H", "Accept-Encoding: identity",  // Match URLSession behavior
            "-H", "Referer: \(url.absoluteString)",
        ]

        if let rangeHeader = rangeHeader {
            args += ["-H", "Range: \(rangeHeader)"]
        }

        args.append(url.absoluteString)

        // Create context before starting stream
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let context = CurlContext(process: process, pipe: pipe)

        return AsyncThrowingStream { continuation in
            Task.detached {
                let process = context.process
                let pipe = context.pipe

                do {
                    try process.run()

                    let fileHandle = pipe.fileHandleForReading

                    // Read data as it becomes available
                    while true {
                        let data = fileHandle.availableData
                        if data.isEmpty {
                            break  // EOF
                        }

                        // Check if the stream is terminated by the consumer
                        let result = continuation.yield(data)
                        if case .terminated = result {
                            process.terminate()
                            return
                        }
                    }

                    // Flush any remaining data
                    let remaining = fileHandle.readDataToEndOfFile()
                    if !remaining.isEmpty {
                        let result = continuation.yield(remaining)
                        if case .terminated = result {
                            process.terminate()
                            return
                        }
                    }

                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        // curl exit code 18 = partial transfer, 56 = recv failure
                        if process.terminationStatus == 18 || process.terminationStatus == 56 {
                            continuation.finish(throwing: NetworkError.connectionFailed)
                        } else {
                            // Treating other errors as connection failed for retry logic
                            continuation.finish(throwing: NetworkError.connectionFailed)
                        }
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func runCurl(_ arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                    process.arguments = arguments

                    let pipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = errorPipe

                    // Note: We don't need CurlContext here as the block captures process/pipe directly
                    // and waits for exit, keeping them alive.

                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    // Ignore exit code for HEAD/metadata requests if we got headers but curl complained about something else
                    // (e.g. sometimes curl returns non-zero for HEAD even if headers are printed)
                    if process.terminationStatus != 0 && output.isEmpty {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                        print(
                            "CurlNetworkHandler: curl failed (exit \(process.terminationStatus)): \(errorOutput)"
                        )
                        continuation.resume(throwing: NetworkError.connectionFailed)
                        return
                    }

                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func parseHeaders(_ rawOutput: String) -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        // Split by newlines to handle both \n and \r\n, and filter out empty lines
        let lines = rawOutput.components(separatedBy: .newlines)

        var contentLength: Int64 = 0
        var acceptsRanges = false  // Default to false until we see evidence
        var lastModified: Date? = nil
        var eTag: String? = nil

        for line in lines {
            let lower = line.trimmingCharacters(in: .whitespaces).lowercased()

            // Validate start of new response (e.g. redirect)
            if lower.hasPrefix("http/") {
                // If we see a new HTTP status line, it means we are parsing a new response (e.g. after a redirect).
                // Reset state to ensure we capture the FINAL response headers.
                contentLength = 0
                acceptsRanges = false
                lastModified = nil
                eTag = nil
                continue
            }

            // Parse Content-Range: bytes 0-0/1073741824
            if lower.hasPrefix("content-range:") {
                let value = String(line.dropFirst("content-range:".count)).trimmingCharacters(
                    in: .whitespaces)
                if let slashIndex = value.lastIndex(of: "/") {
                    let totalPart = String(value[value.index(after: slashIndex)...])
                    if totalPart != "*", let total = Int64(totalPart) {
                        contentLength = total
                    }
                }
                acceptsRanges = true  // If server returns Content-Range, it supports ranges
            }
            // Parse Content-Length (only if Content-Range didn't give us the total)
            else if lower.hasPrefix("content-length:") && contentLength == 0 {
                let value = String(line.dropFirst("content-length:".count)).trimmingCharacters(
                    in: .whitespaces)
                if let length = Int64(value) {
                    contentLength = length
                }
            }
            // Parse Accept-Ranges
            else if lower.hasPrefix("accept-ranges:") {
                let value = String(line.dropFirst("accept-ranges:".count)).trimmingCharacters(
                    in: .whitespaces)
                // "bytes" means ranges supported. "none" means no.
                if value.lowercased() == "bytes" {
                    acceptsRanges = true
                }
            }
            // Parse Last-Modified
            else if lower.hasPrefix("last-modified:") {
                let value = String(line.dropFirst("last-modified:".count)).trimmingCharacters(
                    in: .whitespaces)
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                lastModified = formatter.date(from: value)
            }
            // Parse ETag
            else if lower.hasPrefix("etag:") {
                eTag = String(line.dropFirst("etag:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        print(
            "CurlNetworkHandler: Content-Length: \(contentLength), Accept-Ranges: \(acceptsRanges), ETag: \(eTag ?? "nil")"
        )
        return (contentLength, acceptsRanges, lastModified, eTag)
    }
}
