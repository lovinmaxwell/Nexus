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
    @ObservedObject private var speedLimiter = SpeedLimiter.shared

    @State private var selection: UUID?
    @State private var showAddSheet = false
    @State private var newURLString = ""
    @State private var selectedCategory: DownloadCategory = .all
    @State private var showSpeedLimitPopover = false
    @State private var customSpeedLimit: Double = 1.0
    @State private var customSpeedUnit: SpeedUnit = .mbps

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

                Section("Downloads") {
                    ForEach(filteredTasks) { task in
                        DownloadRowView(task: task)
                            .tag(task.id)
                    }
                    .onDelete(perform: deleteItems)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            .toolbar {
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

                        Button(action: { showAddSheet = true }) {
                            Label("Add Download", systemImage: "plus")
                        }
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
            }
        }
        .alert("Download Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastErrorMessage)
        }
        .sheet(isPresented: $showAddSheet) {
            AddDownloadSheet(urlString: $newURLString) { urlString, path in
                addDownload(urlString: urlString, path: path)
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
        .onAppear {
            DownloadManager.shared.setModelContainer(modelContext.container)
        }
    }

    @State private var showErrorAlert = false
    @State private var lastErrorMessage = ""

    private func addDownload(urlString: String, path: String) {
        Task {
            do {
                // For media URLs, the task is added immediately and extraction happens in background
                // For regular URLs, we start download right away
                if let taskID = try await DownloadManager.shared.addMediaDownload(
                    urlString: urlString, destinationFolder: path)
                {
                    // Only start immediately for non-media URLs
                    // Media URLs auto-start after extraction completes
                    let extractor = MediaExtractor.shared
                    if !extractor.isMediaURL(urlString) {
                        await DownloadManager.shared.startDownload(taskID: taskID)
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

                Spacer()

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
}

struct TaskDetailView: View {
    @Bindable var task: DownloadTask
    @Environment(\.modelContext) var modelContext

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
                }

                GroupBox("Segments (\(task.segments.count))") {
                    SegmentVisualizationView(segments: task.segments, totalSize: task.totalSize)
                        .frame(height: 40)

                    ForEach(task.segments) { segment in
                        SegmentRowView(segment: segment, totalSize: task.totalSize)
                    }
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
    let onAdd: (String, String) -> Void

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
                    onAdd(urlString, destinationPath)
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
            let downloadsPath =
                FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                ?? "/tmp"
            destinationPath = downloadsPath
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
