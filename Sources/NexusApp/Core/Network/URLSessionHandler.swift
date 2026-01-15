import Foundation

class URLSessionHandler: NetworkHandler {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
    }

    func headRequest(url: URL) async throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        let contentLength = httpResponse.expectedContentLength
        let acceptsRanges = (httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")

        // Parse Last-Modified
        var lastModified: Date? = nil
        if let lastModString = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            lastModified = formatter.date(from: lastModString)
        }

        let eTag = httpResponse.value(forHTTPHeaderField: "ETag")

        return (contentLength, acceptsRanges, lastModified, eTag)
    }

    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<
        Data, Error
    > {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")

        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed
        }

        // Handle specific error codes
        if httpResponse.statusCode == 416 {
            throw NetworkError.rangeNotSatisfiable
        }

        if httpResponse.statusCode == 503 {
            throw NetworkError.serviceUnavailable
        }

        guard httpResponse.statusCode == 206 || httpResponse.statusCode == 200 else {
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        return AsyncThrowingStream { continuation in
            Task {
                var buffer = Data()
                // 64KB Buffer
                let bufferSize = 64 * 1024
                buffer.reserveCapacity(bufferSize)

                do {
                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        if buffer.count >= bufferSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
