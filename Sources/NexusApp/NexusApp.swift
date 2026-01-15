import SwiftUI
import SwiftData
import AppKit

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
        QueueManager.shared.setModelContainer(sharedModelContainer)
        QueueManager.shared.startProcessing()
        BrowserExtensionListener.shared.startListening()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
