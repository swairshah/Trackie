import Foundation
import UniformTypeIdentifiers
import TrackieClient

/// On-disk attachments that live alongside items. Each item gets its own
/// subdirectory so purging an item is a single `rm -rf` of that folder.
///
/// Directory layout:
///     ~/Library/Application Support/Trackie/attachments/<item-id>/<name>-<hash>.<ext>
///
/// The pure helpers (slug, hash, snippet, kind detection) live in
/// `TrackieClient.AttachmentUtils` so they can be unit-tested without
/// dragging in AppKit.
enum AttachmentManager {
    static var rootDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Trackie", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    static func directory(for itemId: UUID) -> URL {
        rootDirectory.appendingPathComponent(itemId.uuidString, isDirectory: true)
    }

    /// Persist `data` under the item's attachment folder. Files whose
    /// content hashes to the same value are deduped.
    @discardableResult
    static func save(data: Data, suggestedName: String, for itemId: UUID) throws -> URL {
        let dir = directory(for: itemId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ext = (suggestedName as NSString).pathExtension
        let base = (suggestedName as NSString).deletingPathExtension
        let safeBase = AttachmentUtils.sanitize(base.isEmpty ? "attachment" : base)
        let hash = AttachmentUtils.shortHash(data)
        let filename = ext.isEmpty ? "\(safeBase)-\(hash)" : "\(safeBase)-\(hash).\(ext)"

        let url = dir.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    /// Copy an existing file into the item's attachment folder.
    @discardableResult
    static func ingestFile(at source: URL, for itemId: UUID) throws -> URL {
        let data = try Data(contentsOf: source)
        return try save(data: data, suggestedName: source.lastPathComponent, for: itemId)
    }

    /// Wipe the attachment folder for an item. Safe to call even if
    /// nothing was ever attached.
    static func removeAll(for itemId: UUID) {
        try? FileManager.default.removeItem(at: directory(for: itemId))
    }

    // MARK: - Re-exports from AttachmentUtils
    //
    // The app-side call sites were already using `AttachmentManager.xxx`
    // before the split; these forwarders keep the call sites stable so
    // the refactor is a pure rearrangement.

    static func isImage(_ ext: String) -> Bool { AttachmentUtils.isImage(ext) }
    static func isVideo(_ ext: String) -> Bool { AttachmentUtils.isVideo(ext) }
    static func isAudio(_ ext: String) -> Bool { AttachmentUtils.isAudio(ext) }
    static func markdownSnippet(for url: URL) -> String { AttachmentUtils.markdownSnippet(for: url) }
    static func suggestedName(for uti: UTType?, fallbackExt: String) -> String {
        AttachmentUtils.suggestedName(for: uti, fallbackExt: fallbackExt)
    }
}
