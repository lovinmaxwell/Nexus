import Foundation

/// Delegate to capture redirect chains and extract final URLs
class RedirectCapturingDelegate: NSObject, URLSessionTaskDelegate {
    var redirectChain: [URL] = []
    var finalURL: URL?
    private let followRedirects: Bool
    
    init(followRedirects: Bool = false) {
        self.followRedirects = followRedirects
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Capture the redirect URL from the Location header
        if let locationHeader = response.value(forHTTPHeaderField: "Location"),
           let originalURL = task.originalRequest?.url,
           let redirectURL = URL(string: locationHeader, relativeTo: originalURL)?.absoluteURL {
            redirectChain.append(redirectURL)
            finalURL = redirectURL
            print("URLSessionHandler: Redirect detected -> \(redirectURL)")
        }
        
        if followRedirects {
            // Follow the redirect with the new request
            completionHandler(request)
        } else {
            // Stop the redirect chain - return nil to prevent automatic following
            completionHandler(nil)
        }
    }
}

class URLSessionHandler: NetworkHandler {
    private let session: URLSession
    private let noRedirectSession: URLSession
    private let redirectDelegate: RedirectCapturingDelegate
    
    /// Stores the resolved final URL after redirect resolution
    private var resolvedURL: URL?
    /// Stores the original URL for Referer header
    private var originalURL: URL?

    init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
        
