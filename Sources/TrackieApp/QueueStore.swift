import Foundation
import Combine
import TrackieClient

/// Thread-safe persistent store of TrackieItems. Order in `items` reflects queue priority.
@MainActor
final class QueueStore: ObservableObject {
    static let shared = QueueStore()

    @Published private(set) var items: [TrackieItem] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let ioQueue = DispatchQueue(label: "trackie.store.io", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Trackie", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("items.json")

        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return
        }
        do {
            self.items = try decoder.decode([TrackieItem].self, from: data)
        } catch {
            NSLog("Trackie: failed to decode items.json: \(error)")
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = items
        let url = fileURL
        let enc = encoder
        let work = DispatchWorkItem {
            do {
                let data = try enc.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("Trackie: save failed: \(error)")
            }
        }
        saveWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: - Queries

    func item(withIdPrefix prefix: String) -> TrackieItem? {
        let normalized = prefix.lowercased()
        return items.first { $0.id.uuidString.lowercased().hasPrefix(normalized) }
    }

    func item(id: UUID) -> TrackieItem? {
        items.first { $0.id == id }
    }

    var pendingCount: Int { items.filter { $0.status == .pending }.count }

    // MARK: - Mutations

    @discardableResult
    func add(
        title: String,
        note: String? = nil,
        project: String? = nil,
        priority: Int = 0,
        sourceApp: String? = nil,
        sessionId: String? = nil,
        pid: Int32? = nil
    ) -> TrackieItem {
        let item = TrackieItem(
            title: title,
            note: note,
            project: project,
            priority: priority,
            sourceApp: sourceApp,
            sessionId: sessionId,
            pid: pid
        )
        items.append(item)
        scheduleSave()
        return item
    }

    func remove(id: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: idx)
        AttachmentManager.removeAll(for: id)
        scheduleSave()
        return true
    }

    func setStatus(id: UUID, _ status: TrackieStatus) -> TrackieItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        items[idx].status = status
        items[idx].updatedAt = Date()
        scheduleSave()
        return items[idx]
    }

    func update(
        id: UUID,
        title: String? = nil,
        note: String?? = nil,
        project: String?? = nil,
        priority: Int? = nil
    ) -> TrackieItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        if let title { items[idx].title = title }
        if let note { items[idx].note = note }
        if let project { items[idx].project = project }
        if let priority { items[idx].priority = priority }
        items[idx].updatedAt = Date()
        scheduleSave()
        return items[idx]
    }

    func appendNote(id: UUID, text: String) -> TrackieItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items[idx] }
        if let existing = items[idx].note, !existing.isEmpty {
            items[idx].note = existing + "\n\n" + trimmed
        } else {
            items[idx].note = trimmed
        }
        items[idx].updatedAt = Date()
        scheduleSave()
        return items[idx]
    }

    func move(from source: Int, to destination: Int) {
        guard items.indices.contains(source) else { return }
        let clamped = max(0, min(destination, items.count - 1))
        guard clamped != source else { return }
        let item = items.remove(at: source)
        items.insert(item, at: clamped)
        scheduleSave()
    }

    func move(id: UUID, direction: String) -> TrackieItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        let target: Int
        switch direction {
        case "up": target = max(0, idx - 1)
        case "down": target = min(items.count - 1, idx + 1)
        case "top": target = 0
        case "bottom": target = items.count - 1
        default: return items[idx]
        }
        move(from: idx, to: target)
        return items.first(where: { $0.id == id })
    }

    func move(id: UUID, toIndex: Int) -> TrackieItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        move(from: idx, to: toIndex)
        return items.first(where: { $0.id == id })
    }

    /// Remove all scratched/done items; keep pending and trashed.
    func clearCompleted() -> Int {
        let before = items.count
        items.removeAll { $0.status == .done || $0.status == .scratched }
        let removed = before - items.count
        if removed > 0 { scheduleSave() }
        return removed
    }

    /// Hard-delete all items currently in the trash.
    func purgeTrashed() -> Int {
        let trashedIds = items.filter { $0.status == .trashed }.map(\.id)
        items.removeAll { $0.status == .trashed }
        for id in trashedIds { AttachmentManager.removeAll(for: id) }
        if !trashedIds.isEmpty { scheduleSave() }
        return trashedIds.count
    }

    func clearAll() -> Int {
        let removed = items.count
        items.removeAll()
        if removed > 0 { scheduleSave() }
        return removed
    }

    // Reorder via IndexSet (used by SwiftUI .onMove)
    func onMove(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }
}
