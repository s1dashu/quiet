# Quiet

Quiet is a native macOS menu-bar app for a local file-organizing agent. Drop files or folders into Quiet and the bundled agent moves them into an organized local workspace.

The app is built with the native macOS stack, not Electron.

## What It Uses

- SwiftUI/AppKit for the status-bar app, glass window, chat UI, settings, drag/drop, and agent bridge.
- `NSGlassEffectView` on newer macOS versions, with `NSVisualEffectView` fallback.
- A bundled Node runtime for the local agent process.
- `@earendil-works/pi-coding-agent` and `@earendil-works/pi-ai` for the agent backend.
- JSON Lines over stdin/stdout as the local IPC protocol.

## Run

```bash
swift run quiet
```

Package a local app bundle:

```bash
./scripts/package-quiet-app.sh
open dist/Quiet.app
```

The packaged app launches its bundled Node binary. In development, it falls back to `/usr/bin/env node` when no bundled binary is present.

## Current Behavior

- Quiet runs as a menu-bar accessory app without a Dock icon.
- The status-bar icon toggles the main glass window.
- Dropped files are first ingested into `~/Documents/Quiet/Inbox`.
- The local agent organizes files into `~/Documents/Quiet/Files`.
- Future generated content should be written into `~/Documents/Quiet/Output`.
- Runtime data, memory, and undo logs live under `~/.quiet`.
- User-editable organizing rules live in `~/.quiet/memory.md` and are appended to the agent prompt.

## Agent Backend

`Sources/QuietMenuBar/Resources/pi-agent/server.mjs` is the Node JSONL agent daemon. It reads `quiet-prompt.md`, appends `~/.quiet/memory.md`, ingests dropped files into `~/Documents/Quiet/Inbox`, and organizes them under `~/Documents/Quiet/Files`.

Incoming JSONL event shape:

```json
{"type":"user_message","text":"整理这些文件","paths":["/path/to/file"]}
```

Representative outgoing events:

```json
{"type":"ready"}
{"type":"status","value":"正在扫描文件"}
{"type":"assistant_start","id":"..."}
{"type":"assistant_delta","id":"...","text":"..."}
{"type":"assistant_done","id":"..."}
{"type":"plan","items":["..."]}
```

For packaged builds, the app expects the bundled runtime at:

```text
Quiet.app/Contents/Resources/Quiet_QuietMenuBar.bundle/Resources/node
```
