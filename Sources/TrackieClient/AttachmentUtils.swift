import Foundation
import UniformTypeIdentifiers

/// Pure helpers for attachment handling — no disk I/O. Lives in
/// `TrackieClient` so the CLI and unit tests can share them without
/// pulling in AppKit. All the functions below are deterministic and
/// total; the app-side `AttachmentManager` calls into them.
public enum AttachmentUtils {
    // MARK: - Kind detection

    public static func isImage(_ ext: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"].contains(ext.lowercased())
    }
    public static func isVideo(_ ext: String) -> Bool {
        ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(ext.lowercased())
    }
    public static func isAudio(_ ext: String) -> Bool {
        ["mp3", "wav", "m4a", "aac", "flac", "ogg", "aiff"].contains(ext.lowercased())
    }

    // MARK: - Filename shaping

    /// Convert an arbitrary string into a short filename-safe slug.
    /// Non-alphanumeric characters collapse to `-`, capped at 32 chars,
    /// lower-cased.
    public static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let mapped = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(mapped).prefix(32).lowercased().description
    }

    /// Short FNV-1a hash encoded in base 36. Deterministic; collisions
    /// are acceptable here because dedupe scope is a single item's
    /// attachments folder.
    public static func shortHash(_ data: Data) -> String {
        var h: UInt64 = 1469598103934665603  // FNV offset basis
        for b in data.prefix(64 * 1024) {
            h ^= UInt64(b)
            h &*= 1099511628211            // FNV prime
        }
        return String(h, radix: 36).prefix(10).description
    }

    /// Human-recognizable attachment filename inferred from a UTI.
    public static func suggestedName(for uti: UTType?, fallbackExt: String, now: Date = Date()) -> String {
        let ts = Int(now.timeIntervalSince1970)
        let ext = uti?.preferredFilenameExtension ?? fallbackExt
        let kind: String = {
            guard let uti else { return "file" }
            if uti.conforms(to: .image) { return "image" }
            if uti.conforms(to: .movie) { return "video" }
            if uti.conforms(to: .audio) { return "audio" }
            return "file"
        }()
        return "\(kind)-\(ts).\(ext)"
    }

    // MARK: - Markdown snippet

    /// Build the correct markdown link for an attachment based on its
    /// file extension. Images use `![alt](url)`; video/audio use the
    /// same syntax with a tagged alt-text so the Trackie preview can
    /// swap in an inline player. Unknown kinds render as a plain link.
    public static func markdownSnippet(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let encoded = url.absoluteString
        let ext = url.pathExtension.lowercased()
        if isImage(ext) {
            return "![\(name)](\(encoded))"
        } else if isVideo(ext) {
            return "![video:\(name)](\(encoded))"
        } else if isAudio(ext) {
            return "![audio:\(name)](\(encoded))"
        } else {
            return "[\(url.lastPathComponent)](\(encoded))"
        }
    }
}
