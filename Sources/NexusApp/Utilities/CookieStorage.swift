import Foundation

/// Utility for serializing and deserializing HTTP cookies.
///
/// This allows cookies from browser extensions to be stored in DownloadTask
/// and used for authenticated downloads.
enum CookieStorage {
    /// Serializes HTTPCookieStorage cookies for a given URL to Data.
    ///
    /// - Parameters:
    ///   - url: The URL to get cookies for
    ///   - cookieStorage: The cookie storage to read from
    /// - Returns: Serialized cookie data, or nil if no cookies
    static func serializeCookies(for url: URL, from cookieStorage: HTTPCookieStorage = .shared) -> Data? {
        guard let cookies = cookieStorage.cookies(for: url), !cookies.isEmpty else {
            return nil
        }
        
        // Convert cookies to a simple string format for serialization
        // Format: "name1=value1; name2=value2"
        let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return cookieString.data(using: .utf8)
    }
    
    /// Deserializes cookie data and creates HTTPCookie objects.
    ///
    /// - Parameters:
    ///   - data: Serialized cookie data
    ///   - url: The URL to associate cookies with
    /// - Returns: Array of HTTPCookie objects, or empty array if deserialization fails
    static func deserializeCookies(_ data: Data, for url: URL) -> [HTTPCookie] {
        // Try parsing as cookie string format (from browser extensions or our serialization)
        if let cookieString = String(data: data, encoding: .utf8) {
            return parseCookieString(cookieString, for: url)
        }
        return []
    }
    
    /// Parses a cookie string (e.g., "name=value; name2=value2") into HTTPCookie objects.
    ///
    /// - Parameters:
    ///   - cookieString: Cookie string in format "name=value; name2=value2"
    ///   - url: The URL to associate cookies with
    /// - Returns: Array of HTTPCookie objects
    static func parseCookieString(_ cookieString: String, for url: URL) -> [HTTPCookie] {
        var cookies: [HTTPCookie] = []
        let pairs = cookieString.components(separatedBy: ";")
        
        for pair in pairs {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            
            let name = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            
            var properties: [HTTPCookiePropertyKey: Any] = [:]
            properties[.name] = name
            properties[.value] = value
            properties[.domain] = url.host ?? ""
            properties[.path] = url.path.isEmpty ? "/" : url.path
            
            if let cookie = HTTPCookie(properties: properties) {
                cookies.append(cookie)
            }
        }
        
        return cookies
    }
    
    /// Stores cookies from data into HTTPCookieStorage.
    ///
    /// - Parameters:
    ///   - data: Serialized cookie data
    ///   - url: The URL to associate cookies with
    ///   - cookieStorage: The cookie storage to write to
    static func storeCookies(_ data: Data, for url: URL, in cookieStorage: HTTPCookieStorage = .shared) {
        let cookies = deserializeCookies(data, for: url)
        cookieStorage.setCookies(cookies, for: url, mainDocumentURL: url)
    }
}