        // Create a session that captures but doesn't automatically follow redirects
        self.redirectDelegate = RedirectCapturingDelegate(followRedirects: false)
        self.noRedirectSession = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    func headRequest(url: URL) async throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    ) {
        // Store original URL for Referer header
        self.originalURL = url
        
        // STEP 1: Resolve redirects first to get the actual download URL
        // This is critical for sites like testfile.org that return 302 redirects
        let resolvedResult = try await resolveRedirects(for: url)
        let targetURL = resolvedResult.finalURL
        self.resolvedURL = targetURL
        
        if targetURL != url {
            print("URLSessionHandler: Using resolved URL for download: \(targetURL)")
        }
        
        // STEP 2: Try HEAD request on the resolved URL
        var request = URLRequest(url: targetURL)
        request.httpMethod = "HEAD"
        addBrowserHeaders(to: &request, referer: url)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed
        }

        // Handle additional redirects (3xx status codes) - shouldn't happen after resolveRedirects
        if (300...399).contains(httpResponse.statusCode) {
            if let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location, relativeTo: targetURL) {
                print("URLSessionHandler: Additional redirect detected to \(redirectURL)")
                self.resolvedURL = redirectURL.absoluteURL
                return try await headRequest(url: redirectURL)
            } else {
                throw NetworkError.serverError(httpResponse.statusCode)
            }
        }

        // If HEAD request is forbidden (403) or not allowed (405), fall back to GET
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 405 {
            print("URLSessionHandler: HEAD request not allowed (status \(httpResponse.statusCode)), using GET fallback")
            do {
                return try await getMetadataViaGET(url: targetURL)
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
            contentLength = try await getContentLengthViaGET(url: targetURL)
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
        // Use resolved URL if available, otherwise use the provided URL
        let targetURL = resolvedURL ?? url
        let refererURL = originalURL ?? url
        
        // First try without Range header - some servers block Range requests
        var request = URLRequest(url: targetURL)
        addBrowserHeaders(to: &request, referer: refererURL)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed
        }
        
        // Handle redirects
        if (300...399).contains(httpResponse.statusCode) {
            if let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location, relativeTo: targetURL)?.absoluteURL {
                print("URLSessionHandler: Following redirect in GET fallback to \(redirectURL)")
                self.resolvedURL = redirectURL
                return try await getMetadataViaGET(url: redirectURL)
            } else {
                throw NetworkError.serverError(httpResponse.statusCode)
            }
        }
        
        // If still 403, try with Range header
        if httpResponse.statusCode == 403 {
            print("URLSessionHandler: GET without Range also 403, trying with Range header...")
            var rangeRequest = URLRequest(url: targetURL)
            rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            addBrowserHeaders(to: &rangeRequest, referer: refererURL)
            
            let (_, rangeResponse) = try await session.data(for: rangeRequest)
            guard let rangeHttpResponse = rangeResponse as? HTTPURLResponse else {
                throw NetworkError.connectionFailed
            }
            
            if (200...299).contains(rangeHttpResponse.statusCode) || rangeHttpResponse.statusCode == 206 {
                // Use the range response
                return try parseMetadataFromResponse(rangeHttpResponse, url: targetURL)
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("URLSessionHandler: GET fallback failed with status \(httpResponse.statusCode)")
            // If we can't get metadata, allow download with unknown size
            print("URLSessionHandler: Proceeding with unknown file size - download will determine size during transfer")
            return (0, false, nil, nil)  // Unknown size, no range support detected
        }
        
        return try parseMetadataFromResponse(httpResponse, url: targetURL)
    }
    
    private func addBrowserHeaders(to request: inout URLRequest, referer: URL? = nil) {
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding") // Avoid compressed response if possible, though URLSession handles gzip automatically
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        
        // Add Referer header if provided - critical for sites that check origin
        if let referer = referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
    }
    
    /// Resolves all redirects and returns the final URL along with metadata
    /// This is critical for sites like testfile.org that use 302 redirects to CDN URLs
    func resolveRedirects(for url: URL, maxRedirects: Int = 10) async throws -> (
        finalURL: URL, 
        response: HTTPURLResponse?
    ) {
        var currentURL = url
        var redirectCount = 0
        var lastResponse: HTTPURLResponse?
        
        print("URLSessionHandler: Resolving redirects for \(url)")
        
        while redirectCount < maxRedirects {
            // Create a new delegate for each request to capture the redirect
            let delegate = RedirectCapturingDelegate(followRedirects: false)
            let tempSession = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
            
            defer { tempSession.finishTasksAndInvalidate() }
            
            var request = URLRequest(url: currentURL)
            request.httpMethod = "GET"
            addBrowserHeaders(to: &request, referer: originalURL ?? url)
            // Only request first byte to avoid downloading entire file
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            
            let (_, response) = try await tempSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.connectionFailed
            }
            
            lastResponse = httpResponse
            
            // Check if this is a redirect response
            if (300...399).contains(httpResponse.statusCode) {
                // Get the redirect URL from the delegate or from Location header
                if let redirectURL = delegate.finalURL {
                    print("URLSessionHandler: Following redirect #\(redirectCount + 1) to \(redirectURL)")
                    currentURL = redirectURL
                    redirectCount += 1
                    continue
                } else if let location = httpResponse.value(forHTTPHeaderField: "Location"),
                          let redirectURL = URL(string: location, relativeTo: currentURL)?.absoluteURL {
                    print("URLSessionHandler: Following redirect #\(redirectCount + 1) to \(redirectURL) (from header)")
                    currentURL = redirectURL
                    redirectCount += 1
                    continue
                } else {
                    // Redirect without location - treat as final
                    break
                }
            }
            
            // Not a redirect - this is the final URL
            break
        }
        
        if redirectCount >= maxRedirects {
            print("URLSessionHandler: Warning - max redirects reached")
        }
        
        if currentURL != url {
            print("URLSessionHandler: Resolved final URL: \(currentURL)")
        }
        
        return (currentURL, lastResponse)
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
        let targetURL = resolvedURL ?? url
        let refererURL = originalURL ?? url
        
        var request = URLRequest(url: targetURL)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        addBrowserHeaders(to: &request, referer: refererURL)
        
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
        // If we don't have a resolved URL yet, resolve redirects now
        if resolvedURL == nil {
            print("URLSessionHandler: No resolved URL cached, resolving redirects for download...")
            self.originalURL = url
            let resolved = try await resolveRedirects(for: url)
            self.resolvedURL = resolved.finalURL
        }
        
        // Use resolved URL if available (from previous headRequest), otherwise use provided URL
        let downloadURL = resolvedURL ?? url
        let refererURL = originalURL ?? url
        
        if downloadURL != url {
            print("URLSessionHandler: Downloading from resolved URL: \(downloadURL)")
        }
        
        var request = URLRequest(url: downloadURL)
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
        
        addBrowserHeaders(to: &request, referer: refererURL)
        
        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed
        }
        
        // Handle redirects during download - update resolved URL and retry
        if (300...399).contains(httpResponse.statusCode) {
            if let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location, relativeTo: downloadURL)?.absoluteURL {
                print("URLSessionHandler: Redirect during download to \(redirectURL)")
                self.resolvedURL = redirectURL
                return try await downloadRange(url: url, start: start, end: end)
            }
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
    
    /// Returns the resolved download URL (after redirect resolution)
    func getResolvedURL() -> URL? {
        return resolvedURL
    }
    
    /// Returns the original URL (before redirect resolution)
    func getOriginalURL() -> URL? {
        return originalURL
    }
    
    /// Resets the cached URLs (useful when starting a new download)
    func resetURLCache() {
        resolvedURL = nil
        originalURL = nil
    }
}
