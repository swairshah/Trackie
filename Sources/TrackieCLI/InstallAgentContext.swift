import Foundation

/// Canonical "Trackie is available" block that agents read to learn how to
/// use Trackie. Kept in lockstep with docs/agent-context.md.
///
/// The sentinel markers let us find and replace an existing block on
/// re-runs so the command is idempotent.
private let agentContextStartMarker = "<!-- trackie:agent-context -->"
private let agentContextEndMarker = "<!-- /trackie:agent-context -->"

private let agentContextBlock = """
\(agentContextStartMarker)

## Trackie — shared issue tracker

Trackie is a local, menubar-resident issue tracker shared between the user and
every coding agent on this machine. Use it as a durable backlog for substantial
work that may span long sessions, multiple days, or handoffs between agents.

The `trackie` CLI is already installed on `PATH` (via
`brew install --cask swairshah/tap/trackie`).

### How to use Trackie

- Prefer reading first: run `trackie list --json` when starting substantial
  work so you know what is already tracked and avoid creating duplicates.
- Add items only for large, durable work: multi-session projects, investigations
  that may continue later, risky migrations, or decisions blocked on the user.
- Don't add routine tasks, small fixes, quick follow-ups, ordinary test runs,
  or anything you expect to finish in the current session.

Trackie is not a progress log. If you add an item, keep notes concise and mark
it `done` only when the tracked work is actually complete.

### Commands

```bash
trackie add "Investigate flaky login test" --project auth --note "see auth_test.py"
trackie list --json          # read existing items before adding new ones
trackie note 3f8a "root cause is likely token refresh timing"
trackie done 3f8a            # mark complete by id prefix
trackie scratch 3f8a         # drop without marking complete
```

Always tag `--project <name>` when you're inside a project directory, and
`--session-id <id>` with your agent session identifier when available.
Before finishing, update only the Trackie items you materially worked on.

\(agentContextEndMarker)
"""

/// Plan for where to write the agent-context block, grouped by the common
/// conventions across agents.
private struct AgentTarget {
    let path: URL
    let label: String
    /// If `true`, we'll create the file if it doesn't exist. Files we
    /// don't create unless the user has already opted in (e.g. they
    /// already have the file).
    let createIfMissing: Bool
}

