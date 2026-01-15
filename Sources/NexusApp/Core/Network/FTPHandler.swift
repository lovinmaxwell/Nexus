import Foundation

enum FTPError: Error {
    case invalidURL
    case connectionFailed
    case authenticationFailed
    case fileNotFound
    case rangeNotSupported
    case commandFailed(String)
}

class FTPHandler: NetworkHandler {
    private var username: String?
    private var password: String?
    
    init(username: String? = nil, password: String? = nil) {
        self.username = username
        self.password = password
    }
    
    func headRequest(url: URL) async throws -> (contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?) {
        let size = try await getFileSize(url: url)
        let modDate = try await getModificationDate(url: url)
        return (size, size > 0, modDate, nil)
    }
    
    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await self.downloadFTPRange(url: url, start: start, end: end)
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func getFileSize(url: URL) async throws -> Int64 {
        let curlURL = buildCurlURL(from: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-sI", curlURL]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw FTPError.connectionFailed
        }
        
        for line in output.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let sizeStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                if let size = Int64(sizeStr) {
                    return size
                }
            }
        }
        
        return try await getFileSizeViaSIZE(url: url)
    }
    
    private func getFileSizeViaSIZE(url: URL) async throws -> Int64 {
        guard let host = url.host, let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw FTPError.invalidURL
        }
        
        let port = url.port ?? 21
        var args = ["-s", "--ftp-pasv", "-I", "ftp://\(host):\(port)\(path)"]
        
        if let user = username, let pass = password {
            args.insert(contentsOf: ["-u", "\(user):\(pass)"], at: 0)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            for line in output.components(separatedBy: "\n") {
                if line.lowercased().contains("content-length") {
                    let parts = line.split(separator: ":")
                    if parts.count >= 2, let size = Int64(parts[1].trimmingCharacters(in: .whitespaces)) {
                        return size
                    }
                }
            }
        }
        
        throw FTPError.commandFailed("SIZE")
    }
    
    private func getModificationDate(url: URL) async throws -> Date? {
        let curlURL = buildCurlURL(from: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-sI", curlURL]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        for line in output.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("last-modified:") {
                let dateStr = line.dropFirst("last-modified:".count).trimmingCharacters(in: .whitespaces)
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter.date(from: dateStr)
            }
        }
        
        return nil
    }
    
    private func downloadFTPRange(url: URL, start: Int64, end: Int64) async throws -> Data {
        let curlURL = buildCurlURL(from: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-s",
            "--ftp-pasv",
            "-r", "\(start)-\(end)",
            curlURL
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw FTPError.connectionFailed
        }
        
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
    
    private func buildCurlURL(from url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        
        if let user = username, let pass = password {
            components.user = user
            components.password = pass
        }
        
        return components.url?.absoluteString ?? url.absoluteString
    }
}
