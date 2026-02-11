import AppKit
import SwiftData
import SwiftUI

/// Manages the menu bar status item (NSStatusItem) for Mini Mode.
///
/// Provides quick access to active downloads, pause/resume all, and clipboard URL addition.
@MainActor
class MenuBarManager: ObservableObject {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var modelContainer: ModelContainer?
    private var updateTimer: Timer?
    @Published var activeDownloadCount: Int = 0
    @Published var totalSpeed: Double = 0.0
    @Published var isPaused: Bool = false
    
    private init() {
        setupStatusItem()
    }
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        startUpdating()
    }
    
    /// Sets up the menu bar status item.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Nexus Download Manager")
        button.image?.isTemplate = true
        button.toolTip = "Nexus Download Manager"
        button.action = #selector(statusItemClicked)
        button.target = self
    }
    
    /// Starts periodic updates of the status item.
    private func startUpdating() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }
        updateStatusItem()
    }
    
    /// Updates the status item with current download information.
    private func updateStatusItem() {
        guard let container = modelContainer else { return }
        guard let button = statusItem?.button else { return }
        
        let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>()
        
        guard let tasks = try? context.fetch(descriptor) else { return }
        
        let activeTasks = tasks.filter { $0.status == .running || $0.status == .connecting }
        activeDownloadCount = activeTasks.count
        
        // Calculate total speed
        Task {
            var totalSpeed: Double = 0.0
            for task in activeTasks {
                if let progress = await DownloadManager.shared.getProgress(taskID: task.id) {
                    totalSpeed += progress.speed
                }
            }
            await MainActor.run {
                self.totalSpeed = totalSpeed
            }
        }
        
        // Update button appearance
        if activeDownloadCount > 0 {
            button.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Nexus Download Manager")
            button.title = formatSpeed(totalSpeed)
        } else {
            button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Nexus Download Manager")
            button.title = ""
        }
        
        button.image?.isTemplate = true
    }
    
    /// Handles status item click - shows menu.
    @objc private func statusItemClicked() {
        showMenu()
    }
    
    /// Shows the status item menu.
    private func showMenu() {
        guard let statusItem = statusItem else { return }
        guard let container = modelContainer else { return }
        
        let menu = NSMenu()
        
        // Active downloads header
        if activeDownloadCount > 0 {
            let headerItem = NSMenuItem(title: "\(activeDownloadCount) active download\(activeDownloadCount == 1 ? "" : "s")", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
            
            if totalSpeed > 0 {
                let speedItem = NSMenuItem(title: "Total Speed: \(formatSpeed(totalSpeed))", action: nil, keyEquivalent: "")
                speedItem.isEnabled = false
                menu.addItem(speedItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // Pause/Resume All
        let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>()
        guard let tasks = try? context.fetch(descriptor) else { return }
        
        let hasRunning = tasks.contains { task in task.status == .running || task.status == .connecting }
        let hasPaused = tasks.contains { task in task.status == .paused }
        
        if hasRunning {
            let pauseItem = NSMenuItem(title: "Pause All", action: #selector(pauseAll), keyEquivalent: "")
            pauseItem.target = self
            menu.addItem(pauseItem)
        }
        
        if hasPaused {
            let resumeItem = NSMenuItem(title: "Resume All", action: #selector(resumeAll), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)
        }
        
        if hasRunning || hasPaused {
            menu.addItem(NSMenuItem.separator())
        }
        
        // Add URL from clipboard
        let clipboardItem = NSMenuItem(title: "Add URL from Clipboard", action: #selector(addFromClipboard), keyEquivalent: "")
        clipboardItem.target = self
        menu.addItem(clipboardItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Recent downloads (last 5)
        let recentTasks = tasks.prefix(5)
        if !recentTasks.isEmpty {
            let recentHeader = NSMenuItem(title: "Recent Downloads", action: nil, keyEquivalent: "")
            recentHeader.isEnabled = false
            menu.addItem(recentHeader)
            
            for task in recentTasks {
                let taskItem = NSMenuItem(title: task.effectiveDisplayName, action: #selector(openTask(_:)), keyEquivalent: "")
                taskItem.target = self
                taskItem.representedObject = task.id
                menu.addItem(taskItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // Show main window
        let showWindowItem = NSMenuItem(title: "Show Nexus", action: #selector(showMainWindow), keyEquivalent: "")
        showWindowItem.target = self
        menu.addItem(showWindowItem)
        
        // Quit
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Nexus", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }
    
    @objc private func pauseAll() {
        Task {
            guard let container = modelContainer else { return }
            let context = container.mainContext
            let runningStatus = TaskStatus.running.rawValue
            let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate<DownloadTask> { task in
                task.status.rawValue == runningStatus
            })
            
            if let tasks = try? context.fetch(descriptor) {
                for task in tasks {
                    await DownloadManager.shared.pauseDownload(taskID: task.id)
                }
            }
        }
    }
    
    @objc private func resumeAll() {
        Task {
            guard let container = modelContainer else { return }
            let context = container.mainContext
            let pausedStatus = TaskStatus.paused.rawValue
            let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate<DownloadTask> { task in
                task.status.rawValue == pausedStatus
            })
            
            if let tasks = try? context.fetch(descriptor) {
                for task in tasks {
                    await DownloadManager.shared.resumeDownload(taskID: task.id)
                }
            }
        }
    }
    
    @objc private func addFromClipboard() {
        guard let clipboardString = NSPasteboard.general.string(forType: .string),
              !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // Check if it's a valid URL
        if let url = URL(string: clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            Task {
                _ = await DownloadManager.shared.addDownload(
                    url: url,
                    destinationPath: downloadsDir.path
                )
            }
        }
    }
    
    @objc private func openTask(_ sender: NSMenuItem) {
        guard let taskID = sender.representedObject as? UUID else { return }
        // Focus main window and select task
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Post notification to select task in main window
        NotificationCenter.default.post(name: NSNotification.Name("SelectTask"), object: taskID)
    }
    
    @objc private func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            if window.isMainWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
    
    deinit {
        updateTimer?.invalidate()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}
