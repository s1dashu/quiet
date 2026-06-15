# AGENTS.md

## Project

This project is the native macOS desktop/menu-bar app for **Neat**, a file-organizing agent UI.

The app is intentionally built with the native macOS stack, not Electron. It is a Swift Package app that uses AppKit + SwiftUI for the desktop glass window and an embedded Node runtime for the pi coding agent.

## Main Files

- `Package.swift` defines the Swift package and executable product `neat`.
- `Sources/PiDesktopWidget/main.swift` contains the macOS app, status bar item, glass window, chat UI, settings page, drag/drop, auto-follow, and agent process bridge.
- `Sources/PiDesktopWidget/Resources/pi-agent/server.mjs` is the Node JSONL agent server.
- `Sources/PiDesktopWidget/Resources/pi-agent/neat-prompt.md` is the Neat system prompt used by pi.
- `scripts/package-neat-app.sh` builds `dist/Neat.app`, embeds Node, embeds the pi-agent resources, and copies `node_modules`.
- `README.md` has user-facing project notes.

There are older demo artifacts in the repo such as `CodexActivityWidget*`, `Shared`, `project.yml`, `.build`, and `dist`. Treat the SwiftPM `PiDesktopWidget` target as the active app unless the user explicitly asks about those legacy files.

## Product Shape

- App name: `Neat`.
- Runtime data root: `~/.neat`.
- Dragged files first go to `~/.neat/inbox/<batch-id>`.
- The pi agent organizes files into `~/.neat/files`.
- Future generated content should go to `~/.neat/output`.
- Undo logs go to `~/.neat/undo`.

Do not move user files outside `~/.neat/files` unless the user explicitly asks for a different policy.

## Agent Backend

The app embeds and launches Node itself, so end users do not need Node installed.

The Node backend lives at `Sources/PiDesktopWidget/Resources/pi-agent/server.mjs` and loads:

- `@earendil-works/pi-coding-agent@0.79.3`
- `@earendil-works/pi-ai@0.79.3`

The Swift app talks to the backend over JSONL stdin/stdout.

Current tool policy is intentionally small and local-file focused:

- `read`
- `bash`
- `grep`
- `find`
- `ls`

## Model Settings

Default settings:

- Provider: `deepseek`
- Model: `deepseek-v4-flash`
- Thinking: `medium`

Settings can be overridden by app settings/UserDefaults and environment variables:

- `NEAT_MODEL_PROVIDER`
- `NEAT_MODEL_ID`
- `NEAT_THINKING_LEVEL`

The settings UI is a full page switch inside the main app content, not a transparent modal overlay.

## UI Principles

- Keep the outer window glass as close to the system material as possible.
- Prefer `NSGlassEffectView` on macOS 26+ and `NSVisualEffectView` fallback on older macOS.
- Avoid fake heavy overlays, gradients, or extra tint layers that create visible bands or muddy glass.
- The status bar icon toggles the window: click once to show, click again to hide.
- The menu-bar popover/window should appear like normal macOS menu extras, offset toward the right side of the status item rather than centered directly underneath.
- The top-right controls are folder and settings icons. Do not reintroduce the old `AUTO` pill.
- The green status dot in the top-left was removed by request; do not re-add it unless asked.

## Chat Interaction

The chat area follows the latest message automatically unless the user scrolls upward. When the user scrolls away from the bottom, show a centered `跟随` button above the composer. Clicking it, or scrolling back to the bottom, re-enables automatic following.

Tool calls are rendered as compact one-line rows:

- Left: icon.
- Middle: tool name and truncated key content.
- Right: running state or a small green completed indicator.
- `write` and `edit` calls may expand while active and collapse after completion.
- Fast tools such as `bash`, `read`, and `ls` should default to collapsed rows.

While the agent is between actions, show a small loading/waiting state rather than leaving the UI visually frozen.

## Useful Commands

```sh
swift build
node --check Sources/PiDesktopWidget/Resources/pi-agent/server.mjs
./scripts/package-neat-app.sh
open dist/Neat.app
```

If testing packaging, remember the packaged app launches its embedded Node from:

`dist/Neat.app/Neat_PiDesktopWidget.bundle/Resources/node`

## Safety Notes

- Preserve user files and old project directories when moving or renaming paths.
- Do not delete `~/.neat` data during ordinary development.
- Prefer small, native AppKit/SwiftUI changes over adding web or Electron dependencies.
- If updating `.codex` project records for a path migration, update full absolute path references carefully.
