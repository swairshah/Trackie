# Trackie — development notes

## Architecture

```
         +--------------+   127.0.0.1:27182 (NDJSON/TCP)   +---------------+
         | trackie CLI  | ------------------------------>  | Trackie.app   |
         | (or agent)   |                                  |  MenuBarExtra |
         +--------------+                                  |  Broker + UI  |
                                                           +---------------+
```

- **Broker port:** `27182` — intentionally far from PiTalk's 18080/18081
- **Storage:** `~/Library/Application Support/Trackie/items.json`
- **Access:** loopback only; non-loopback peers are rejected in the accept path

## Build & run

```bash
./run.sh                              # debug build, assemble .build/Trackie.app, launch
./scripts/build-app.sh                # build-only (debug)
./scripts/build-app.sh --release      # optimized build
./scripts/build-app.sh --universal    # release + arm64 + x86_64
```

## Repository layout

- `Sources/TrackieClient/` — wire types (`TrackieItem`, `TrackieRequest`,
  `TrackieResponse`) and the `TrackieClient` that talks to the broker over
  `NWConnection`.
- `Sources/TrackieApp/` — SwiftUI `MenuBarExtra`, main window, `QueueStore`
  (persistent queue), `Broker` (NWListener on loopback), `DockIconManager`,
  `ResizableSplit`.
- `Sources/TrackieCLI/` — the `trackie` command-line tool. Built under the
  SwiftPM product name `trackiectl` because macOS APFS is case-insensitive and
  two binaries named `Trackie` and `trackie` would clobber each other in
  `.build/debug/`. The cask and install scripts rename it back to `trackie` on
  the user's PATH.

## Broker protocol

Any process can push an item by opening a TCP connection to
`127.0.0.1:27182` and sending a single JSON object terminated by a newline:

```json
{"type":"add","title":"Investigate flaky test","project":"trackie","sourceApp":"claude","sessionId":"sess-123"}
```

The broker replies with a single JSON line and closes the connection. See
`TrackieRequest` in `Sources/TrackieClient/TrackieModel.swift` for the full
command vocabulary: `add`, `list`, `get`, `done`, `undone`, `scratch`,
`remove`, `update`, `move`, `clear`, `health`.

## Icons

- App icon source: `Resources/icons/rolodex-v4-floating-card.png`
- Menubar icon source: `Resources/icons/rolodex-menubar-source.png`
- `scripts/convert_menubar_icon.swift` converts the source into a
  black-and-white template suitable for `NSImage.isTemplate = true`. It uses
  brightness × alpha as the mask so the light card fill becomes the ink and
  the black strokes become see-through, which reads much better at 22–26pt.

## Release

See [RELEASE.md](RELEASE.md) for the sign-notarise-tag-release workflow.
