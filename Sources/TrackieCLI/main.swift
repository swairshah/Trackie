import Foundation
import TrackieClient

// MARK: - Usage

let USAGE = """
trackie - personal queue / project tracker CLI

USAGE:
    trackie <COMMAND> [ARGS...]
    echo "something to do" | trackie add

COMMANDS:
    add <title>                 Add an item to the queue
        -p, --project <name>    Tag with a project
        -n, --note <text>       Add a note
        --priority <N>          Priority (int, higher = more important)

    list                        List items (default: pending only)
        -a, --all               Include done + scratched
        --done                  Only done items
        --scratched             Only scratched items
        -p, --project <name>    Filter by project

    get <id>                    Show full details for an item
    done <id>                   Mark an item as done
    undone <id>                 Move a done/scratched item back to pending
    scratch <id>                Scratch (drop) an item
    rm <id>                     Delete an item
    mv <id> up|down|top|bottom  Move item in the queue
    mv <id> --to <index>        Move item to a specific 0-based index
    update <id>                 Replace title / note / project / priority
    note <id> <text>            Append additional note text to an item
                                (pipe stdin, or pass --note <text>, also works)
    clear                       Clear completed + scratched items
    clear --all                 Clear EVERYTHING (destructive)

    install-agent-context       Write the Trackie "how to use me" block into
                                CLAUDE.md / AGENTS.md / .cursor/rules/ so any
                                agent running in this directory knows Trackie
                                is available.
        -g, --global            Target home-level configs instead of cwd
        --dry-run               Print what would change without writing

GLOBAL OPTIONS:
    --host <HOST>               Broker host (default: 127.0.0.1)
    --port <PORT>               Broker port (default: \(TrackieDefaults.brokerPort))
    --json                      Output machine-readable JSON
    -S, --session-id <ID>       Tag item with a session id
    -q, --quiet                 Suppress non-error output
    -h, --help                  Show this help

IDs can be either a full UUID or a short prefix (e.g. `trackie done 3f8a2b`).

EXAMPLES:
    trackie add "Fix build on CI"
    trackie add "Investigate flaky test" --project trackie --note "see logs"
    echo "refactor broker" | trackie add -p trackie
    trackie list
    trackie done 3f8a
    trackie mv 3f8a top
    trackie rm 3f8a
    trackie note 3f8a "turned out to be a caching issue, see commit abc123"
"""

// MARK: - Arg parsing

struct ParsedArgs {
    var command: String = ""
    var positionals: [String] = []
    var project: String?
    var note: String?
    var priority: Int?
    var filter: String?         // "all" | "done" | "scratched"
    var projectFilter: String?
    var toIndex: Int?
    var host = TrackieDefaults.brokerHost
    var port = TrackieDefaults.brokerPort
    var sessionId: String?
    var json = false
    var quiet = false
    var help = false
    var title: String?
    var global = false
    var dryRun = false
}

func parseArgs() -> ParsedArgs {
    var p = ParsedArgs()
    let args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else {
        p.help = true
        return p
    }
    var i = 0
    // First non-flag token is the command.
    while i < args.count, args[i].hasPrefix("-") {
        if args[i] == "-h" || args[i] == "--help" { p.help = true; return p }
        i += 1
    }
    if i < args.count {
        p.command = args[i]
        i += 1
    }
    while i < args.count {
        let a = args[i]
        switch a {
        case "-h", "--help":
            p.help = true
        case "-p", "--project":
            i += 1
            if i < args.count {
                if p.command == "list" {
                    p.projectFilter = args[i]
                } else {
                    p.project = args[i]
                }
            }
        case "-n", "--note":
            i += 1
            if i < args.count { p.note = args[i] }
        case "--priority":
            i += 1
            if i < args.count, let v = Int(args[i]) { p.priority = v }
        case "-a", "--all":
            if p.command == "list" { p.filter = "all" }
            if p.command == "clear" { p.filter = "all" }
        case "--done":
            p.filter = "done"
        case "--scratched":
            p.filter = "scratched"
        case "--to":
            i += 1
            if i < args.count, let v = Int(args[i]) { p.toIndex = v }
        case "-t", "--title":
            i += 1
            if i < args.count { p.title = args[i] }
        case "--host":
            i += 1
            if i < args.count { p.host = args[i] }
        case "--port":
            i += 1
            if i < args.count, let v = Int(args[i]) { p.port = v }
        case "-S", "--session-id":
            i += 1
            if i < args.count { p.sessionId = args[i] }
        case "--json":
            p.json = true
        case "-q", "--quiet":
            p.quiet = true
        case "-g", "--global":
            p.global = true
        case "--dry-run":
            p.dryRun = true
        default:
            if a.hasPrefix("-") {
                FileHandle.standardError.write("Unknown option: \(a)\n".data(using: .utf8)!)
            } else {
                p.positionals.append(a)
            }
        }
        i += 1
    }
    return p
}

