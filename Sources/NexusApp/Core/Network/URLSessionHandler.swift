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
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed
        }

        // Handle redirects (3xx status codes)
        if (300...399).contains(httpResponse.statusCode) {
            if let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location, relativeTo: url) {
                print("URLSessionHandler: Following redirect to \(redirectURL)")
                // Recursively follow redirect (with limit to prevent infinite loops)
                return try await headRequest(url: redirectURL)
            } else {
                throw NetworkError.serverError(httpResponse.statusCode)
            }
        }

        // If HEAD request is forbidden (403) or not allowed (405), fall back to GET
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 405 {
            print("URLSessionHandler: HEAD request not allowed (status \(httpResponse.statusCode)), using GET fallback")
            do {
                return try await getMetadataViaGET(url: url)
            } catch {
                // If GET fallback also fails, return unknown size but allow download to proceed
                print("URLSessionHandler: GET fallback also failed, proceeding with unknown size")
                return (0, false, nil, nil)
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("URLSessionHandler: HEAD request failed with status \(httpResponse.statusCode)")
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        // Get Content-Length from header (more reliable than expectedContentLength)
        var contentLength: Int64 = httpResponse.expectedContentLength
        if let contentLengthHeader = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let length = Int64(contentLengthHeader) {
            contentLength = length
        }
        
        // If still -1, try a GET request to get the actual size
        if contentLength < 0 {
            print("URLSessionHandler: Content-Length not in HEAD, trying GET request...")
            contentLength = try await getContentLengthViaGET(url: url)
        }

        let acceptsRanges = (httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")

        // Parse Last-Modified
        var lastModified: Date? = nil
        if let lastModString = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            lastModified = formatter.date(from: lastModString)
        }

        let eTag = httpResponse.value(forHTTPHeaderField: "ETag")

        print("URLSessionHandler: Content-Length: \(contentLength), Accept-Ranges: \(acceptsRanges)")
        return (contentLength, acceptsRanges, lastModified, eTag)
    }
    
    /// Fallback: Get metadata via GET request when HEAD is not allowed
    private func getMetadataViaGET(url: URL) async throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        // First try without Range header - some servers block Range requests
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        // Don't set Referer to avoid anti-hotlinking protections (mimic direct navigation)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed
        }
        
        // Handle redirects
        if (300...399).contains(httpResponse.statusCode) {
            if let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location, relativeTo: url) {
                print("URLSessionHandler: Following redirect in GET fallback to \(redirectURL)")
                return try await getMetadataViaGET(url: redirectURL)
            } else {
                throw NetworkError.serverError(httpResponse.statusCode)
            }
        }
        
        // If still 403, try with Range header
        if httpResponse.statusCode == 403 {
            print("URLSessionHandler: GET without Range also 403, trying with Range header...")
            var rangeRequest = URLRequest(url: url)
            rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            rangeRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            // Don't set Referer
            
            let (_, rangeResponse) = try await session.data(for: rangeRequest)
            guard let rangeHttpResponse = rangeResponse as? HTTPURLResponse else {
                throw NetworkError.connectionFailed
            }
            
            if (200...299).contains(rangeHttpResponse.statusCode) || rangeHttpResponse.statusCode == 206 {
                // Use the range response
                return try parseMetadataFromResponse(rangeHttpResponse, url: url)
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("URLSessionHandler: GET fallback failed with status \(httpResponse.statusCode)")
            // If we can't get metadata, allow download with unknown size
            print("URLSessionHandler: Proceeding with unknown file size - download will determine size during transfer")
            return (0, false, nil, nil)  // Unknown size, no range support detected
        }
        
        return try parseMetadataFromResponse(httpResponse, url: url)
    }
    
    /// Helper to parse metadata from HTTP response
    private func parseMetadataFromResponse(_ httpResponse: HTTPURLResponse, url: URL) throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        // Extract content length from Content-Range or Content-Length
        var contentLength: Int64 = 0
        let acceptsRanges = (httpResponse.statusCode == 206) || 
                           (httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        
        if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
            // Format: "bytes 0-0/524288000" or "bytes 0-0/*"
            if let slashIndex = contentRange.lastIndex(of: "/") {
                let totalPart = String(contentRange[contentRange.index(after: slashIndex)...])
                if totalPart != "*", let total = Int64(totalPart) {
                    contentLength = total
                }
            }
        }
        
        // Fallback to Content-Length header
        if contentLength == 0 {
            if let contentLengthHeader = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let length = Int64(contentLengthHeader) {
                contentLength = length
            } else {
                // Last resort: use expectedContentLength
                contentLength = httpResponse.expectedContentLength
            }
        }
        
        // Parse Last-Modified
        var lastModified: Date? = nil
        if let lastModString = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            lastModified = formatter.date(from: lastModString)
        }
        
        let eTag = httpResponse.value(forHTTPHeaderField: "ETag")
        
        print("URLSessionHandler: GET fallback successful - Size: \(contentLength), Ranges: \(acceptsRanges)")
        return (contentLength, acceptsRanges, lastModified, eTag)
    }
    
    /// Fallback: Get content length via GET request with Range header
    private func getContentLengthViaGET(url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        // Don't set Referer
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return 0
        }
        
        // If server supports ranges, Content-Range header will have total size
        if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
            // Format: "bytes 0-0/524288000" or "bytes 0-0/*"
            if let slashIndex = contentRange.lastIndex(of: "/") {
                let totalPart = String(contentRange[contentRange.index(after: slashIndex)...])
                if totalPart != "*", let total = Int64(totalPart) {
                    return total
                }
            }
        }
        
        // Fallback to Content-Length header
        if let contentLengthHeader = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let length = Int64(contentLengthHeader) {
            return length
        }
        
        return 0
    }

    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<
        Data, Error
    > {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // For unknown file size (end is near Int64.max), use open-ended range or no range
        if end >= Int64.max - 1000 {
            if start > 0 {
                // Resuming: use open-ended range "bytes=start-"
                request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
            }
            // If start is 0 and size unknown, don't set Range header - download entire file
        } else {
            request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        }
        
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        // Don't set Referer
        
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
