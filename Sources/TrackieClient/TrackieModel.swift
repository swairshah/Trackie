import Foundation

/// Status of a tracked item.
public enum TrackieStatus: String, Codable, Sendable {
    case pending
    case done
    case scratched
    case trashed
}

/// A single item in the Trackie queue.
public struct TrackieItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var project: String?
    public var priority: Int
    public var status: TrackieStatus
    public var sourceApp: String?
    public var sessionId: String?
    public var pid: Int32?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        project: String? = nil,
        priority: Int = 0,
        status: TrackieStatus = .pending,
        sourceApp: String? = nil,
        sessionId: String? = nil,
        pid: Int32? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.project = project
        self.priority = priority
        self.status = status
        self.sourceApp = sourceApp
        self.sessionId = sessionId
        self.pid = pid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Newline-delimited JSON over TCP. Each request is a single JSON object terminated by \n.
public struct TrackieRequest: Codable, Sendable {
    public var type: String

    // add / update
    public var title: String?
    public var note: String?
    public var project: String?
    public var priority: Int?

    // identify target for update / remove / done / undone / scratch / move
    public var id: String?
    public var idPrefix: String?   // allow short id matches

    // move
    public var toIndex: Int?
    public var direction: String?  // "up" | "down" | "top" | "bottom"

    // list filter
    public var filter: String?     // "pending" | "done" | "scratched" | "all"
    public var projectFilter: String?

    // identity metadata
    public var sourceApp: String?
    public var sessionId: String?
    public var pid: Int32?

    public init(
        type: String,
        title: String? = nil,
        note: String? = nil,
        project: String? = nil,
        priority: Int? = nil,
        id: String? = nil,
        idPrefix: String? = nil,
        toIndex: Int? = nil,
        direction: String? = nil,
        filter: String? = nil,
        projectFilter: String? = nil,
        sourceApp: String? = nil,
        sessionId: String? = nil,
        pid: Int32? = nil
    ) {
        self.type = type
        self.title = title
        self.note = note
        self.project = project
        self.priority = priority
        self.id = id
        self.idPrefix = idPrefix
        self.toIndex = toIndex
        self.direction = direction
        self.filter = filter
        self.projectFilter = projectFilter
        self.sourceApp = sourceApp
        self.sessionId = sessionId
        self.pid = pid
    }
}

public struct TrackieResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var item: TrackieItem?
    public var items: [TrackieItem]?
    public var count: Int?

    public init(
        ok: Bool,
        error: String? = nil,
        item: TrackieItem? = nil,
        items: [TrackieItem]? = nil,
        count: Int? = nil
    ) {
        self.ok = ok
        self.error = error
        self.item = item
        self.items = items
        self.count = count
    }

    public static func success(item: TrackieItem? = nil, items: [TrackieItem]? = nil, count: Int? = nil) -> TrackieResponse {
        TrackieResponse(ok: true, item: item, items: items, count: count)
    }

    public static func failure(_ message: String) -> TrackieResponse {
        TrackieResponse(ok: false, error: message)
    }
}

public enum TrackieError: Error, LocalizedError {
    case serverNotRunning
    case serverError(String)
    case invalidResponse
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            return "Trackie app is not running. Launch Trackie.app first."
        case .serverError(let message):
            return message
        case .invalidResponse:
            return "Invalid response from Trackie broker."
        case .notFound(let hint):
            return "Item not found: \(hint)"
        }
    }
}

public enum TrackieDefaults {
    public static let brokerHost = "127.0.0.1"
    public static let brokerPort = 27182
}

public extension TrackieItem {
    /// A short, human-friendly id prefix used in CLI output.
    var shortId: String {
        String(id.uuidString.prefix(8))
    }
}
