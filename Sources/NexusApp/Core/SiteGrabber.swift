import Foundation

/// A tool to recursively grab assets from a website.
actor SiteGrabber {
    static let shared = SiteGrabber()
    
    private init() {}
    
    struct GrabbedAsset: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let type: AssetType
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }
        
        static func == (lhs: GrabbedAsset, rhs: GrabbedAsset) -> Bool {
            lhs.url == rhs.url
        }
    }
    
    enum AssetType {
        case image
        case document
        case audio
        case video
        case other
        
        static func from(url: URL) -> AssetType {
            let ext = url.pathExtension.lowercased()
            let imageExts = ["jpg", "jpeg", "png", "gif", "svg", "webp", "bmp"]
            let docExts = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt"]
            let audioExts = ["mp3", "wav", "flac", "aac", "m4a"]
            let videoExts = ["mp4", "mkv", "avi", "mov", "flv"]
            
            if imageExts.contains(ext) { return .image }
            if docExts.contains(ext) { return .document }
            if audioExts.contains(ext) { return .audio }
            if videoExts.contains(ext) { return .video }
            return .other
        }
    }
    
    /// Grabs URLs from a starting page with specified depth and filters.
    func grab(
        from startURL: URL,
        depth: Int = 1,
        allowedTypes: Set<AssetType> = [.image, .document, .audio, .video],
        domainRestricted: Bool = true
    ) async throws -> Set<GrabbedAsset> {
        var foundAssets = Set<GrabbedAsset>()
        var visitedURLs = Set<URL>()
        var toVisit = [startURL]
        
        let host = startURL.host
        
        for _ in 0...depth {
            var nextToVisit = [URL]()
            
            for url in toVisit {
                guard !visitedURLs.contains(url) else { continue }
                visitedURLs.insert(url)
                
                if domainRestricted && url.host != host {
                    continue
                }
                
                let (assets, links) = try await parsePage(url: url)
                
                for asset in assets {
                    if allowedTypes.contains(asset.type) {
                        foundAssets.insert(asset)
                    }
                }
                
                for link in links {
                    if !visitedURLs.contains(link) {
                        nextToVisit.append(link)
                    }
                }
            }
            
            toVisit = nextToVisit
            if toVisit.isEmpty { break }
        }
        
        return foundAssets
    }
    
    private func parsePage(url: URL) async throws -> (assets: [GrabbedAsset], links: [URL]) {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return ([], [])
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            return ([], [])
        }
        
        var assets = [GrabbedAsset]()
        var links = [URL]()
        
        // Simple regex-based parsing for assets (img src, a href)
        // In a real app, we might use a proper HTML parser like SwiftSoup
        
        let assetPatterns = [
            "src\\s*=\\s*\"([^\"]+)\"",
            "href\\s*=\\s*\"([^\"]+)\""
        ]
        
        for pattern in assetPatterns {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let path = String(html[range])
                    if let assetURL = URL(string: path, relativeTo: url)?.absoluteURL {
                        if isAsset(assetURL) {
                            assets.append(GrabbedAsset(url: assetURL, type: AssetType.from(url: assetURL)))
                        } else if isHTML(assetURL) {
                            links.append(assetURL)
                        }
                    }
                }
            }
        }
        
        return (assets, links)
    }
    
    private func isAsset(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && ext != "html" && ext != "htm" && ext != "php" && ext != "asp"
    }
    
    private func isHTML(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || ext == "html" || ext == "htm" || ext == "php" || ext == "asp"
    }
}
