<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./quiet-icon-iOS-Default-1024@1x.png">
    <img alt="Quiet" src="./quiet-icon-iOS-Default-1024@1x.png" width="128" height="128">
  </picture>
</p>

<h1 align="center">Quiet</h1>

<p align="center">
  <strong>A native macOS menu-bar app that organizes your files locally.<br>Drop in the mess. Get back your calm.</strong>
</p>

<p align="center">
  <a href="https://github.com/sida/quiet/releases"><img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&style=flat" alt="macOS 14+"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://swiftpackageindex.com"><img src="https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift&style=flat" alt="Swift 6.0"></a>
</p>

---

## What is Quiet?

Quiet is a tiny menu-bar app for macOS that tidies your files so you don't have to.

You drag files, folders, or screenshots onto its icon. Quiet figures out what they are, renames the chaos, and moves everything to a clean, organized folder — all on your own Mac. No cloud. No accounts. No one else's server ever touches your documents.

It's like a smart `~/Documents` that sorts itself, sitting quietly in your menu bar.

<img src="./landing/assets/quiet-demo.mp4" width="100%" alt="Quiet demo">

## Why Quiet?

| Problem | Quiet's answer |
| --- | --- |
| Downloads folder is a graveyard | Drag it in. Quiet sorts by type, date, or your own rules. |
| Screenshots pile up on your desktop | Drop them anytime. Quiet files them without you opening Finder. |
| You have an organizing system in your head | Tell Quiet once. It remembers and keeps doing it. |
| "AI organizers" want your files in the cloud | Quiet runs 100% locally. Your files never leave your machine. |
| Electron apps feel sluggish and heavy | Quiet is built with Swift + AppKit. It starts instantly and uses almost no memory. |

## How It Works

```
You drag files onto the menu bar icon
              │
              ▼
    Quiet ingests them into ~/Documents/Quiet/Inbox
              │
              ▼
    The local agent inspects content, follows your rules,
    and moves everything into ~/Documents/Quiet/Files
              │
              ▼
    Done. Your files are organized. You got a summary.
```

1. **Drop anything** — individual files, folders full of mixed content, screenshots, archives.
2. **Quiet understands them** — it reads filenames and content to decide where each file belongs.
3. **Everything lands in `~/Documents/Quiet/Files`** — a single, clean home for organized files that you control.

If you tell Quiet "I like images sorted by year → project," it writes that rule to `~/.quiet/memory.md`. From then on, it follows your preference automatically.

## Features

### 🧘‍♂️ Drag and forget
Drop files and go back to your work. Quiet handles categorization, naming, and placement in the background. No Finder windows, no manual sorting.

### 🪟 Native macOS experience
Quiet isn't a web app in a shell. It's built with Swift, SwiftUI, and AppKit. The menu-bar window uses real system materials (`NSGlassEffectView` / `NSVisualEffectView`), starts with your Mac, and sits at a few megabytes of memory.

### 🔒 Fully local
Everything runs on your machine. Quiet bundles its own Node runtime so you don't even need Node installed. Files stay in `~/Documents/Quiet`. No telemetry, no analytics, no network requests to third parties.

### 📝 Remembers your preferences
When you tell Quiet how you like things organized, it writes your rules to a plain Markdown file at `~/.quiet/memory.md`. Edit it anytime. It's just a text file you own.

### 💬 Built-in chat interface
Want more than drag-and-drop? Open the Quiet window and chat directly with the agent. Ask it to reorganize a folder, clean up duplicates, or follow a new naming convention.

## Installation

### Option 1 — Download the app

Download the latest `Quiet.zip` from [Releases](https://github.com/sida/quiet/releases), unzip, and drag `Quiet.app` to your Applications folder.

Quiet comes with everything bundled — no dependencies to install.

### Option 2 — Build from source

```bash
# Prerequisites: Xcode 16+, Node 22+ (only for development builds)
git clone https://github.com/sida/quiet.git
cd quiet

# Install Node dependencies for the agent backend
npm install

# Build the Swift app
swift build

# Run
swift run quiet
```

To produce a standalone `.app` bundle:

```bash
./scripts/package-quiet-app.sh
open dist/Quiet.app
```

The packaged app embeds Node automatically. End users don't need anything installed.

## Configuration

Quiet works out of the box with sensible defaults. To customize:

### Model settings

Set via environment variables or the in-app Settings panel:

| Variable | Default | Description |
| --- | --- | --- |
| `QUIET_MODEL_PROVIDER` | `deepseek` | Model provider |
| `QUIET_MODEL_ID` | `deepseek-v4-flash` | Model identifier |
| `QUIET_MODEL_API_KEY` | — | Your API key |
| `QUIET_THINKING_LEVEL` | `medium` | Thinking depth: `off`, `minimal`, `low`, `medium`, `high`, `xhigh` |
| `QUIET_LANGUAGE` | `en` | UI language: `en` or `zh` |

### Organizing rules

Quiet reads `~/.quiet/memory.md` for your file-organizing preferences. This file is created automatically, and you can edit it directly. The agent also updates it when you express durable preferences during chat.

```markdown
# Quiet Memory

## Folder Taxonomy
- Images → Images/
- Documents → Documents/
- Screenshots → Screenshots/
- Spreadsheets → Sheets/
```

## Under the Hood

| Layer | Technology |
| --- | --- |
| UI | Swift, SwiftUI, AppKit, `NSGlassEffectView` |
| Agent runtime | Bundled Node.js + `@earendil-works/pi-coding-agent` |
| IPC | JSON Lines over stdin/stdout |
| File system | `~/Documents/Quiet` (user files), `~/.quiet` (runtime data) |
| Build | Swift Package Manager + shell packaging script |

Quiet launches the Node agent as a child process and communicates with it via JSONL over stdin/stdout. The agent uses the pi-coding-agent framework with the AI provider of your choice — all processing happens locally on your machine.

## Philosophy

- **Files should stay local.** Your documents don't belong on someone else's server.
- **Tools should feel native.** If it's a Mac app, it should look and behave like one.
- **Your rules, your file.** Preferences live in plain Markdown. No proprietary formats, no vendor lock-in.
- **Zero telemetry.** Quiet doesn't phone home. It's your app on your machine.

## Contributing

Contributions are welcome! Check the [AGENTS.md](./AGENTS.md) for architecture notes and development guidelines.

Before opening a PR:
- Run `swift build` and verify it compiles cleanly
- Run `node --check Sources/QuietMenuBar/Resources/pi-agent/server.mjs` to validate the agent
- Keep UI changes native (no Electron, no web views)

## License

MIT © [Sida](https://github.com/sida)

---

<p align="center">
  <sub>Built with ❤️ for Mac. No cloud strings attached.</sub>
</p>
