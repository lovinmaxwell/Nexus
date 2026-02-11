import AppKit
import SwiftData

/// Manages Dock icon badge and progress overlay.
///
/// Displays active download count and global progress on the Dock icon.
@MainActor
class DockManager: ObservableObject {
    static let shared = DockManager()
    
    private var modelContainer: ModelContainer?
    private var updateTimer: Timer?
    @Published var activeDownloadCount: Int = 0
    @Published var globalProgress: Double = 0.0
    
    private init() {
        startUpdating()
    }
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }
    
    /// Starts periodic updates of the Dock icon.
    private func startUpdating() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDockIcon()
            }
        }
        updateDockIcon()
    }
    
    /// Updates the Dock icon with badge count and progress.
    private func updateDockIcon() {
        guard let container = modelContainer else { return }
        
        let context = container.mainContext
        let descriptor = FetchDescriptor<DownloadTask>()
        
        guard let tasks = try? context.fetch(descriptor) else { return }
        
        let activeTasks = tasks.filter { $0.status == .running || $0.status == .connecting }
        activeDownloadCount = activeTasks.count
        
        // Calculate global progress
        var totalBytes: Int64 = 0
        var downloadedBytes: Int64 = 0
        
        for task in activeTasks {
            totalBytes += task.totalSize
            downloadedBytes += task.downloadedBytes
        }
        
        if totalBytes > 0 {
            globalProgress = Double(downloadedBytes) / Double(totalBytes)
        } else {
            globalProgress = 0.0
        }
        
        // Update Dock badge
        if activeDownloadCount > 0 {
            NSApplication.shared.dockTile.badgeLabel = "\(activeDownloadCount)"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
        
        // Update Dock icon with progress overlay
        updateDockIconWithProgress()
    }
    
    /// Updates the Dock icon with a circular progress overlay.
    private func updateDockIconWithProgress() {
        guard activeDownloadCount > 0 && globalProgress > 0 else {
            // Reset to default icon
            NSApplication.shared.dockTile.contentView = nil
            return
        }
        
        // Create a custom view with progress overlay
        let progressView = DockProgressView(progress: globalProgress)
        NSApplication.shared.dockTile.contentView = progressView
        NSApplication.shared.dockTile.display()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}

/// Custom view for Dock icon with progress overlay.
class DockProgressView: NSView {
    private let progress: Double
    
    init(progress: Double) {
        self.progress = progress
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw app icon
        if let appIcon = NSApplication.shared.applicationIconImage {
            appIcon.draw(in: bounds)
        }
        
        // Draw circular progress overlay
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 50
        let lineWidth: CGFloat = 6
        
        // Background circle
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        NSColor.black.withAlphaComponent(0.3).setFill()
        backgroundPath.fill()
        
        // Progress arc
        let progressPath = NSBezierPath()
        let startAngle: CGFloat = 90  // Start at top
        let endAngle = startAngle - (360 * CGFloat(progress))
        
        progressPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        NSColor.systemBlue.setStroke()
        progressPath.lineWidth = lineWidth
        progressPath.lineCapStyle = .round
        progressPath.stroke()
    }
}

