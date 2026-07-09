// App/ThumbnailLoader.swift
import AppKit
import QuickLookThumbnailing

@MainActor
final class ThumbnailLoader: ObservableObject {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSURL, NSImage>()

    func thumbnail(for url: URL, side: CGFloat) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = rep.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
