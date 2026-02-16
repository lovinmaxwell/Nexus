import SwiftUI

struct BrowserExtensionsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.accent)

                    Text("Browser Integration")
                        .appTitleStyle()

                    Text(
                        "Install the Nexus extension to capture downloads directly from your browser."
                    )
                    .appBodyStyle()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        // Chrome
                        GlassCard(cornerRadius: 12, padding: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: "globe")
                                    .font(.title)
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Google Chrome / Brave / Edge")
                                        .appHeadlineStyle()

                                    Text("1. Open chrome://extensions")
                                        .appBodyStyle()
                                    Text("2. Enable 'Developer mode'")
                                        .appBodyStyle()
                                    Text("3. Click 'Load unpacked' and select the 'Chrome' folder")
                                        .appBodyStyle()

                                    Button("Open Extensions Folder") {
                                        openExtensionsFolder(browser: "Chrome")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }

                        // Firefox
                        GlassCard(cornerRadius: 12, padding: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: "flame")
                                    .font(.title)
                                    .foregroundStyle(.orange)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Mozilla Firefox")
                                        .appHeadlineStyle()

                                    Text("1. Open about:debugging")
                                        .appBodyStyle()
                                    Text("2. Click 'This Firefox'")
                                        .appBodyStyle()
                                    Text(
                                        "3. Click 'Load Temporary Add-on' and select manifest.json"
                                    )
                                    .appBodyStyle()

                                    Button("Open Extensions Folder") {
                                        openExtensionsFolder(browser: "Firefox")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }

                        // Safari
                        GlassCard(cornerRadius: 12, padding: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: "safari")
                                    .font(.title)
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Safari")
                                        .appHeadlineStyle()

                                    Text("Safari extension is bundled with the app.")
                                        .appBodyStyle()
                                    Text("1. Open Safari Settings > Extensions")
                                        .appBodyStyle()
                                    Text("2. Enable 'Nexus Download Manager'")
                                        .appBodyStyle()

                                    Button("Open Safari Extensions") {
                                        NSWorkspace.shared.open(
                                            URL(
                                                string:
                                                    "x-apple.systempreferences:com.apple.preferences.extensions"
                                            )!)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }

                        // Native Messaging Host Setup
                        GlassCard(cornerRadius: 12, padding: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Native Messaging Host", systemImage: "terminal")
                                    .appHeadlineStyle()

                                Text("Required for Chrome and Firefox integration.")
                                    .appCaptionStyle()

                                Text(
                                    "Run the installation script to register the Native Messaging Host."
                                )
                                .appBodyStyle()
                                .padding(.bottom, 8)

                                Button("Open Script Location") {
                                    openExtensionsFolder(browser: "")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppColors.accent)
                            }
                        }
                    }
                    .padding()
                }

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
                .padding(.bottom)
            }
        }
        .frame(width: 500, height: 650)
    }

    private func openExtensionsFolder(browser: String) {
        // This path needs to be correct relative to the running app or project
        // For development, we point to the project source
        let projectPath = "/Users/lovinmaxwell/Developer/Nexus/BrowserExtensions"

        let path: String
        if browser.isEmpty {
            path = projectPath
        } else {
            path = "\(projectPath)/\(browser)"
        }

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}
