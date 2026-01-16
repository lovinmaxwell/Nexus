import SwiftData
import SwiftUI

// MARK: - Speed Limit Presets

/// Unit of speed for custom speed limit input.
enum SpeedUnit: String, CaseIterable, Identifiable {
    case kbps = "KB/s"
    case mbps = "MB/s"

    var id: String { rawValue }

    /// Multiplier to convert the value to bytes per second.
    var multiplier: Int64 {
        switch self {
        case .kbps: return 1024
        case .mbps: return 1024 * 1024
        }
    }
}

/// Predefined speed limit options for quick selection.
enum SpeedLimitPreset: String, CaseIterable, Identifiable {
    case unlimited = "Unlimited"
    case slow = "500 KB/s"
    case medium = "1 MB/s"
    case fast = "5 MB/s"
    case veryFast = "10 MB/s"
    case custom = "Custom..."

    var id: String { rawValue }

    /// Speed limit in bytes per second.
    var bytesPerSecond: Int64 {
        switch self {
        case .unlimited: return 0
        case .slow: return 500 * 1024
        case .medium: return 1024 * 1024
        case .fast: return 5 * 1024 * 1024
        case .veryFast: return 10 * 1024 * 1024
        case .custom: return 0  // Handled separately
        }
    }
}

// MARK: - Download Category

