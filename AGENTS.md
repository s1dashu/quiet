# AGENTS.md

## Project

This project is the native macOS status-bar app for **Quiet**, a local agent UI.

The app is intentionally built with the native macOS stack, not Electron. It is a Swift Package app that uses AppKit + SwiftUI for the menu-bar glass window and an embedded Node runtime for the pi coding agent.

## Main Files

- `Package.swift` defines the Swift package and executable product `quiet`.
- `Sources/QuietMenuBar/main.swift` contains the macOS app, status bar item, glass window, chat UI, settings page, drag/drop, auto-follow, and agent process bridge.
- `Sources/QuietMenuBar/Resources/pi-agent/server.mjs` is the Node JSONL agent server.
- `Sources/QuietMenuBar/Resources/pi-agent/quiet-prompt.md` is the Quiet system prompt used by pi.
- `scripts/package-quiet-app.sh` builds `dist/Quiet.app`, embeds Node, embeds the pi-agent resources, and copies `node_modules`.
- `README.md` has user-facing project notes.

Treat the SwiftPM `QuietMenuBar` target as the active app. Build output under `.build` and packaged artifacts under `dist` are generated files.

## Product Shape

- App name: `Quiet`.
- Runtime data root: `~/.quiet`.
- User-visible content root: `~/Documents/Blackhole`.
- Dragged files first go to visible inbox batches under `~/Documents/Blackhole/00-09 System management/00 System management/00.01 Inbox for Blackhole/<batch-id>`.
- The pi agent organizes files using the Johnny.Decimal structure directly:
  - `00-09 System management/00 System management/00.00 Index for Blackhole` for the system index.
  - `00-09 System management/00 System management/00.01 Inbox for Blackhole` for new drops, in-progress material, and resources that still need human judgment.
  - `00-09 System management/00 System management/00.02 Task & project management for Blackhole` for task/project-management material.
  - `00-09 System management/00 System management/00.03 Templates for Blackhole` for templates.
  - `00-09 System management/00 System management/00.08 Someday for Blackhole` for someday material.
  - `00-09 System management/00 System management/00.09 Archive for Blackhole` for completed or inactive system-management material.
  - `10-19 Personal 个人`, `20-29 Money 财务`, `30-39 Work 工作`, `40-49 Legal & Admin 法务行政`, `50-59 Assets & Property 资产`, and `90-99 Archive 归档` for organized user resources.
- Keep generated or explanatory content in chat unless the user explicitly asks for files.
- Undo logs go to `~/.blackhole/undo`.

Do not move user files outside `~/Documents/Blackhole` unless the user explicitly asks for a different policy.

## Agent Backend

The app embeds and launches Node itself, so end users do not need Node installed.

The Node backend lives at `Sources/QuietMenuBar/Resources/pi-agent/server.mjs` and loads:

- `@earendil-works/pi-coding-agent@0.79.3`
- `@earendil-works/pi-ai@0.79.3`

The Swift app talks to the backend over JSONL stdin/stdout.

Current tool policy does not pass a restricted whitelist; Quiet should let pi use its default available tool set.

## Model Settings

Default settings:

- Language: `en`
- Provider: `deepseek`
- Model: `deepseek-v4-flash`
- Thinking: `medium`

Settings can be overridden by app settings/UserDefaults and environment variables:

- `QUIET_MODEL_PROVIDER`
- `QUIET_MODEL_ID`
- `QUIET_MODEL_API_KEY`
- `QUIET_THINKING_LEVEL`

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
node --check Sources/QuietMenuBar/Resources/pi-agent/server.mjs
./scripts/package-quiet-app.sh
open dist/Quiet.app
```

After each code change, stop any previously running development/preview instance of Quiet, then start a fresh preview with `swift run quiet` so the user is always looking at the latest build. For this status-bar app, do not treat a short-lived background launch, `nohup swift run quiet`, or direct `.build/.../quiet` execution as a successful preview unless you verify the app process is still alive and the status-bar icon is visible. Do not launch the packaged `.app` for ordinary development previews, and do not leave stale dev processes running in the background.

If testing packaging, remember the packaged app launches its embedded Node from:

`dist/Quiet.app/Quiet_QuietMenuBar.bundle/Resources/node`

## Safety Notes

- Preserve user files and old project directories when moving or renaming paths.
- Do not delete `~/.quiet` data during ordinary development.
- Prefer small, native AppKit/SwiftUI changes over adding web or Electron dependencies.
- If updating `.codex` project records for a path migration, update full absolute path references carefully.
