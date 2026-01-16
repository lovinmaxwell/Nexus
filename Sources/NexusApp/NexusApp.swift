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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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
