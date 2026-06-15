# Neat Desktop Widget

A native macOS desktop widget for a persistent Neat / Pi file-organizing agent.

This app uses:

- SwiftUI/AppKit for the lightweight always-on desktop window.
- `NSVisualEffectView` for a native glass-style surface.
- A long-running Node process for the agent runtime.
- Bundled Node + `@earendil-works/pi-coding-agent`, matching Ousia's pi stack.
- JSON Lines over stdin/stdout as the local IPC protocol.
- File/folder drag-and-drop as conversation attachments.

## Run

```bash
swift run neat
```

Package a local app bundle:

```bash
./scripts/package-neat-app.sh
open dist/Neat.app
```

The app looks for an app-bundled `node` binary first. If none exists, it falls
back to `/usr/bin/env node` for development.

## Current Behavior

- The widget launches as an accessory app without a Dock icon.
- The window lives on the desktop layer, can join all Spaces, and remembers its position.
- Dropping files sends a `user_message` event to the Node agent.
- The Node agent keeps in-memory session state and streams assistant text.
- Dropped files are first moved into `~/.neat/inbox`.
- pi-coding-agent inspects inbox file names/content and can use bash.
- pi is instructed to move organized files into `~/.neat/files`.
- User-editable organizing rules live in `~/.neat/memory.md` and are appended to the agent system prompt. The agent may update this file when the user expresses durable organizing preferences.
- Future generated content should be written into `~/.neat/output`.
- The app records completed moves under `~/.neat/undo`.
- Type `撤回` or `undo` to restore the most recent completed batch.

## Pi Agent Integration

`Sources/PiDesktopWidget/Resources/pi-agent/server.mjs` is the Node agent daemon.
It keeps a persistent conversation, reads the preset prompt from
`neat-prompt.md`, appends `~/.neat/memory.md`, ingests dropped files into
`~/.neat/inbox`, and organizes them under `~/.neat/files`.

Keep the JSONL protocol shape:

```json
{"type":"user_message","text":"整理这些文件","paths":["/path/to/file"]}
```

Expected outgoing events:

```json
{"type":"ready"}
{"type":"status","value":"正在扫描文件"}
{"type":"assistant_start","id":"..."}
{"type":"assistant_delta","id":"...","text":"..."}
{"type":"assistant_done","id":"..."}
{"type":"plan","items":["..."]}
```

For users without Node installed, package a signed Node binary at:

```text
Neat.app/Contents/Resources/node
```

The Swift launcher will use that binary automatically.