// MARK: - Output helpers

func readStdin() -> String? {
    if isatty(STDIN_FILENO) != 0 { return nil }
    guard let data = try? FileHandle.standardInput.readToEnd(),
          let s = String(data: data, encoding: .utf8) else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write("trackie: \(message)\n".data(using: .utf8)!)
    exit(code)
}

func printJSON<T: Encodable>(_ value: T) {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(value), let s = String(data: data, encoding: .utf8) {
        print(s)
    }
}

func printItemRow(index: Int?, item: TrackieItem) {
    let mark: String
    switch item.status {
    case .pending:    mark = "○"
    case .done:       mark = "✓"
    case .scratched:  mark = "✕"
    }
    let idx = index.map { String(format: "%2d ", $0) } ?? ""
    var suffix = ""
    if let project = item.project, !project.isEmpty {
        suffix += " \u{001B}[2m[\(project)]\u{001B}[0m"
    }
    if let note = item.note, !note.isEmpty {
        let short = note.replacingOccurrences(of: "\n", with: " ").prefix(48)
        suffix += " \u{001B}[2m— \(short)\u{001B}[0m"
    }
    let id = item.shortId
    let title: String
    switch item.status {
    case .pending:   title = item.title
    case .done:      title = "\u{001B}[9m\(item.title)\u{001B}[0m"
    case .scratched: title = "\u{001B}[2m\(item.title)\u{001B}[0m"
    }
    print("\(idx)\(mark) \u{001B}[90m\(id)\u{001B}[0m  \(title)\(suffix)")
}

// MARK: - Commands