func installAgentContext(global: Bool, dryRun: Bool, quiet: Bool) {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)

    // Collect candidate files. For project-scoped runs we write into the
    // repo you're standing in; for --global we write into $HOME so the
    // context applies to every project automatically.
    var targets: [AgentTarget] = []

    if global {
        // Claude Code: ~/.claude/CLAUDE.md
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        targets.append(AgentTarget(
            path: claudeDir.appendingPathComponent("CLAUDE.md"),
            label: "Claude Code (global)",
            createIfMissing: true
        ))
        // Codex: ~/.codex/AGENTS.md
        let codexDir = home.appendingPathComponent(".codex", isDirectory: true)
        targets.append(AgentTarget(
            path: codexDir.appendingPathComponent("AGENTS.md"),
            label: "Codex (global)",
            createIfMissing: true
        ))
        // Aider / OpenAI tooling: ~/AGENTS.md is uncommon, but a per-user
        // copy is still useful — users symlink it into projects.
        targets.append(AgentTarget(
            path: home.appendingPathComponent("AGENTS.md"),
            label: "AGENTS.md (global)",
            createIfMissing: true
        ))
        // Cursor: ~/.cursor/rules/trackie.mdc
        let cursorDir = home.appendingPathComponent(".cursor/rules", isDirectory: true)
        targets.append(AgentTarget(
            path: cursorDir.appendingPathComponent("trackie.mdc"),
            label: "Cursor (global rules)",
            createIfMissing: true
        ))
        // pi.dev: ~/.pi/agent/AGENTS.md
        let piDir = home.appendingPathComponent(".pi/agent", isDirectory: true)
        targets.append(AgentTarget(
            path: piDir.appendingPathComponent("AGENTS.md"),
            label: "pi (global)",
            createIfMissing: true
        ))
    } else {
        targets.append(AgentTarget(
            path: cwd.appendingPathComponent("CLAUDE.md"),
            label: "Claude Code",
            createIfMissing: false
        ))
        targets.append(AgentTarget(
            path: cwd.appendingPathComponent("AGENTS.md"),
            label: "AGENTS.md (Codex / Aider / OpenAI)",
            createIfMissing: false
        ))
        targets.append(AgentTarget(
            path: cwd.appendingPathComponent(".cursor/rules/trackie.mdc"),
            label: "Cursor",
            createIfMissing: false
        ))
        targets.append(AgentTarget(
            path: cwd.appendingPathComponent(".pi/agent/AGENTS.md"),
            label: "pi",
            createIfMissing: false
        ))
    }

    var touched: [(URL, String, Action)] = []
    for target in targets {
        let action = planAction(for: target, fm: fm)
        if let action {
            touched.append((target.path, target.label, action))
        }
    }

    if touched.isEmpty {
        if global {
            FileHandle.standardError.write("No agent context files found, and --global didn't produce any targets. This shouldn't happen.\n".data(using: .utf8)!)
            exit(1)
        }
        FileHandle.standardError.write(
            "trackie install-agent-context: no agent files found in \(cwd.path).\n".data(using: .utf8)!
        )
        FileHandle.standardError.write(
            "Hint: run with --global to drop the Trackie block into your home-level agent configs, or create one of CLAUDE.md / AGENTS.md / .cursor/rules/trackie.mdc / .pi/agent/AGENTS.md first.\n".data(using: .utf8)!
        )
        exit(1)
    }

    for (path, label, action) in touched {
        switch action {
        case .create:
            if !quiet { print("\(dryRun ? "[dry-run] would create" : "created"): \(path.path)  (\(label))") }
            if !dryRun {
                try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? (agentContextBlock + "\n").write(to: path, atomically: true, encoding: .utf8)
            }
        case .append:
            if !quiet { print("\(dryRun ? "[dry-run] would append to" : "appended to"): \(path.path)  (\(label))") }
            if !dryRun {
                let existing = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
                let prefix = existing.hasSuffix("\n") ? "" : "\n"
                let new = existing + prefix + "\n" + agentContextBlock + "\n"
                try? new.write(to: path, atomically: true, encoding: .utf8)
            }
        case .replace:
            if !quiet { print("\(dryRun ? "[dry-run] would refresh Trackie block in" : "refreshed Trackie block in"): \(path.path)  (\(label))") }
            if !dryRun, let existing = try? String(contentsOf: path, encoding: .utf8),
               let new = replacingTrackieBlock(in: existing, with: agentContextBlock) {
                try? new.write(to: path, atomically: true, encoding: .utf8)
            }
        }
    }
}

private enum Action {
    case create
    case append
    case replace
}

private func planAction(for target: AgentTarget, fm: FileManager) -> Action? {
    if fm.fileExists(atPath: target.path.path) {
        guard let existing = try? String(contentsOf: target.path, encoding: .utf8) else {
            return nil
        }
        if existing.contains(agentContextStartMarker) {
            return .replace
        }
        return .append
    } else if target.createIfMissing {
        return .create
    }
    return nil
}

/// Replace the existing Trackie-context block (delimited by the sentinel
/// markers) with the current canonical block. Returns nil if no block is
/// found.
private func replacingTrackieBlock(in text: String, with block: String) -> String? {
    guard let startRange = text.range(of: agentContextStartMarker),
          let endRange = text.range(of: agentContextEndMarker, range: startRange.upperBound..<text.endIndex)
    else { return nil }
    let full = startRange.lowerBound..<endRange.upperBound
    return text.replacingCharacters(in: full, with: block)
}
