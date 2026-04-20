import Foundation
import AppKit
import UniformTypeIdentifiers

/// On-disk attachments that live alongside items. Each item gets its own
/// subdirectory so purging an item is a single `rm -rf` of that folder.
///
/// Directory: ~/Library/Application Support/Trackie/attachments/<item-id>/
/// Files are named by short content hash + original extension so
/// identical pastes dedupe.
enum AttachmentManager {
    static var rootDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Trackie", isDirectory: true)
        return appSupport.appendingPathComponent("attachments", isDirectory: true)
    }

    static func directory(for itemId: UUID) -> URL {
        rootDirectory.appendingPathComponent(itemId.uuidString, isDirectory: true)
    }

    /// Persist `data` under the item's attachment folder. Returns the
    /// absolute file URL of the saved attachment.
    @discardableResult
    static func save(data: Data, suggestedName: String, for itemId: UUID) throws -> URL {
        let dir = directory(for: itemId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = (suggestedName as NSString).pathExtension
        let base = suggestedName.isEmpty ? "attachment" : ((suggestedName as NSString).deletingPathExtension)
        let safeBase = sanitize(base)
        let hash = shortHash(data)
        let filename = ext.isEmpty ? "\(safeBase)-\(hash)" : "\(safeBase)-\(hash).\(ext)"
        let url = dir.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    /// Copy an existing file into the item's attachment folder, returning
    /// the destination URL. Existing files with identical content (same
    /// hash) are reused.
    @discardableResult
    static func ingestFile(at source: URL, for itemId: UUID) throws -> URL {
        let data = try Data(contentsOf: source)
        let name = source.lastPathComponent
        return try save(data: data, suggestedName: name, for: itemId)
    }

    /// Wipe the attachment folder for an item. Safe to call even if it
    /// doesn't exist.
    static func removeAll(for itemId: UUID) {
        let dir = directory(for: itemId)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Infer a reasonable filename for a piece of pasteboard data.
    static func suggestedName(for uti: UTType?, fallbackExt: String) -> String {
        let ts = Int(Date().timeIntervalSince1970)
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

    // MARK: - Internals

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }).prefix(32).lowercased().description
    }

    private static func shortHash(_ data: Data) -> String {
        var h: UInt64 = 1469598103934665603  // FNV offset
        for b in data.prefix(64 * 1024) {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        return String(h, radix: 36).prefix(10).description
    }
}

// MARK: - Markdown insertion helpers

extension AttachmentManager {
    /// Build the correct markdown snippet for an attachment URL based on
    /// its file kind. Images stay as standard `![]()`. Video/audio use
    /// the same syntax — the custom image provider in NoteEditor checks
    /// the file extension and renders the right inline player.
    static func markdownSnippet(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        // File URLs with spaces / special chars need percent-encoding.
        let encoded = url.absoluteString
        let ext = url.pathExtension.lowercased()
        if Self.isImage(ext) {
            return "![\(name)](\(encoded))"
        } else if Self.isVideo(ext) {
            return "![video:\(name)](\(encoded))"
        } else if Self.isAudio(ext) {
            return "![audio:\(name)](\(encoded))"
        } else {
            return "[\(url.lastPathComponent)](\(encoded))"
        }
    }

    static func isImage(_ ext: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"].contains(ext)
    }
    static func isVideo(_ ext: String) -> Bool {
        ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(ext)
    }
    static func isAudio(_ ext: String) -> Bool {
        ["mp3", "wav", "m4a", "aac", "flac", "ogg", "aiff"].contains(ext)
    }
}
