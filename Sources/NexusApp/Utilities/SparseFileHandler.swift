import Foundation

actor SparseFileHandler {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    
    init(path: String) throws {
        self.fileURL = URL(filePath: path)
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil, attributes: nil)
        }
        
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
    }
    
    func setFileSize(_ size: Int64) throws {
        try fileHandle?.truncate(atOffset: UInt64(size))
    }
    
    func write(data: Data, at offset: Int64) throws {
        guard let handle = fileHandle else { return }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)
    }
    
    func close() throws {
        try fileHandle?.close()
    }
    
    deinit {
        // Actors cannot have deinit with async calls easily, but FileHandle closes on dealloc usually.
        // explicitly closing is better pattern.
        try? fileHandle?.close()
    }
}
