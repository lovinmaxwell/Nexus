import AppKit
import SwiftData
import SwiftUI

@main
struct NexusApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DownloadTask.self,
            FileSegment.self,
            DownloadQueue.self,
        ])
        
        // Get the default store URL
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nexusDir = appSupport.appendingPathComponent("Nexus")
        let storeURL = nexusDir.appendingPathComponent("default.store")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: nexusDir, withIntermediateDirectories: true)
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If initialization fails, try to delete the corrupted store and recreate
            print("ModelContainer initialization failed: \(error)")
            print("Attempting to recover by resetting database...")
            
            // Try to remove the existing store
            if FileManager.default.fileExists(atPath: storeURL.path) {
                do {
                    try FileManager.default.removeItem(at: storeURL)
                    print("Removed existing database store")
                } catch {
                    print("Failed to remove existing store: \(error)")
                }
            }
            
            // Also try to remove the .sqlite-wal and .sqlite-shm files if they exist
            let walURL = storeURL.appendingPathExtension("wal")
            let shmURL = storeURL.appendingPathExtension("shm")
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
            
            // Try to create a new container
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                // Last resort: use in-memory store
                print("Failed to create persistent store, using in-memory store: \(error)")
                let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [inMemoryConfig])
                } catch {
                    fatalError("Could not create ModelContainer even with in-memory store: \(error)")
                }
            }
        }
    }()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DownloadManager.shared.setModelContainer(sharedModelContainer)
        // QueueManager context is set inside DownloadManager.setModelContainer
        SynchronizationQueueManager.shared.setModelContext(sharedModelContainer.mainContext)
        BackgroundDownloadManager.shared.setModelContainer(sharedModelContainer)
        MenuBarManager.shared.setModelContainer(sharedModelContainer)
        DockManager.shared.setModelContainer(sharedModelContainer)
        QueueManager.shared.processAllQueues()
        BrowserExtensionListener.shared.startListening()
        
        // Start synchronization checks for active synchronization queues
        SynchronizationQueueManager.shared.startSynchronizationChecks()
        
        // Restore background downloads
        BackgroundDownloadManager.shared.restoreBackgroundDownloads()
        
        Task {
            _ = await YtDlpUpdater.shared.performAutoCheckIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
