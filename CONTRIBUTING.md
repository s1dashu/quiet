# Contributing to Quiet

Thanks for helping improve Quiet. This is a native macOS menu-bar app, so changes should preserve the lightweight AppKit + SwiftUI shape of the project.

## Development Setup

Prerequisites:

- macOS 14+
- Xcode 16+
- Node 22+

```sh
npm install
swift build
swift run quiet
```

To build a standalone app bundle:

```sh
./scripts/package-quiet-app.sh
```

Use `CONFIGURATION=debug ./scripts/package-quiet-app.sh` when you need a debug bundle.

## Checks

Before opening a PR, run:

```sh
swift build
node --check Sources/QuietMenuBar/Resources/pi-agent/server.mjs
npm audit --omit=dev --registry=https://registry.npmjs.org
```

## Project Boundaries

- Keep the app native. Do not add Electron or webview UI dependencies.
- Treat `Sources/QuietMenuBar/main.swift` as the active app entry point.
- Keep generated build output out of git: `.build/`, `dist/`, and `node_modules/`.
- User files should remain under `~/Documents/Quiet/Files` unless a user explicitly chooses a different policy.
- Runtime data belongs under `~/.quiet`.

## Privacy Expectations

Quiet should not add telemetry, analytics, or a Quiet-hosted backend. Model requests may go to the provider configured by the user, and UI copy should describe that boundary clearly.
