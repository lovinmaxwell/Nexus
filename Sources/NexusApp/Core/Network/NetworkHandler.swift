import Foundation

enum NetworkError: Error {
    case invalidURL
    case connectionFailed
    case serverError(Int)
    case invalidRange
    case serviceUnavailable
    case rangeNotSatisfiable
    case fileModified
}

protocol NetworkHandler {
    func headRequest(url: URL) async throws -> (
        contentLength: Int64, acceptsRanges: Bool, lastModified: Date?, eTag: String?
    )
    func downloadRange(url: URL, start: Int64, end: Int64) async throws -> AsyncThrowingStream<
        Data, Error
    >
}
