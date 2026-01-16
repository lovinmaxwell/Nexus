import Foundation

/// Detects HTTP/2 protocol and handles protocol negotiation.
///
/// For HTTP/2, uses a single TCP connection with parallel streams.
/// Falls back to multiple HTTP/1.1 connections if throttled.
enum HTTP2Detector {
    /// Detects if a URL supports HTTP/2 protocol.
    ///
    /// - Parameter url: The URL to check
    /// - Returns: True if HTTP/2 is supported, false otherwise
    static func detectHTTP2(for url: URL) async -> Bool {
        // Perform a HEAD request and check the protocol version
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            // Check if response indicates HTTP/2
            if let httpResponse = response as? HTTPURLResponse {
                // Check for HTTP/2 indicators
                // Note: URLSession abstracts protocol details, so we check headers
                if let altSvc = httpResponse.value(forHTTPHeaderField: "Alt-Svc") {
                    return altSvc.contains("h2") || altSvc.contains("h2=")
                }
                
                // Check for HTTP/2 via ALPN (Application-Layer Protocol Negotiation)
                // URLSession handles this automatically, but we can infer from behavior
                // If server supports HTTP/2, URLSession will use it
            }
            
            return false
        } catch {
            print("HTTP2Detector: Failed to detect protocol - \(error)")
            return false
        }
    }
    
    /// Determines optimal connection strategy based on protocol.
    ///
    /// - Parameters:
    ///   - url: The URL to download from
    ///   - preferredConnections: User's preferred connection count
    /// - Returns: Recommended connection count and protocol
    static func determineConnectionStrategy(
        for url: URL,
        preferredConnections: Int
    ) async -> ConnectionStrategy {
        let supportsHTTP2 = await detectHTTP2(for: url)
        
        if supportsHTTP2 {
            // HTTP/2: Use single connection with parallel streams
            // URLSession handles HTTP/2 multiplexing automatically
            return ConnectionStrategy(
                httpProtocol: .http2,
                recommendedConnections: 1,
                useMultipleConnections: false,
                reason: "HTTP/2 detected - using single connection with multiplexing"
            )
        } else {
            // HTTP/1.1: Use multiple connections for better throughput
            return ConnectionStrategy(
                httpProtocol: .http1_1,
                recommendedConnections: min(preferredConnections, 32),
                useMultipleConnections: true,
                reason: "HTTP/1.1 detected - using multiple connections"
            )
        }
    }
}

/// Connection strategy recommendation.
struct ConnectionStrategy {
    enum HTTPProtocol {
        case http1_1
        case http2
    }
    
    let httpProtocol: HTTPProtocol
    let recommendedConnections: Int
    let useMultipleConnections: Bool
    let reason: String
}
