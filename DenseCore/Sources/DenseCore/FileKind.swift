import Foundation

/// Classifies a dropped file by extension so drop handling can route it to
/// the right compressor (or reject it with a clear message).
public enum FileKind: Equatable {
    case video, image, gif, pdf, unsupported

    public static let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv", "mts", "m2ts"]
    public static let imageExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "webp", "bmp"]
    public static let gifExtensions = ["gif"]
    public static let pdfExtensions = ["pdf"]

    public static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if imageExtensions.contains(ext) { return .image }
        if gifExtensions.contains(ext) { return .gif }
        if pdfExtensions.contains(ext) { return .pdf }
        return .unsupported
    }
}
