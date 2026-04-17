import Foundation
import Network

/// Client for communicating with the Trackie broker over TCP+NDJSON.
public final class TrackieClient: @unchecked Sendable {
    public let host: String
    public let port: Int

    public init(host: String = TrackieDefaults.brokerHost, port: Int = TrackieDefaults.brokerPort) {
        self.host = host
        self.port = port
    }

    public func send(_ request: TrackieRequest, timeout: TimeInterval = 3.0) async throws -> TrackieResponse {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw TrackieError.serverError("Invalid port: \(port)")
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "trackie.client.\(UUID().uuidString)")
            var resumed = false
            var buffer = Data()

            let timeoutWork = DispatchWorkItem {
                if resumed { return }
                resumed = true
                connection.cancel()
                continuation.resume(throwing: TrackieError.serverNotRunning)
            }

            func resolve(_ result: Result<TrackieResponse, Error>) {
                if resumed { return }
                resumed = true
                timeoutWork.cancel()
                connection.cancel()
                continuation.resume(with: result)
            }

            func parseResponse(_ data: Data) {
                guard !data.isEmpty else {
                    resolve(.failure(TrackieError.invalidResponse))
                    return
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                do {
                    let response = try decoder.decode(TrackieResponse.self, from: data)
                    resolve(.success(response))
                } catch {
                    resolve(.failure(TrackieError.invalidResponse))
                }
            }

            func receiveResponse() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
                    if let error {
                        resolve(.failure(error))
                        return
                    }
                    if let data, !data.isEmpty {
                        buffer.append(data)
                        if let nl = buffer.firstIndex(of: 0x0A) {
                            parseResponse(Data(buffer.prefix(upTo: nl)))
                            return
                        }
                    }
                    if isComplete {
                        parseResponse(buffer)
                    } else {
                        receiveResponse()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    do {
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        var payload = try encoder.encode(request)
                        payload.append(0x0A)
                        connection.send(content: payload, completion: .contentProcessed { error in
                            if let error {
                                resolve(.failure(error))
                                return
                            }
                            receiveResponse()
                        })
                    } catch {
                        resolve(.failure(error))
                    }
                case .failed(let error):
                    resolve(.failure(error))
                case .cancelled:
                    break
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            connection.start(queue: queue)
        }
    }

    public func health() async throws -> Bool {
        let response = try await send(TrackieRequest(type: "health"))
        return response.ok
    }
}
