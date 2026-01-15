import Foundation

enum ProtocolType {
    case http
    case https
    case ftp
    case ftps
    case unknown
    
    init(from url: URL) {
        switch url.scheme?.lowercased() {
        case "http": self = .http
        case "https": self = .https
        case "ftp": self = .ftp
        case "ftps": self = .ftps
        default: self = .unknown
        }
    }
}

class NetworkHandlerFactory {
    static func handler(for url: URL, username: String? = nil, password: String? = nil) -> NetworkHandler {
        let protocolType = ProtocolType(from: url)
        
        switch protocolType {
        case .http, .https:
            return URLSessionHandler()
        case .ftp, .ftps:
            return FTPHandler(username: username, password: password)
        case .unknown:
            return URLSessionHandler()
        }
    }
    
    static func supportsProtocol(_ url: URL) -> Bool {
        let protocolType = ProtocolType(from: url)
        return protocolType != .unknown
    }
}
