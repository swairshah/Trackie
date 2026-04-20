# Trackie — TODO

Roadmap of what's next, roughly in priority order.

---

## 1. Launch-at-login toggle

Expose a "Launch Trackie at login" checkbox in the menubar footer (or under the
⋯ menu). Back it with `SMAppService` on macOS 13+ so the OS handles the login
registration without needing a helper bundle.

- [ ] `LaunchAtLogin` wrapper around `SMAppService.mainApp.register/unregister`
- [ ] Menubar entry (checkbox / toggle)
- [ ] Persist state in UserDefaults just so the UI reflects reality even
      before the first toggle
- [ ] Test: register, reboot, verify Trackie starts as menubar-only

## 2. `trackie watch` — event stream for agents

Let agents *subscribe* to queue changes instead of polling `trackie list`.
Keeps the menubar broker, just adds a long-lived connection type.

- [ ] Broker: add `type: "watch"` request that keeps the connection open and
      writes one NDJSON event per mutation (`{event:"added", item:{…}}`,
      `{event:"status", id, from, to}`, `{event:"moved", id, to}`, etc.)
- [ ] CLI: `trackie watch` that prints events; `--json` for machine output
- [ ] Wire QueueStore mutations through a Combine publisher the broker taps
- [ ] Heartbeat + reconnect guidance in README

## 3. Agent recipes in README

Lower the barrier for hooking Trackie into common agent workflows. A new
"Wiring agents" section with copy-pasteable snippets.

- [ ] Claude Code: `Stop` / `PostToolUse` hook that pushes follow-ups
- [ ] Cursor: Rules snippet that tells the model to `trackie add` when it
      defers work
- [ ] Codex: system-prompt snippet + shell alias
- [ ] Aider: `/cmd` integration
- [ ] Plain scripts: `echo "…" | trackie add` cron examples

## 4. Notifications on new items

When something is pushed from outside the app (CLI, agent, remote), post a
quiet `UNUserNotificationCenter` notification so the user sees what happened.

- [ ] Request notification permission on first external add
- [ ] Collapse bursts (>2 adds within 5s → "N new items") to avoid spam
- [ ] Clicking the notification opens the main window focused on that item
      (reuse `MainWindowController.show(select:)`)
- [ ] Respect a "Silent adds" toggle in the menubar ⋯ menu

## 5. MCP server

Expose Trackie's commands as tools over the Model Context Protocol so
Claude Desktop / Claude Code / any MCP-speaking client can add, list,
update, and complete items natively — no shell-out required.

- [ ] Stand up an MCP stdio server (likely a new `trackie-mcp` binary) that
      delegates to the existing broker
- [ ] Tool schema: `trackie.add`, `trackie.list`, `trackie.done`, `trackie.move`,
      `trackie.watch` (streaming if the MCP client supports it)
- [ ] Ship mcp manifest / config snippet so users can drop it into their
      `claude_desktop_config.json` / similar
- [ ] Document in README under "Agent recipes"
