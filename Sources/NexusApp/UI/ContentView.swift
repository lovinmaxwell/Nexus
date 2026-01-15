import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DownloadTask.createdDate, order: .reverse) private var tasks: [DownloadTask]

    @State private var selection: UUID?
    @State private var showAddSheet = false
    @State private var newURLString = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Downloads") {
                    ForEach(tasks) { task in
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
                    Button(action: { showAddSheet = true }) {
                        Label("Add Download", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let selectedID = selection,
               let task = tasks.first(where: { $0.id == selectedID }) {
                TaskDetailView(task: task)
            } else {
                ContentUnavailableView("Select a Download", systemImage: "arrow.down.circle", description: Text("Choose a download from the sidebar"))
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddDownloadSheet(urlString: $newURLString) { url, path in
                addDownload(url: url, path: path)
            }
        }
        .onAppear {
            DownloadManager.shared.setModelContainer(modelContext.container)
        }
    }

    private func addDownload(url: URL, path: String) {
        let task = DownloadTask(sourceURL: url, destinationPath: path)
        modelContext.insert(task)
        try? modelContext.save()
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(tasks[index])
            }
        }
    }
}

struct DownloadRowView: View {
    @Bindable var task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.sourceURL.lastPathComponent)
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

            if task.status == .running {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
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
            case .running:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }

    private var statusText: String {
        switch task.status {
        case .paused: return "Paused"
        case .running: return "Downloading..."
        case .complete: return "Complete"
        case .error: return "Error"
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
                    if task.status == .paused || task.status == .error {
                        Button("Start") {
                            Task {
                                await DownloadManager.shared.startDownload(taskID: task.id)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if task.status == .running {
                        Button("Pause") {
                            Task {
                                await DownloadManager.shared.pauseDownload(taskID: task.id)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if task.status == .complete {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(task.destinationPath, inFileViewerRootedAtPath: "")
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
        case .complete: return "Complete"
        case .error: return "Error"
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
                    let startRatio = totalSize > 0 ? CGFloat(segment.startOffset) / CGFloat(totalSize) : 0
                    let progressRatio = totalSize > 0 ? CGFloat(segment.currentOffset - segment.startOffset) / CGFloat(totalSize) : 0

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
    let onAdd: (URL, String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Download")
                .font(.headline)

            TextField("URL", text: $urlString)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Destination", text: $destinationPath)
                    .textFieldStyle(.roundedBorder)

                Button("Choose...") {
                    chooseDestination()
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Add") {
                    if let url = URL(string: urlString), !destinationPath.isEmpty {
                        onAdd(url, destinationPath)
                        urlString = ""
                        destinationPath = ""
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(URL(string: urlString) == nil || destinationPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            if let filename = URL(string: urlString)?.lastPathComponent, !filename.isEmpty {
                let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/tmp"
                destinationPath = "\(downloadsPath)/\(filename)"
            }
        }
        .onChange(of: urlString) { _, newValue in
            if let filename = URL(string: newValue)?.lastPathComponent, !filename.isEmpty {
                let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/tmp"
                destinationPath = "\(downloadsPath)/\(filename)"
            }
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        if let filename = URL(string: urlString)?.lastPathComponent {
            panel.nameFieldStringValue = filename
        }
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
        }
    }
}

