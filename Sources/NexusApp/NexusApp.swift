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
        DownloadManager.shared.setModelContainer(sharedModelContainer)
        // QueueManager context is set inside DownloadManager.setModelContainer, but explicit setting is fine too if we change naming.
        // But better to remove redundant call or fix it.
        // QueueManager.shared.setModelContext(sharedModelContainer.mainContext)
        QueueManager.shared.processAllQueues()
        BrowserExtensionListener.shared.startListening()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
