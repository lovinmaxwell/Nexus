import SwiftData
import SwiftUI

/// View for Site Grabber functionality - batch downloading assets from websites.
struct SiteGrabberView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var startURL: String = ""
    @State private var depth: Int = 1
    @State private var domainRestricted: Bool = true
    @State private var selectedAssetTypes: Set<SiteGrabber.AssetType> = [
        .image, .document, .audio, .video,
    ]
    @State private var isGrabbing: Bool = false
    @State private var grabbedAssets: [SiteGrabber.GrabbedAsset] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Site Grabber")
                    .appTitleStyle()

                GlassCard(cornerRadius: 12, padding: 16) {
                    VStack(spacing: 16) {
                        TextField("Starting URL", text: $startURL)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Text("Depth:")
                                .appBodyStyle()
                                .frame(width: 80, alignment: .trailing)
                            Stepper(value: $depth, in: 1...5) {
                                Text("\(depth)")
                                    .appBodyStyle()
                                    .frame(width: 40)
                            }
                            Spacer()
                        }

                        Toggle("Restrict to same domain", isOn: $domainRestricted)
                            .toggleStyle(.switch)
                    }
                }

                GlassCard(cornerRadius: 12, padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Asset Types:")
                            .appHeadlineStyle()

                        ForEach(
                            [SiteGrabber.AssetType.image, .document, .audio, .video], id: \.self
                        ) { type in
                            Toggle(
                                typeName(type),
                                isOn: Binding(
                                    get: { selectedAssetTypes.contains(type) },
                                    set: { isOn in
                                        if isOn {
                                            selectedAssetTypes.insert(type)
                                        } else {
                                            selectedAssetTypes.remove(type)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                if isGrabbing {
                    VStack {
                        ProgressView()
                            .tint(AppColors.accent)
                        Text("Grabbing assets...")
                            .appBodyStyle()
                        Text("Found \(grabbedAssets.count) assets")
                            .appCaptionStyle()
                    }
                }

                if !grabbedAssets.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(grabbedAssets) { asset in
                                GlassCard(cornerRadius: 8, padding: 8) {
                                    HStack {
                                        Image(systemName: iconForType(asset.type))
                                            .foregroundStyle(colorForType(asset.type))
                                        Text(asset.url.lastPathComponent)
                                            .appCaptionStyle()
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }

                if let error = errorMessage {
                    Text(error)
                        .appCaptionStyle()
                        .foregroundStyle(AppColors.error)
                }

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                    .buttonStyle(.bordered)

                    Spacer()

                    if !grabbedAssets.isEmpty {
                        Button("Download All (\(grabbedAssets.count))") {
                            downloadAllAssets()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accent)
                    }

                    Button("Grab") {
                        grabAssets()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    .disabled(startURL.isEmpty || isGrabbing)
                    .keyboardShortcut(.return)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 700)
    }

    private func grabAssets() {
        guard let url = URL(string: startURL) else {
            errorMessage = "Invalid URL"
            return
        }

        isGrabbing = true
        errorMessage = nil
        grabbedAssets = []

        Task {
            do {
                let assets = try await SiteGrabber.shared.grab(
                    from: url,
                    depth: depth,
                    allowedTypes: selectedAssetTypes,
                    domainRestricted: domainRestricted
                )

                await MainActor.run {
                    grabbedAssets = Array(assets)
                    isGrabbing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to grab assets: \(error.localizedDescription)"
                    isGrabbing = false
                }
            }
        }
    }

    private func downloadAllAssets() {
        let downloadsPath = SecurityScopedBookmark.getDefaultDownloadDirectoryPath()

        Task {
            for asset in grabbedAssets {
                _ = await DownloadManager.shared.addDownload(
                    url: asset.url,
                    destinationPath: downloadsPath
                )
            }

            await MainActor.run {
                dismiss()
            }
        }
    }

    private func typeName(_ type: SiteGrabber.AssetType) -> String {
        switch type {
        case .image: return "Images"
        case .document: return "Documents"
        case .audio: return "Audio"
        case .video: return "Video"
        case .other: return "Other"
        }
    }

    private func iconForType(_ type: SiteGrabber.AssetType) -> String {
        switch type {
        case .image: return "photo"
        case .document: return "doc"
        case .audio: return "music.note"
        case .video: return "film"
        case .other: return "file"
        }
    }

    private func colorForType(_ type: SiteGrabber.AssetType) -> Color {
        switch type {
        case .image: return .blue
        case .document: return .orange
        case .audio: return .purple
        case .video: return .red
        case .other: return .gray
        }
    }
}
