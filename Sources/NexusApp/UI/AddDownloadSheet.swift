import SwiftData
import SwiftUI

struct AddDownloadSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var urlString: String
    @State private var destinationPath: String = ""
    @State private var availableFormats: [MediaExtractor.MediaFormat] = []
    @State private var selectedFormatID: String = "best"
    @State private var isLoadingFormats = false
    @State private var isAdding = false
    @State private var addPhaseMessage: String?
    @State private var formatError: String?
    @State private var errorMessage: String?
    @State private var connectionCount: Int = 8
    @State private var selectedQueueID: UUID?
    @State private var startPaused: Bool = false
    @State private var username = ""
    @State private var password = ""
    @State private var showAuthFields = false

    @Query(sort: \DownloadQueue.name) private var queues: [DownloadQueue]
    let modelContext: ModelContext
    let onAdd: (String, String, Int, UUID?, Bool, String?, String?, String?) async throws -> Void

    private var isMediaURL: Bool {
        MediaExtractor.shared.isMediaURL(urlString)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Download")
                .appHeadlineStyle()

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
                    .appCaptionStyle()
                    .foregroundStyle(AppColors.textSecondary)
            }

            if isMediaURL {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Format:")
                            .appBodyStyle()
                            .frame(width: 120, alignment: .trailing)
                        Picker("Resolution", selection: $selectedFormatID) {
                            Text("Best (auto)").tag("best")
                            ForEach(availableFormats) { format in
                                Text(format.displayName).tag(format.id)
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                    }

                    HStack {
                        Button(availableFormats.isEmpty ? "Load Formats" : "Refresh Formats") {
                            loadFormats()
                        }
                        .disabled(isLoadingFormats)

                        if isLoadingFormats {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Spacer()
                    }

                    if let error = formatError {
                        Text(error)
                            .appCaptionStyle()
                            .foregroundStyle(AppColors.error)
                    } else if availableFormats.isEmpty {
                        Text(
                            "Uses best available format. Load formats to choose a specific resolution."
                        )
                        .appCaptionStyle()
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }
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
                    .appBodyStyle()
                    .frame(width: 120, alignment: .trailing)
                Stepper(value: $connectionCount, in: 1...32) {
                    Text("\(connectionCount)")
                        .appBodyStyle()
                        .frame(width: 40)
                }
                Spacer()
            }

            // Queue assignment dropdown
            HStack {
                Text("Queue:")
                    .appBodyStyle()
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

            // Authentication
            DisclosureGroup("Authentication", isExpanded: $showAuthFields) {
                VStack(spacing: 8) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 4)
            }

            // Start paused option
            Toggle("Start paused", isOn: $startPaused)

            if let error = errorMessage {
                Text(error)
                    .appCaptionStyle()
                    .foregroundStyle(AppColors.error)
            }

            if let phase = addPhaseMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(phase)
                        .appCaptionStyle()
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .disabled(isAdding)

                Spacer()

                Button("Add") {
                    addDownload()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(urlString.isEmpty || destinationPath.isEmpty || isAdding)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            // Use Security-Scoped Bookmark if available, otherwise use Downloads folder
            destinationPath = SecurityScopedBookmark.getDefaultDownloadDirectoryPath()
        }
        .onChange(of: urlString) { _, _ in
            if isMediaURL {
                resetFormatSelection()
            }
        }
    }

    private func addDownload() {
        guard !isAdding else { return }
        isAdding = true
        errorMessage = nil
        addPhaseMessage = isMediaURL ? "Extracting media info..." : "Resolving URL..."

        Task {
            do {
                let formatID = isMediaURL ? selectedFormatID : nil
                let user = username.isEmpty ? nil : username
                let pass = password.isEmpty ? nil : password

                try await onAdd(
                    urlString, destinationPath, connectionCount, selectedQueueID, startPaused,
                    formatID, user, pass)
                await MainActor.run {
                    urlString = ""
                    username = ""
                    password = ""
                    // Keep destination path for convenience
                    addPhaseMessage = nil
                    isAdding = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    addPhaseMessage = nil
                    isAdding = false
                    errorMessage = error.localizedDescription
                }
            }
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

    private func resetFormatSelection() {
        availableFormats = []
        selectedFormatID = "best"
        formatError = nil
        isLoadingFormats = false
    }

    private func loadFormats() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let requestedURL = trimmed
        isLoadingFormats = true
        formatError = nil

        Task {
            do {
                let parsedURL = URL(string: trimmed)
                let cookieFileURL = parsedURL.flatMap {
                    try? NetscapeCookieWriter.writeCookies(for: $0)
                }
                defer { NetscapeCookieWriter.cleanup(cookieFileURL) }

                let formats = try await MediaExtractor.shared.listFormats(
                    from: trimmed,
                    cookiesFileURL: cookieFileURL
                )
                let sortedFormats = formats.sorted { formatSortKey($0) > formatSortKey($1) }

                await MainActor.run {
                    guard urlString.trimmingCharacters(in: .whitespacesAndNewlines) == requestedURL
                    else {
                        isLoadingFormats = false
                        return
                    }
                    availableFormats = sortedFormats
                    if selectedFormatID != "best",
                        !sortedFormats.contains(where: { $0.id == selectedFormatID })
                    {
                        selectedFormatID = "best"
                    }
                    isLoadingFormats = false
                }
            } catch {
                await MainActor.run {
                    formatError = error.localizedDescription
                    availableFormats = []
                    isLoadingFormats = false
                }
            }
        }
    }

    private func formatHeight(_ resolution: String?) -> Int {
        guard let resolution else { return 0 }
        let digits = resolution.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    private func formatSortKey(_ format: MediaExtractor.MediaFormat) -> Int {
        let height = formatHeight(format.resolution)
        let typeBoost = format.isAudioOnly ? -1000 : 0
        return height + typeBoost
    }
}
