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
every coding agent on this machine. Items pushed here let the user see work
you've queued up, are working on, or completed — even after your session ends.

The `trackie` CLI is already installed on `PATH` (via
`brew install --cask swairshah/tap/trackie`).

### When to push to Trackie

- **Deferred work**: if you discover a follow-up while solving another task,
  file it instead of silently dropping it on the floor.
- **Non-trivial in-progress work**: when starting a task that will take more
  than a few tool calls, add it so the user can see what you're working on.
- **Questions / decisions pending the user**: add an item so it doesn't get
  buried in the transcript.

Don't push trivia ("ran the tests"). Push things the user genuinely benefits
from seeing later.

### Commands

```bash
trackie add "Investigate flaky login test" --project auth --note "see auth_test.py"
trackie list                 # open items
trackie list --json          # machine-readable
trackie done 3f8a            # mark done by 8-char id prefix
trackie scratch 3f8a         # drop without marking complete
```

Always tag `--project <name>` when you're inside a project directory, and
`--session-id <id>` with your agent session identifier when available.
Before finishing a coherent unit of work, run `trackie list --json` and mark
the items you actually completed as `done`.

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
        // Codex / Aider / OpenAI tooling: ~/AGENTS.md is uncommon, but a
        // per-user copy is still useful — users symlink it into projects.
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
            "Hint: run with --global to drop the Trackie block into your home-level agent configs, or create one of CLAUDE.md / AGENTS.md / .cursor/rules/trackie.mdc first.\n".data(using: .utf8)!
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