func run() async {
    let args = parseArgs()
    if args.help || args.command.isEmpty {
        FileHandle.standardError.write(USAGE.data(using: .utf8)!)
        exit(args.help ? 0 : 1)
    }

    let client = TrackieClient(host: args.host, port: args.port)

    func trySend(_ request: TrackieRequest) async -> TrackieResponse {
        do {
            return try await client.send(request)
        } catch {
            die("Could not reach Trackie broker on \(args.host):\(args.port). Is Trackie.app running?")
        }
    }

    switch args.command {

    case "add":
        var title = args.positionals.joined(separator: " ")
        if title.isEmpty {
            if let piped = readStdin() { title = piped }
        }
        if title.isEmpty {
            die("add requires a title")
        }
        let req = TrackieRequest(
            type: "add",
            title: title,
            note: args.note,
            project: args.project,
            priority: args.priority,
            sourceApp: "trackie-cli",
            sessionId: args.sessionId,
            pid: getpid()
        )
        let response = await trySend(req)
        if !response.ok { die(response.error ?? "add failed") }
        if args.json {
            printJSON(response)
        } else if !args.quiet, let item = response.item {
            print("added \u{001B}[90m\(item.shortId)\u{001B}[0m  \(item.title)")
        }

    case "list", "ls":
        let req = TrackieRequest(type: "list", filter: args.filter ?? "pending", projectFilter: args.projectFilter)
        let response = await trySend(req)
        if !response.ok { die(response.error ?? "list failed") }
        if args.json {
            printJSON(response)
        } else {
            let items = response.items ?? []
            if items.isEmpty {
                if !args.quiet {
                    let label = args.filter ?? "pending"
                    print("no \(label) items")
                }
            } else {
                for (idx, item) in items.enumerated() {
                    printItemRow(index: idx, item: item)
                }
            }
        }

    case "get", "show":
        guard let id = args.positionals.first else { die("get requires an id") }
        let response = await trySend(TrackieRequest(type: "get", id: id, idPrefix: id))
        if !response.ok { die(response.error ?? "not found") }
        if args.json {
            printJSON(response)
        } else if let item = response.item {
            printItemRow(index: nil, item: item)
            print("  id:       \(item.id.uuidString)")
            if let p = item.project { print("  project:  \(p)") }
            if let n = item.note { print("  note:     \(n)") }
            print("  status:   \(item.status.rawValue)")
            print("  created:  \(item.createdAt)")
            print("  updated:  \(item.updatedAt)")
            if let src = item.sourceApp { print("  source:   \(src)") }
            if let sid = item.sessionId { print("  session:  \(sid)") }
        }

    case "done":
        guard let id = args.positionals.first else { die("done requires an id") }
        let response = await trySend(TrackieRequest(type: "done", id: id, idPrefix: id))
        if !response.ok { die(response.error ?? "done failed") }
        if args.json { printJSON(response) }
        else if !args.quiet, let item = response.item { print("done: \(item.title)") }

    case "undone", "reopen":
        guard let id = args.positionals.first else { die("undone requires an id") }
        let response = await trySend(TrackieRequest(type: "undone", id: id, idPrefix: id))
        if !response.ok { die(response.error ?? "undone failed") }
        if args.json { printJSON(response) }
        else if !args.quiet, let item = response.item { print("reopened: \(item.title)") }

    case "scratch":
        guard let id = args.positionals.first else { die("scratch requires an id") }
        let response = await trySend(TrackieRequest(type: "scratch", id: id, idPrefix: id))
        if !response.ok { die(response.error ?? "scratch failed") }
        if args.json { printJSON(response) }
        else if !args.quiet, let item = response.item { print("scratched: \(item.title)") }

    case "rm", "remove", "delete":
        guard let id = args.positionals.first else { die("rm requires an id") }
        let response = await trySend(TrackieRequest(type: "remove", id: id, idPrefix: id))
        if !response.ok { die(response.error ?? "rm failed") }
        if args.json { printJSON(response) }
        else if !args.quiet { print("removed \(id)") }

    case "mv", "move":
        guard let id = args.positionals.first else { die("mv requires an id") }
        let direction = args.positionals.count >= 2 ? args.positionals[1] : nil
        let req = TrackieRequest(
            type: "move",
            id: id,
            idPrefix: id,
            toIndex: args.toIndex,
            direction: direction
        )
        let response = await trySend(req)
        if !response.ok { die(response.error ?? "mv failed") }
        if args.json { printJSON(response) }
        else if !args.quiet, let item = response.item { print("moved: \(item.title)") }

    case "note", "append-note":
        guard let id = args.positionals.first else { die("note requires an id") }
        var text = args.positionals.dropFirst().joined(separator: " ")
        if text.isEmpty, let piped = readStdin() { text = piped }
        if text.isEmpty, let n = args.note { text = n }
        if text.isEmpty {
            die("note requires text: `trackie note <id> \"text\"`, or pipe via stdin, or pass --note")
        }
        let req = TrackieRequest(
            type: "append-note",
            note: text,
            id: id,
            idPrefix: id,
            sourceApp: "trackie-cli",
            sessionId: args.sessionId,
            pid: getpid()
        )
        let response = await trySend(req)
        if !response.ok { die(response.error ?? "note failed") }
        if args.json { printJSON(response) }
        else if !args.quiet, let item = response.item { print("noted: \(item.title)") }

    case "update", "edit":
        guard let id = args.positionals.first else { die("update requires an id") }
        let req = TrackieRequest(
            type: "update",
            title: args.title,
            note: args.note,
            project: args.project,
            priority: args.priority,
            id: id,
            idPrefix: id
        )
        let response = await trySend(req)
        if !response.ok { die(response.error ?? "update failed") }
        if args.json { printJSON(response) }
        else if !args.quiet, let item = response.item { print("updated: \(item.title)") }

    case "clear":
        let req = TrackieRequest(type: "clear", filter: args.filter)
        let response = await trySend(req)
        if !response.ok { die(response.error ?? "clear failed") }
        if args.json { printJSON(response) }
        else if !args.quiet { print("cleared \(response.count ?? 0) items") }

    case "health", "ping":
        do {
            let ok = try await client.health()
            if ok {
                if !args.quiet { print("ok") }
                exit(0)
            } else {
                die("broker reported not ok", code: 2)
            }
        } catch {
            die("broker unreachable: \(error.localizedDescription)", code: 2)
        }

    case "install-agent-context", "install-agent":
        installAgentContext(global: args.global, dryRun: args.dryRun, quiet: args.quiet)

    default:
        FileHandle.standardError.write("Unknown command: \(args.command)\n\n".data(using: .utf8)!)
        FileHandle.standardError.write(USAGE.data(using: .utf8)!)
        exit(1)
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    await run()
    sem.signal()
}
sem.wait()
