# Trackie

A personal, menubar-resident project tracker. Any agent or script can push items
into the queue through a tiny TCP broker; you reorder, mark done, or scratch
them from the menubar dropdown or a full window.

## Architecture

```
         +--------------+   127.0.0.1:27182 (NDJSON/TCP)   +---------------+
         | trackie CLI  | ------------------------------>  | Trackie.app   |
         | (or agent)   |                                  |  MenuBarExtra |
         +--------------+                                  |  Broker + UI  |
                                                           +---------------+
```

- **Broker port:** `27182` (Euler — intentionally far from PiTalk's 18080/18081)
- **Storage:** `~/Library/Application Support/Trackie/items.json`
- **Access:** loopback only; non-loopback peers are dropped in the accept path

## Build & run

```bash
./run.sh           # build, assemble .build/Trackie.app, launch, install `trackie` to ~/.local/bin
./scripts/build-app.sh            # build-only
./scripts/build-app.sh --release  # optimized build
./scripts/build-app.sh --universal  # release + arm64 + x86_64
```

After launch you should see the menubar icon. Click for the dropdown; hit
**Open** to bring up the full window.

## CLI

```bash
trackie add "Investigate flaky test"
trackie add "Refactor broker" --project trackie --note "see Broker.swift"
echo "random thought" | trackie add
trackie list                # pending only
trackie list --all
trackie list --json         # machine-readable
trackie mv 3f8a top
trackie mv 3f8a up
trackie done 3f8a
trackie scratch 3f8a        # drop without deleting
trackie rm 3f8a
trackie clear               # remove done + scratched
trackie ping                # health check
```

IDs are shown as an 8-char prefix; the CLI accepts any unique prefix.

## Layout

- `Sources/TrackieClient` — wire types (`TrackieItem`, `TrackieRequest`,
  `TrackieResponse`), `TrackieClient` over `NWConnection`.
- `Sources/TrackieApp` — SwiftUI `MenuBarExtra`, main window, `QueueStore`, and
  `Broker` (NWListener on loopback).
- `Sources/TrackieCLI` — the `trackie` command-line tool. Built as product
  `trackiectl` internally because macOS is case-insensitive and `Trackie` /
  `trackie` would collide in the same build folder.

## Integration from an agent

Any process can push an item by connecting to `127.0.0.1:27182` and sending a
single JSON line terminated by `\n`:

```json
{"type":"add","title":"Investigate flaky test","project":"trackie","sourceApp":"claude","sessionId":"sess-123"}
```

The broker replies with a single JSON line and closes the connection. See
`TrackieRequest` for the full command vocabulary (add, list, get, done, undone,
scratch, remove, update, move, clear, health).
