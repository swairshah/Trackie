<h1>  <img src="assets/icon_128.png" alt="Trackie icon" width="30"/> Trackie</h1>

__Your personal issue tracker that you and your coding agents share.__

```bash
brew install --cask swairshah/tap/trackie
```

A tiny menubar app (plus a `trackie` CLI) that gives every coding agent on
your machine — Codex, Cursor, Claude Code, Aider, pyd.ev, anything — the same
place to push work, check what's open, and mark things done.

## What is it?

Trackie is a single shared to-do list that lives in your menubar.

- Any coding agent can **push** new items as it discovers them ("flaky test in
  `auth_test.py`", "refactor the broker", "follow-up on the review comment")
- You and any agent can **see** the full backlog, reorder it, or mark things
  done
- Items carry along where they came from — which agent/session filed it, what
  project it belongs to, any note the agent left behind — so when you come
  back to an item you know what context it had
- Completed work sticks around in the `DONE` section so you can glance at what
  just happened without trawling through terminal scrollback

It's the missing "shared notepad" between you and your agents.

## Install

```bash
brew install --cask swairshah/tap/trackie
```

Or grab the DMG directly from the [Releases page](https://github.com/swairshah/Trackie/releases).

The cask installs two things for you:

- **Trackie.app** — the menubar app and full window
- **`trackie`** — the command-line tool, auto-symlinked onto your `PATH`

## Using Trackie — the UI

Click the rolodex icon in the menubar to pop the dropdown. From there you can:

- Add a new item inline
- See the most recent open items (or all of them when you expand)
- Check one off, bump it up/down the queue, or scratch it
- Click **Open** (or double-click any row) to bring up the full window

In the full window you get:

- The queue in the sidebar — drag-reorder, click to see the detail view
- Title, project, and notes on the right — edit in place
- Three sections: `QUEUE`, `DONE`, `SCRATCHED` so nothing gets lost
- A draggable divider between sidebar and detail (Trackie remembers the width
  across launches)

## Using Trackie — from an agent

Every coding agent that can run a shell command can talk to Trackie through
the `trackie` CLI.

```bash
trackie add "Investigate flaky login test"
trackie add "Refactor broker" --project trackie --note "see Broker.swift"
echo "random thought" | trackie add

trackie list                # what's open right now
trackie list --all          # include done + scratched
trackie list --json         # machine-readable, perfect for agents

trackie done 3f8a           # mark done by id prefix
trackie mv 3f8a top         # bump to the top of the queue
trackie rm 3f8a
trackie clear               # drop everything that's done or scratched
```

Any process — a Claude Code subagent, a cron job, a Cursor hook, a one-off
Python script — can push items or tick them off without knowing anything
about Trackie's internals. You stay in the loop by glancing at the menubar.

Point your agent at the same commands and it'll start filing work for you.

## First launch

- Click the menubar icon to open the dropdown
- Type your first item in "Add to queue" and hit enter
- Toggle the dock icon from the menubar footer if you want Trackie to live in
  the dock too (useful when you keep the full window open)

Your items are stored locally at
`~/Library/Application Support/Trackie/items.json`. Nothing leaves your
machine — the agent integration runs over loopback only.

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel

## Development

Building from source, architecture notes, and release instructions live in
[DEVELOPMENT.md](DEVELOPMENT.md).

## License

MIT