enum DownloadCategory: String, CaseIterable, Identifiable {
    case all = "All Downloads"
    case compressed = "Compressed"
    case documents = "Documents"
    case music = "Music"
    case video = "Video"
    case programs = "Programs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "arrow.down.circle.fill"
        case .compressed: return "doc.zipper"
        case .documents: return "doc.fill"
        case .music: return "music.note"
        case .video: return "film"
        case .programs: return "app.fill"
        }
    }

    var extensions: Set<String> {
        switch self {
        case .all: return []
        case .compressed: return ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "pkg"]
        case .documents:
            return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "odt"]
        case .music: return ["mp3", "wav", "flac", "aac", "m4a", "ogg", "wma", "aiff"]
        case .video: return ["mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "mpeg"]
        case .programs: return ["exe", "msi", "app", "deb", "rpm", "apk", "ipa"]
        }
    }

    func matches(_ task: DownloadTask) -> Bool {
        if self == .all { return true }
        let ext = (task.destinationPath as NSString).pathExtension.lowercased()
        return extensions.contains(ext)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DownloadTask.createdDate, order: .reverse) private var tasks: [DownloadTask]
    @Query(sort: \DownloadQueue.name) private var queues: [DownloadQueue]
    @ObservedObject private var speedLimiter = SpeedLimiter.shared

    @State private var selection: UUID?
    @State private var showAddSheet = false
    @State private var newURLString = ""
    @State private var selectedCategory: DownloadCategory = .all
    @State private var showSpeedLimitPopover = false
    @State private var customSpeedLimit: Double = 1.0
    @State private var customSpeedUnit: SpeedUnit = .mbps
    @State private var showQueueManager = false
    @State private var showSiteGrabber = false

    var filteredTasks: [DownloadTask] {
        tasks.filter { selectedCategory.matches($0) }
    }

    @State private var showClearConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Categories") {
                    ForEach(DownloadCategory.allCases) { category in
                        let count = tasks.filter { category.matches($0) }.count
                        HStack {
                            Label(category.rawValue, systemImage: category.icon)
                            Spacer()
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategory = category
                            selection = nil
                        }
                    }
                }
                
                Section("Queues") {
                    ForEach(queues) { queue in
                        let queueTasks = tasks.filter { $0.queue?.id == queue.id }
                        let activeCount = queueTasks.filter { $0.status == .running }.count
                        let pendingCount = queueTasks.filter { $0.status == .pending }.count
                        
                        HStack {
                            Label(queue.name, systemImage: "list.bullet.rectangle")
                            Spacer()
                            if activeCount > 0 || pendingCount > 0 {
                                HStack(spacing: 4) {
                                    if activeCount > 0 {
                                        Text("\(activeCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                    if pendingCount > 0 {
                                        Text("\(pendingCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Filter by queue
                            selectedCategory = .all
                            selection = nil
                        }
                    }
                    
                    Button {
                        showQueueManager = true
                    } label: {
                        Label("Manage Queues...", systemImage: "plus.circle")
                    }
                }

                Section("Downloads") {
                    ForEach(filteredTasks) { task in
                        DownloadRowView(task: task)
                            .tag(task.id)
                            .contextMenu {
                                // Native context menu
                                if task.status == .running {
                                    Button("Pause") {
                                        Task {
                                            await DownloadManager.shared.pauseDownload(taskID: task.id)
                                        }
                                    }
                                } else if task.status == .paused || task.status == .pending {
                                    Button("Resume") {
                                        Task {
                                            await DownloadManager.shared.resumeDownload(taskID: task.id)
                                        }
                                    }
                                }
                                
                                if task.status == .complete {
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.selectFile(
                                            task.destinationPath, inFileViewerRootedAtPath: "")
                                    }
                                }
                                
                                Divider()
                                
                                Button("Delete", role: .destructive) {
                                    Task {
                                        await DownloadManager.shared.cancelDownload(taskID: task.id)
                                        modelContext.delete(task)
                                    }
                                }
                                .keyboardShortcut(.delete)
                            }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // Standard macOS toolbar items
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Download", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Add New Download (⌘N)")
                    
                    Button {
                        if let selectedID = selection,
                           let task = filteredTasks.first(where: { $0.id == selectedID }) {
                            Task {
                                if task.status == .running {
                                    await DownloadManager.shared.pauseDownload(taskID: task.id)
                                } else if task.status == .paused || task.status == .pending {
                                    await DownloadManager.shared.resumeDownload(taskID: task.id)
                                }
                            }
                        }
                    } label: {
                        Label("Pause/Resume", systemImage: "pause.fill")
                    }
                    .keyboardShortcut("p", modifiers: .command)
                    .help("Pause/Resume Download (⌘P)")
                    
                    Button {
                        deleteTasks(completedOnly: true)
                    } label: {
                        Label("Clear Completed", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                    .help("Clear Completed Downloads (⌘⇧⌫)")
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        // Speed Limit Control
                        Button {
                            showSpeedLimitPopover.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: speedLimiter.isEnabled ? "gauge.with.dots.needle.33percent" : "gauge.with.dots.needle.100percent")
                                if speedLimiter.isEnabled {
                                    Text(speedLimiter.limitDescription)
                                        .font(.caption)
                                }
                            }
                        }
                        .popover(isPresented: $showSpeedLimitPopover) {
                            SpeedLimitPopoverView(
                                customSpeed: $customSpeedLimit,
                                customUnit: $customSpeedUnit
                            )
                        }
                        .help(speedLimiter.isEnabled ? "Speed limit: \(speedLimiter.limitDescription)" : "Speed limit: Unlimited")

                        Menu {
                            Button("Clear Completed") {
                                deleteTasks(completedOnly: true)
                            }

                            Button("Clear All...", role: .destructive) {
                                showClearConfirmation = true
                            }
                        } label: {
                            Label("Manage List", systemImage: "ellipsis.circle")
                        }

                        // Add Download button (also in toolbar)
                        Button(action: { showAddSheet = true }) {
                            Label("Add Download", systemImage: "plus")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                        
                        Button {
                            showSiteGrabber = true
                        } label: {
                            Label("Site Grabber", systemImage: "spider")
                        }
                        .help("Grab assets from a website")
                    }
                }
            }
        } detail: {
            if let selectedID = selection,
                let task = filteredTasks.first(where: { $0.id == selectedID })
            {
                TaskDetailView(task: task)
            } else {
                ContentUnavailableView(
                    "Select a Download", systemImage: "arrow.down.circle",
                    description: Text("Choose a download from the sidebar"))
                    .dropDestination(for: String.self) { items, _ in
                        // Handle dropped URLs
                        for item in items {
                            if let url = URL(string: item) {
                                let downloadsPath = SecurityScopedBookmark.getDefaultDownloadDirectoryPath()
                                addDownload(urlString: item, path: downloadsPath)
                            }
                        }
                        return true
                    }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            // Handle dropped file URLs or web URLs
            let downloadsPath = SecurityScopedBookmark.getDefaultDownloadDirectoryPath()
            for url in urls {
                if url.isFileURL {
                    // If it's a file, extract URLs from it (e.g., .txt file with URLs)
                    if let content = try? String(contentsOf: url),
                       !content.isEmpty {
                        let lines = content.components(separatedBy: .newlines)
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty, URL(string: trimmed) != nil {
                                addDownload(urlString: trimmed, path: downloadsPath)
                            }
                        }
                    }
                } else {
                    // It's a web URL
                    addDownload(urlString: url.absoluteString, path: downloadsPath)
                }
            }
            return true
        }
        .alert("Download Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastErrorMessage)
        }
        .sheet(isPresented: $showAddSheet) {
            AddDownloadSheet(urlString: $newURLString, modelContext: modelContext) { urlString, path, connectionCount, queueID, startPaused in
                addDownload(urlString: urlString, path: path, connectionCount: connectionCount, queueID: queueID, startPaused: startPaused)
            }
        }
        .confirmationDialog(
            "Are you sure you want to clear all downloads?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                deleteTasks(completedOnly: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop all running downloads and remove them from the list.")
        }
        .sheet(isPresented: $showQueueManager) {
            QueueManagerView()
        }
        .sheet(isPresented: $showSiteGrabber) {
            SiteGrabberView()
        }
        .onAppear {
            DownloadManager.shared.setModelContainer(modelContext.container)
            MenuBarManager.shared.setModelContainer(modelContext.container)
            DockManager.shared.setModelContainer(modelContext.container)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectTask"))) { notification in
            if let taskID = notification.object as? UUID {
                selection = taskID
            }
        }
    }

    @State private var showErrorAlert = false
    @State private var lastErrorMessage = ""

    private func addDownload(urlString: String, path: String, connectionCount: Int = 8, queueID: UUID? = nil, startPaused: Bool = false) {
        Task {
            do {
                let extractor = MediaExtractor.shared
                let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // For media URLs, use addMediaDownload
                if extractor.isMediaURL(trimmedURL) {
                    if let taskID = try await DownloadManager.shared.addMediaDownload(
                        urlString: trimmedURL, destinationFolder: path)
                    {
                        // Media URLs auto-start after extraction completes
                        // Update connection count if needed (stored in task metadata)
                    }
                } else {
                    // For regular URLs, use addDownload
                    guard let url = URL(string: trimmedURL) else {
                        lastErrorMessage = "Invalid URL"
                        showErrorAlert = true
                        return
                    }
                    
                    // Temporarily set connection count (will be used when creating TaskCoordinator)
                    DownloadManager.shared.maxConnectionsPerDownload = connectionCount
                    
                    if let taskID = await DownloadManager.shared.addDownload(
                        url: url, destinationPath: path, connectionCount: connectionCount,
                        queueID: queueID, startPaused: startPaused)
                    {
                        // Task will auto-start unless startPaused is true
                    }
                }
            } catch {
                print("Failed to add download: \(error)")
                lastErrorMessage = "Failed to add download: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    private func deleteTasks(completedOnly: Bool) {
        let targets = completedOnly ? tasks.filter { $0.status == .complete } : tasks

        Task {
            for task in targets {
                if !completedOnly {
                    // If clearing all, we must ensure active ones are cancelled
                    await DownloadManager.shared.cancelDownload(taskID: task.id)
                }
                modelContext.delete(task)
            }
            // Clear selection if deleted
            if let sel = selection, targets.contains(where: { $0.id == sel }) {
                selection = nil
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            let tasksToDelete = offsets.map { filteredTasks[$0] }
            Task {
                for task in tasksToDelete {
                    await DownloadManager.shared.cancelDownload(taskID: task.id)
                    modelContext.delete(task)
                }
            }
        }
    }
}

struct DownloadRowView: View {
    @Bindable var task: DownloadTask
    @State private var currentSpeed: Double = 0
    @State private var timeRemaining: TimeInterval? = nil
    
    // Throttled UI updates: 0.5-1.0 second interval to reduce CPU usage
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.effectiveDisplayName)
                .font(.headline)
                .lineLimit(1)

            HStack {
                statusIcon
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if task.status == .running && currentSpeed > 0 {
                    Text(formatSpeed(currentSpeed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                
                if task.status == .running, let remaining = timeRemaining {
                    Text(formatTimeRemaining(remaining))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Resume capability indicator
                if task.status == .paused || task.status == .pending {
                    HStack(spacing: 2) {
                        Image(systemName: task.supportsResume ? "arrow.clockwise.circle.fill" : "xmark.circle.fill")
                            .font(.caption2)
                        Text(task.supportsResume ? "Yes" : "No")
                            .font(.caption2)
                    }
                    .foregroundStyle(task.supportsResume ? .green : .orange)
                }

                if task.totalSize > 0 {
                    Text(formatBytes(task.totalSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if task.status == .running || task.status == .extracting {
                if task.status == .extracting {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(.vertical, 4)
        .onReceive(timer) { _ in
            updateProgress()
        }
        .onAppear {
            updateProgress()
        }
    }
    
    private func updateProgress() {
        guard task.status == .running else {
            currentSpeed = 0
            timeRemaining = nil
            return
        }
        
        Task {
            if let progress = await DownloadManager.shared.getProgress(taskID: task.id) {
                await MainActor.run {
                    currentSpeed = progress.speed
                    if progress.speed > 0 && progress.totalBytes > 0 {
                        let remaining = Double(progress.totalBytes - progress.downloadedBytes) / progress.speed
                        timeRemaining = remaining > 0 ? remaining : 0
                    } else {
                        timeRemaining = nil
                    }
                }
            }
        }
    }

    private var statusIcon: some View {
        Group {
            switch task.status {
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
            case .pending:
                Image(systemName: "clock.fill")
                    .foregroundStyle(.gray)
            case .running:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            case .extracting:
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)
            }
        }
        .font(.caption)
    }

    private var statusText: String {
        switch task.status {
        case .paused: return "Paused"
        case .running: return "Downloading..."
        case .pending: return "Pending"
        case .complete: return "Complete"
        case .error: return task.errorMessage ?? "Error"
        case .extracting: return "Extracting media info..."
        }
    }

    private var progress: Double {
        guard task.totalSize > 0 else { return 0 }
        let downloaded = task.segments.reduce(0) { $0 + ($1.currentOffset - $1.startOffset) }
        return Double(downloaded) / Double(task.totalSize)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%dm %ds", minutes, secs)
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%dh %dm", hours, minutes)
        }
    }
}

struct TaskDetailView: View {
    @Bindable var task: DownloadTask
    @Environment(\.modelContext) var modelContext
    @State private var isInspectorExpanded = false
    @State private var serverHeaders: [String: String] = [:]
    @State private var debugLog: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("File Info") {
                    LabeledContent("URL", value: task.sourceURL.absoluteString)
                    LabeledContent("Destination", value: task.destinationPath)
                    LabeledContent("Size", value: formatBytes(task.totalSize))
                    LabeledContent("Status", value: statusText)
                    if let eTag = task.eTag {
                        LabeledContent("ETag", value: eTag)
                    }
                    if let lastModified = task.lastModified {
                        LabeledContent("Last Modified", value: lastModified.formatted())
                    }
                    LabeledContent("Resume Capable", value: task.supportsResume ? "Yes" : "No")
                }

                GroupBox("Segments (\(task.segments.count))") {
                    SegmentVisualizationView(segments: task.segments, totalSize: task.totalSize)
                        .frame(height: 40)

                    ForEach(task.segments) { segment in
                        SegmentRowView(segment: segment, totalSize: task.totalSize)
                    }
                }
                
                // Collapsible Inspector Panel
                DisclosureGroup("Inspector", isExpanded: $isInspectorExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Detailed Segmentation Map
                        GroupBox("Segmentation Map") {
                            DetailedSegmentationMapView(segments: task.segments, totalSize: task.totalSize)
                                .frame(height: 60)
                        }
                        
                        // Server Headers
                        GroupBox("Server Headers") {
                            if serverHeaders.isEmpty {
                                Text("No headers available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(serverHeaders.keys.sorted()), id: \.self) { key in
                                    HStack {
                                        Text(key)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(serverHeaders[key] ?? "")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        
                        // Connection Status per Segment
                        GroupBox("Connection Status") {
                            ForEach(task.segments) { segment in
                                HStack {
                                    Text("Segment \(segment.id.uuidString.prefix(8))")
                                        .font(.caption.monospaced())
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(segment.isComplete ? .green : (task.status == .running ? .blue : .gray))
                                            .frame(width: 8, height: 8)
                                        Text(segment.isComplete ? "Complete" : (task.status == .running ? "Active" : "Pending"))
                                            .font(.caption2)
                                    }
                                    Spacer()
                                    Text("\(formatBytes(segment.currentOffset - segment.startOffset)) / \(formatBytes(segment.endOffset - segment.startOffset + 1))")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        // Debug Log
                        GroupBox("Debug Log") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(debugLog, id: \.self) { logEntry in
                                        Text(logEntry)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(height: 100)
                        }
                    }
                    .padding(.vertical, 8)
                }

                HStack(spacing: 12) {
                    if task.status == .paused || task.status == .error || task.status == .pending {
                        Button("Start") {
                            Task {
                                await DownloadManager.shared.startDownload(taskID: task.id)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(task.status == .extracting)
                    }

                    if task.status == .running {
                        Button("Pause") {
                            Task {
                                await DownloadManager.shared.pauseDownload(taskID: task.id)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if task.status == .extracting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Extracting media info...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if task.status == .complete {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(
                                task.destinationPath, inFileViewerRootedAtPath: "")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(task.sourceURL.lastPathComponent)
        .onAppear {
            loadServerHeaders()
            loadDebugLog()
        }
        .onChange(of: task.status) { _, _ in
            loadServerHeaders()
        }
    }
    
    private func loadServerHeaders() {
        var headers: [String: String] = [:]
        if let eTag = task.eTag {
            headers["ETag"] = eTag
        }
        if let lastModified = task.lastModified {
            headers["Last-Modified"] = lastModified.formatted()
        }
        if task.totalSize > 0 {
            headers["Content-Length"] = "\(task.totalSize)"
        }
        headers["Resume Capable"] = task.supportsResume ? "Yes" : "No"
        serverHeaders = headers
    }
    
    private func loadDebugLog() {
        var log: [String] = []
        log.append("Task ID: \(task.id)")
        log.append("Status: \(statusText)")
        log.append("Segments: \(task.segments.count)")
        log.append("Downloaded: \(formatBytes(task.downloadedBytes))")
        if task.totalSize > 0 {
            log.append("Progress: \(Int((Double(task.downloadedBytes) / Double(task.totalSize)) * 100))%")
        }
        if let error = task.errorMessage {
            log.append("Error: \(error)")
        }
        debugLog = log
    }

    private var statusText: String {
        switch task.status {
        case .paused: return "Paused"
        case .running: return "Downloading"
        case .pending: return "Pending"
        case .complete: return "Complete"
        case .error: return task.errorMessage ?? "Error"
        case .extracting: return "Extracting media info..."
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SegmentVisualizationView: View {
    let segments: [FileSegment]
    let totalSize: Int64

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                ForEach(segments) { segment in
                    let startRatio =
                        totalSize > 0 ? CGFloat(segment.startOffset) / CGFloat(totalSize) : 0
                    let progressRatio =
                        totalSize > 0
                        ? CGFloat(segment.currentOffset - segment.startOffset) / CGFloat(totalSize)
                        : 0

                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.isComplete ? Color.green : Color.blue)
                        .frame(width: max(2, geometry.size.width * progressRatio))
                        .offset(x: geometry.size.width * startRatio)
                }
            }
        }
    }
}

struct SegmentRowView: View {
    let segment: FileSegment
    let totalSize: Int64

    var body: some View {
        HStack {
            Circle()
                .fill(segment.isComplete ? Color.green : Color.blue)
                .frame(width: 8, height: 8)

            Text("\(formatBytes(segment.startOffset)) - \(formatBytes(segment.endOffset))")
                .font(.caption.monospaced())

            Spacer()

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var progress: Double {
        let total = segment.endOffset - segment.startOffset
        guard total > 0 else { return 1.0 }
        let done = segment.currentOffset - segment.startOffset
        return Double(done) / Double(total)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct AddDownloadSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var urlString: String
    @State private var destinationPath: String = ""
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var connectionCount: Int = 8
    @State private var selectedQueueID: UUID?
    @State private var startPaused: Bool = false
    @Query(sort: \DownloadQueue.name) private var queues: [DownloadQueue]
    let modelContext: ModelContext
    let onAdd: (String, String, Int, UUID?, Bool) -> Void

    private var isMediaURL: Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaHosts = ["youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv"]
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return false
        }
        return mediaHosts.contains { host.contains($0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Download")
                .font(.headline)

            TextField("URL", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .dropDestination(for: String.self) { items, _ in
                    if let firstItem = items.first {
                        urlString = firstItem
                    }
                    return true
                }
                .dropDestination(for: URL.self) { urls, _ in
                    if let firstURL = urls.first, !firstURL.isFileURL {
                        urlString = firstURL.absoluteString
                    }
                    return true
                }

            if isMediaURL {
                Text("YouTube/Media URL detected - will extract video")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Destination Folder", text: $destinationPath)
                    .textFieldStyle(.roundedBorder)

                Button("Choose...") {
                    chooseDestination()
                }
            }
            
            // Connection count selector
            HStack {
                Text("Connections:")
                    .frame(width: 120, alignment: .trailing)
                Stepper(value: $connectionCount, in: 1...32) {
                    Text("\(connectionCount)")
                        .frame(width: 40)
                }
                Spacer()
            }
            
            // Queue assignment dropdown
            HStack {
                Text("Queue:")
                    .frame(width: 120, alignment: .trailing)
                Picker("Queue", selection: $selectedQueueID) {
                    Text("Default").tag(nil as UUID?)
                    ForEach(queues) { queue in
                        Text(queue.name).tag(queue.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            
            // Start paused option
            Toggle("Start paused", isOn: $startPaused)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Add") {
                    onAdd(urlString, destinationPath, connectionCount, selectedQueueID, startPaused)
                    urlString = ""
                    destinationPath = ""
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(urlString.isEmpty || destinationPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            // Use Security-Scoped Bookmark if available, otherwise use Downloads folder
            destinationPath = SecurityScopedBookmark.getDefaultDownloadDirectoryPath()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
            // Save Security-Scoped Bookmark for persistent access
            _ = SecurityScopedBookmark.saveBookmark(for: url)
            _ = url.startAccessingSecurityScopedResource()
        }
    }
}

// MARK: - Speed Limit Popover View

/// A popover view for configuring download speed limits.
///
/// Provides preset speed limit options and a custom speed limit input.
struct SpeedLimitPopoverView: View {
    @ObservedObject private var speedLimiter = SpeedLimiter.shared
    @Binding var customSpeed: Double
    @Binding var customUnit: SpeedUnit
    @State private var showCustomInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speed Limit")
                .font(.headline)

            // Current status
            HStack {
                Circle()
                    .fill(speedLimiter.isEnabled ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(speedLimiter.isEnabled ? "Limited to \(speedLimiter.limitDescription)" : "Unlimited")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Preset options
            ForEach(SpeedLimitPreset.allCases.filter { $0 != .custom }) { preset in
                Button {
                    applyPreset(preset)
                } label: {
                    HStack {
                        Text(preset.rawValue)
                        Spacer()
                        if isPresetSelected(preset) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Custom speed limit
            DisclosureGroup("Custom Speed Limit", isExpanded: $showCustomInput) {
                HStack {
                    TextField("Speed", value: $customSpeed, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Picker("Unit", selection: $customUnit) {
                        ForEach(SpeedUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)

                    Button("Apply") {
                        applyCustomLimit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customSpeed <= 0)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(width: 250)
    }

    /// Checks if a preset matches the current speed limit.
    private func isPresetSelected(_ preset: SpeedLimitPreset) -> Bool {
        if preset == .unlimited {
            return !speedLimiter.isEnabled
        }
        return speedLimiter.isEnabled && speedLimiter.limitBytesPerSecond == preset.bytesPerSecond
    }

    /// Applies a preset speed limit.
    private func applyPreset(_ preset: SpeedLimitPreset) {
        if preset == .unlimited {
            speedLimiter.disableLimit()
        } else {
            speedLimiter.setLimit(bytesPerSecond: preset.bytesPerSecond)
        }
    }

    /// Applies a custom speed limit based on user input.
    private func applyCustomLimit() {
        let bytesPerSecond = Int64(customSpeed) * customUnit.multiplier
        if bytesPerSecond > 0 {
            speedLimiter.setLimit(bytesPerSecond: bytesPerSecond)
        }
    }
}
