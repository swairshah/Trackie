import Foundation
import Network
import TrackieClient

/// TCP server that serves NDJSON Trackie commands on 127.0.0.1.
final class Broker {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "trackie.broker")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let store: QueueStore

    init(port: Int, store: QueueStore) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(domain: "Trackie", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid broker port: \(port)"])
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // We bind the listener on `nwPort` without `requiredLocalEndpoint`.
        // Setting requiredLocalEndpoint caused NWListener to silently refuse
        // to start when the app was launched via Launch Services (only direct
        // binary launches worked). We enforce loopback-only by filtering
        // incoming connections in `handle(connection:)`.
        self.listener = try NWListener(using: params, on: nwPort)
        self.store = store

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("Trackie broker: listening on 127.0.0.1:\(TrackieDefaults.brokerPort)")
            case .failed(let err):
                NSLog("Trackie broker: failed: \(err)")
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        if !Self.isLoopback(endpoint: connection.endpoint) {
            NSLog("Trackie broker: rejecting non-loopback connection from \(connection.endpoint)")
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private static func isLoopback(endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let addr):
                return addr.rawValue.first == 127 || addr == .loopback
            case .ipv6(let addr):
                if addr == .loopback { return true }
                // IPv4 clients hitting a dual-stack v6 listener arrive as
                // IPv4-mapped IPv6 (::ffff:127.0.0.1). Peek at the last 4
                // bytes and accept anything in 127.0.0.0/8.
                let bytes = addr.rawValue
                if bytes.count == 16 {
                    let v4First = bytes[bytes.index(bytes.startIndex, offsetBy: 12)]
                    let mappedPrefix = bytes.prefix(12) == Data([0,0,0,0,0,0,0,0,0,0,0xff,0xff])
                    if mappedPrefix && v4First == 127 { return true }
                }
                return false
            case .name(let name, _):
                return name == "localhost" || name == "127.0.0.1" || name == "::1"
            @unknown default:
                return false
            }
        default:
            return false
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                self.send(.failure("Connection error: \(error.localizedDescription)"), on: connection)
                return
            }

            var newBuffer = buffer
            if let data { newBuffer.append(data) }

            if let nl = newBuffer.firstIndex(of: 0x0A) {
                let line = newBuffer.subdata(in: 0..<nl)
                self.handleLine(line, on: connection)
                return
            }
            if isComplete {
                self.handleLine(newBuffer, on: connection)
                return
            }
            self.receive(on: connection, buffer: newBuffer)
        }
    }

    private func handleLine(_ line: Data, on connection: NWConnection) {
        guard !line.isEmpty else {
            send(.failure("Empty request"), on: connection)
            return
        }
        let request: TrackieRequest
        do {
            request = try decoder.decode(TrackieRequest.self, from: line)
        } catch {
            send(.failure("Invalid JSON: \(error.localizedDescription)"), on: connection)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let response = self.dispatch(request: request)
            self.send(response, on: connection)
        }
    }

    // MARK: - Command dispatch

    @MainActor
    private func dispatch(request: TrackieRequest) -> TrackieResponse {
        switch request.type {
        case "health":
            return .success(count: store.items.count)

        case "add":
            guard let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return .failure("Missing title")
            }
            let item = store.add(
                title: title,
                note: request.note,
                project: request.project,
                priority: request.priority ?? 0,
                sourceApp: request.sourceApp,
                sessionId: request.sessionId,
                pid: request.pid
            )
            return .success(item: item, count: store.items.count)

        case "list":
            let filter = request.filter ?? "pending"
            var items = store.items
            if let project = request.projectFilter, !project.isEmpty {
                items = items.filter { $0.project == project }
            }
            switch filter {
            case "all":
                break
            case "done":
                items = items.filter { $0.status == .done }
            case "scratched":
                items = items.filter { $0.status == .scratched }
            default:
                items = items.filter { $0.status == .pending }
            }
            return .success(items: items, count: items.count)

        case "get":
            guard let item = resolveItem(request: request) else {
                return .failure("Item not found")
            }
            return .success(item: item)

        case "remove", "rm":
            guard let item = resolveItem(request: request) else {
                return .failure("Item not found")
            }
            _ = store.remove(id: item.id)
            return .success(count: store.items.count)

        case "done":
            guard let item = resolveItem(request: request) else {
                return .failure("Item not found")
            }
            let updated = store.setStatus(id: item.id, .done)
            return .success(item: updated)

        case "undone":
            guard let item = resolveItem(request: request) else {
                return .failure("Item not found")
            }
            let updated = store.setStatus(id: item.id, .pending)
            return .success(item: updated)

        case "scratch":
            guard let item = resolveItem(request: request) else {
                return .failure("Item not found")
            }
            let updated = store.setStatus(id: item.id, .scratched)
            return .success(item: updated)

        case "update":
            guard let item = resolveItem(request: request) else {
                return .failure("Item not found")
            }
            let updated = store.update(
                id: item.id,
                title: request.title,
                note: request.note.map { Optional.some($0) },
                project: request.project.map { Optional.some($0) },
                priority: request.priority
            )
            return .success(item: updated)

        case "append-note", "appendNote":
            guard let item = resolveItem(request: request) else {
                return .failure("Item not found")
            }
            guard let text = request.note, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure("Missing note text")
            }
            let updated = store.appendNote(id: item.id, text: text)
            return .success(item: updated)

        case "move":
            guard let item = resolveItem(request: request) else {
                return .failure("Item not found")
            }
            if let direction = request.direction {
                let updated = store.move(id: item.id, direction: direction)
                return .success(item: updated)
            }
            if let to = request.toIndex {
                let updated = store.move(id: item.id, toIndex: to)
                return .success(item: updated)
            }
            return .failure("Move requires direction or toIndex")

        case "clear":
            let filter = request.filter ?? "completed"
            let removed: Int
            switch filter {
            case "all":
                removed = store.clearAll()
            default:
                removed = store.clearCompleted()
            }
            return .success(count: removed)

        default:
            return .failure("Unknown command: \(request.type)")
        }
    }

    @MainActor
    private func resolveItem(request: TrackieRequest) -> TrackieItem? {
        if let idString = request.id, let uuid = UUID(uuidString: idString) {
            return store.item(id: uuid)
        }
        if let prefix = request.idPrefix ?? request.id, !prefix.isEmpty {
            return store.item(withIdPrefix: prefix)
        }
        return nil
    }

    private func send(_ response: TrackieResponse, on connection: NWConnection) {
        do {
            var data = try encoder.encode(response)
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            let fallback = "{\"ok\":false,\"error\":\"encode failed\"}\n".data(using: .utf8)
            connection.send(content: fallback, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
