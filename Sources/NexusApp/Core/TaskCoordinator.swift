import Foundation
import SwiftData

actor TaskCoordinator {
    let taskID: UUID
    let modelContainer: ModelContainer
    private let networkHandler: NetworkHandler
    private var fileHandler: SparseFileHandler?
    
    // In-memory active state
    private var isRunning = false
    
    init(taskID: UUID, container: ModelContainer, networkHandler: NetworkHandler = URLSessionHandler()) {
        self.taskID = taskID
        self.modelContainer = container
        self.networkHandler = networkHandler
    }
    
    @MainActor
    private func updateTask(_ block: (DownloadTask) -> Void) {
        let context = modelContainer.mainContext
        guard let task = try? context.fetch(FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == taskID })).first else { return }
        block(task)
        try? context.save()
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        
        await updateTask { $0.status = .running }
        
        // Fetch task details (on background context to avoid MainActor requirement inside actor? 
        // access to SwiftData models is not thread-safe, strict concurrency requires care)
        // For simplicity, we fetch fresh context here.
        let stringID = taskID
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.id == stringID })
        let context = ModelContext(modelContainer)
        
        guard let task = try? context.fetch(descriptor).first else {
            print("Task not found")
            return
        }
        
        do {
            // 1. Initialize File
            fileHandler = try SparseFileHandler(path: task.destinationPath)
            
            // 2. Head Request
            let meta = try await networkHandler.headRequest(url: task.sourceURL)
            
            // Update metadata
            task.totalSize = meta.contentLength
            task.eTag = meta.eTag
            task.lastModified = meta.lastModified
            try context.save()
            
            try await fileHandler?.setFileSize(meta.contentLength)
            
            if meta.acceptsRanges {
                print("Server supports ranges. Starting segmentation...")
                let segmentCount = 4
                let segmentSize = meta.contentLength / Int64(segmentCount)
                
                var segmentInfos: [(id: UUID, start: Int64, end: Int64)] = []
                
                for i in 0..<segmentCount {
                    let start = Int64(i) * segmentSize
                    let end = (i == segmentCount - 1) ? meta.contentLength - 1 : (start + segmentSize - 1)
                    let id = UUID()
                    let segment = FileSegment(id: id, startOffset: start, endOffset: end, currentOffset: start)
                    task.segments.append(segment)
                    segmentInfos.append((id, start, end))
                }
                try context.save()
                
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for info in segmentInfos {
                        group.addTask {
                            try await self.downloadSegment(id: info.id, start: info.start, end: info.end, url: task.sourceURL)
                        }
                    }
                    try await group.waitForAll()
                }
                
                task.status = .complete
                print("Download complete!")
            } else {
                print("Server does not support ranges. Fallback to normal download.")
                // Single segment
                 let id = UUID()
                 let segment = FileSegment(id: id, startOffset: 0, endOffset: meta.contentLength - 1, currentOffset: 0)
                 task.segments.append(segment)
                 try context.save()
                 
                 try await downloadSegment(id: id, start: 0, end: meta.contentLength - 1, url: task.sourceURL)
                 task.status = .complete
            }
            try context.save()
            
        } catch {
            print("Download error: \(error)")
            task.status = .error
            try? context.save()
        }
        
        isRunning = false
    }

    private func downloadSegment(id: UUID, start: Int64, end: Int64, url: URL) async throws {
        let stream = try await networkHandler.downloadRange(url: url, start: start, end: end)
        var currentOffset = start
        
        for try await chunk in stream {
            try await fileHandler?.write(data: chunk, at: currentOffset)
            currentOffset += Int64(chunk.count)
            
            // Periodically update DB? Or just keep in memory for now? 
            // For real production we need to batch DB updates to avoid IO thrashing.
        }
    }
}
