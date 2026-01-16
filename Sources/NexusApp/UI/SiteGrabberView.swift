import SwiftData
import SwiftUI

/// View for Site Grabber functionality - batch downloading assets from websites.
struct SiteGrabberView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var startURL: String = ""
    @State private var depth: Int = 1
    @State private var domainRestricted: Bool = true
    @State private var selectedAssetTypes: Set<SiteGrabber.AssetType> = [.image, .document, .audio, .video]
    @State private var isGrabbing: Bool = false
    @State private var grabbedAssets: [SiteGrabber.GrabbedAsset] = []
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Site Grabber")
                .font(.headline)
            
            TextField("Starting URL", text: $startURL)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("Depth:")
                    .frame(width: 120, alignment: .trailing)
                Stepper(value: $depth, in: 1...5) {
                    Text("\(depth)")
                        .frame(width: 40)
                }
                Spacer()
            }
            
            Toggle("Restrict to same domain", isOn: $domainRestricted)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset Types:")
                    .font(.subheadline)
                
                ForEach([SiteGrabber.AssetType.image, .document, .audio, .video], id: \.self) { type in
                    Toggle(typeName(type), isOn: Binding(
                        get: { selectedAssetTypes.contains(type) },
                        set: { isOn in
                            if isOn {
                                selectedAssetTypes.insert(type)
                            } else {
                                selectedAssetTypes.remove(type)
                            }
                        }
                    ))
                }
            }
            
            if isGrabbing {
                ProgressView("Grabbing assets...")
                Text("Found \(grabbedAssets.count) assets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !grabbedAssets.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(grabbedAssets) { asset in
                            HStack {
                                Image(systemName: iconForType(asset.type))
                                    .foregroundStyle(colorForType(asset.type))
                                Text(asset.url.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 200)
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
                
                if !grabbedAssets.isEmpty {
                    Button("Download All (\(grabbedAssets.count))") {
                        downloadAllAssets()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("Grab") {
                    grabAssets()
                }
                .buttonStyle(.borderedProminent)
                .disabled(startURL.isEmpty || isGrabbing)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 500, height: 600)
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
