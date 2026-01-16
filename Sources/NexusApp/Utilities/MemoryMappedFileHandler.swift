import Foundation
import Darwin

/// Memory-mapped file handler for efficient large file operations.
///
/// Uses mmap to map file regions into memory, reducing RAM usage for large files
/// by only loading the necessary portions into memory as needed.
actor MemoryMappedFileHandler {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    private var mappedRegions: [Int64: UnsafeMutableRawPointer] = [:]
    private let regionSize: Int64 = 64 * 1024 * 1024 // 64MB regions
    private let threshold: Int64 = 100 * 1024 * 1024 // Use mmap for files > 100MB
    
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
    
    /// Writes data at the specified offset, using memory mapping for large files.
    func write(data: Data, at offset: Int64) throws {
        guard let handle = fileHandle else { return }
        
        // For small files or small writes, use regular FileHandle
        if offset < threshold && data.count < Int(regionSize) {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
            return
        }
        
        // For large files, use memory mapping
        try writeWithMemoryMapping(data: data, at: offset)
    }
    
    /// Writes data using memory mapping for efficient large file operations.
    private func writeWithMemoryMapping(data: Data, at offset: Int64) throws {
        guard fileHandle != nil else { return }
        
        let dataSize = Int64(data.count)
        let startRegion = offset / regionSize
        let endRegion = (offset + dataSize - 1) / regionSize
        
        // Write data in chunks aligned to regions
        var currentOffset = offset
        var dataIndex = 0
        
        for region in startRegion...endRegion {
            let regionStart = region * regionSize
            let regionEnd = min(regionStart + regionSize, offset + dataSize)
            let writeStart = max(offset, regionStart)
            let writeEnd = min(offset + dataSize, regionEnd)
            let writeSize = writeEnd - writeStart
            
            // Get or create mapped region
            let mappedPtr = try getMappedRegion(for: region, regionStart: regionStart)
            
            // Calculate offset within the mapped region
            let regionOffset = Int(writeStart - regionStart)
            let targetPtr = mappedPtr.advanced(by: regionOffset)
            
            // Copy data to mapped memory
            data.withUnsafeBytes { bytes in
                let sourcePtr = bytes.baseAddress!.advanced(by: dataIndex)
                memcpy(targetPtr, sourcePtr, Int(writeSize))
            }
            
            // Sync the mapped region to disk
            msync(mappedPtr, Int(regionSize), MS_SYNC)
            
            currentOffset += writeSize
            dataIndex += Int(writeSize)
        }
    }
    
    /// Gets or creates a memory-mapped region for the specified region index.
    private func getMappedRegion(for regionIndex: Int64, regionStart: Int64) throws -> UnsafeMutableRawPointer {
        if let existing = mappedRegions[regionIndex] {
            return existing
        }
        
        guard let handle = fileHandle else {
            throw NSError(domain: "MemoryMappedFileHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "File handle is nil"])
        }
        
        // Map the region into memory
        let fd = handle.fileDescriptor
        let mappedPtr = mmap(
            nil,
            Int(regionSize),
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            fd,
            regionStart
        )
        
        guard mappedPtr != MAP_FAILED, let ptr = mappedPtr else {
            throw NSError(domain: "MemoryMappedFileHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to map memory region"])
        }
        
        mappedRegions[regionIndex] = ptr
        return ptr
    }
    
    func close() throws {
        // Unmap all regions
        for (_, ptr) in mappedRegions {
            munmap(ptr, Int(regionSize))
        }
        mappedRegions.removeAll()
        
        try fileHandle?.close()
        fileHandle = nil
    }
    
    deinit {
        // Clean up any remaining mapped regions
        for (_, ptr) in mappedRegions {
            munmap(ptr, Int(regionSize))
        }
        try? fileHandle?.close()
    }
}
