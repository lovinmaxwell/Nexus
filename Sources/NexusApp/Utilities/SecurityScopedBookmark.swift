import Foundation
import AppKit

/// Manages Security-Scoped Bookmarks for persistent directory access.
///
/// This allows the app to maintain read/write access to user-selected directories
/// across app launches, which is required for App Sandbox compliance.
enum SecurityScopedBookmark {
    private static let defaultDownloadDirectoryKey = "defaultDownloadDirectoryBookmark"
    
    /// Saves a Security-Scoped Bookmark for the given URL.
    ///
    /// - Parameter url: The directory URL to save access for
    /// - Returns: True if saved successfully, false otherwise
    static func saveBookmark(for url: URL) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: defaultDownloadDirectoryKey)
            return true
        } catch {
            print("SecurityScopedBookmark: Failed to save bookmark - \(error)")
            return false
        }
    }
    
    /// Resolves a Security-Scoped Bookmark to a URL and starts accessing it.
    ///
    /// - Returns: The resolved URL, or nil if resolution fails
    static func resolveBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: defaultDownloadDirectoryKey) else {
            return nil
        }
        
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("SecurityScopedBookmark: Bookmark is stale, re-saving...")
                _ = saveBookmark(for: url)
            }
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("SecurityScopedBookmark: Failed to start accessing security-scoped resource")
                return nil
            }
            
            return url
        } catch {
            print("SecurityScopedBookmark: Failed to resolve bookmark - \(error)")
            return nil
        }
    }
    
    /// Stops accessing the security-scoped resource.
    ///
    /// - Parameter url: The URL to stop accessing
    static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
    
    /// Gets the default download directory, prompting user if not set.
    ///
    /// - Returns: The default download directory URL, or nil if user cancels
    @MainActor
    static func getDefaultDownloadDirectory() -> URL? {
        // Try to resolve existing bookmark
        if let url = resolveBookmark() {
            return url
        }
        
        // Prompt user to select directory
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select default download directory"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Save bookmark for future use
            if saveBookmark(for: url) {
                // Start accessing it
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        
        return nil
    }
    
    /// Gets the default download directory path, using Downloads folder as fallback.
    ///
    /// - Returns: The default download directory path
    @MainActor
    static func getDefaultDownloadDirectoryPath() -> String {
        if let url = resolveBookmark() {
            return url.path
        }
        
        // Fallback to standard Downloads directory
        if let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloadsDir.path
        }
        
        return "/tmp"
    }
}
