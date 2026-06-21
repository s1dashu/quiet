<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./assets/app-icon/quiet-icon-1024.png">
    <img alt="Blackhole" src="./assets/app-icon/quiet-icon-1024.png" width="128" height="128">
  </picture>
</p>

<h1 align="center">Blackhole</h1>

<p align="center">
  <strong>A native macOS menu-bar app that organizes files, links, snippets, and loose resources locally.<br>Drop in the mess. Get back your calm.</strong>
</p>

<p align="center">
  <a href="https://github.com/s1dashu/quiet/releases"><img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&style=flat" alt="macOS 14+"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://swiftpackageindex.com"><img src="https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift&style=flat" alt="Swift 6.0"></a>
</p>

---

## What is Blackhole?

Blackhole is a tiny menu-bar app for macOS that tidies files, links, snippets, and saved references so you don't have to.

You drag files and folders onto its icon, or paste links and text directly into the window. Blackhole figures out what they are, captures them into an inbox, and moves everything to a clean, organized folder on your own Mac. No account, no Blackhole-hosted cloud, and no telemetry.

It's like a smart `~/Documents` that absorbs loose resources and sorts itself from the menu bar.

<video src="./landing/assets/quiet-demo.mp4" width="100%" autoplay muted loop playsinline controls></video>

## Why Blackhole?

| Problem | Blackhole's answer |
| --- | --- |
| Downloads folder is a graveyard | Drag it in. Blackhole sorts by type, date, or your own rules. |
| Links and copied notes scatter across apps | Paste them in. Blackhole captures each item as an inbox resource. |
| Screenshots pile up on your desktop | Drop them anytime. Blackhole files them without you opening Finder. |
| You have an organizing system in your head | Tell Blackhole once. It remembers and keeps doing it. |
| "AI organizers" want your files in the cloud | Blackhole stores and organizes resources locally, under folders you control. |
| Electron apps feel sluggish and heavy | Blackhole is built with Swift + AppKit. It starts instantly and uses almost no memory. |

## How It Works

```
You drop files, paste links, or paste snippets
              │
              ▼
    Blackhole ingests them into ~/Documents/Blackhole/Inbox
              │
              ▼
    The local agent inspects content, follows your rules,
    and moves everything into ~/Documents/Blackhole/Files
              │
              ▼
    Done. Your resources are organized. You got a summary.
```

1. **Drop or paste anything** — files, folders, screenshots, archives, URLs, notes, prompts, and copied references.
2. **Blackhole understands them** — it reads filenames, saved link files, snippets, and content to decide where each resource belongs.
3. **Everything lands in `~/Documents/Blackhole/Files`** — a single, clean home for organized resources that you control.

If you tell Blackhole "I like links sorted by research topic," it writes that rule to `~/.blackhole/memory.md`. From then on, it follows your preference automatically.

## Features

### 🧘‍♂️ Drag and forget
Drop files, paste links, or paste snippets and go back to your work. Blackhole handles categorization, naming, and placement in the background. No Finder windows, no manual sorting.

### 🪟 Native macOS experience
Blackhole isn't a web app in a shell. It's built with Swift, SwiftUI, and AppKit. This experiment uses a solid black native menu-bar window for dependable contrast across wallpapers, starts with your Mac, and sits at a few megabytes of memory.

### 🔒 Local-first
Blackhole bundles its own Node runtime so you don't even need Node installed. Resources stay in `~/Documents/Blackhole`, runtime data stays in `~/.blackhole`, and Blackhole does not collect telemetry or analytics.

Blackhole uses the model provider you configure in Settings. If you choose a remote provider, prompts and resource-derived context needed for the task may be sent to that provider. Blackhole does not run a hosted backend or upload your files to a Blackhole-owned server.

### 📝 Remembers your preferences
When you tell Blackhole how you like things organized, it writes your rules to a plain Markdown file at `~/.blackhole/memory.md`. Edit it anytime. It's just a text file you own.

### 💬 Built-in chat interface
Want more than capture? Open the Blackhole window and chat directly with the agent. Ask it to reorganize a folder, clean up duplicates, or follow a new naming convention.

## Installation

### Option 1 — Download the app

Download the latest `Blackhole.zip` or `Blackhole.dmg` from [Releases](https://github.com/s1dashu/quiet/releases), unzip or mount it, and drag `Blackhole.app` to your Applications folder.

Blackhole comes with everything bundled — no dependencies to install.

### Option 2 — Build from source

```bash
# Prerequisites: Xcode 16+, Node 22+ (only for development builds)
git clone https://github.com/s1dashu/quiet.git
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
open dist/Blackhole.app
```

The packaged app embeds Node automatically. End users don't need anything installed.

## Configuration

### API Key

Blackhole needs an API key from your model provider to work. Open the Settings panel inside the app, paste your key, and you're done. The key is stored locally in the macOS Keychain.

### Organizing rules

Blackhole reads `~/.blackhole/memory.md` for your resource-organizing preferences. This file is created automatically, and you can edit it directly. The agent also updates it when you express durable preferences during chat.

```markdown
# Blackhole Memory

## Folder Taxonomy
- Images → Images/
- Documents → Documents/
- Screenshots → Screenshots/
- Spreadsheets → Sheets/
```

## Under the Hood

| Layer | Technology |
| --- | --- |
| UI | Swift, SwiftUI, AppKit, native black menu-bar window |
| Agent runtime | Bundled Node.js + `@earendil-works/pi-coding-agent` |
| IPC | JSON Lines over stdin/stdout |
| File system | `~/Documents/Blackhole` (user resources), `~/.blackhole` (runtime data) |
| Build | Swift Package Manager + shell packaging script |

Blackhole launches the Node agent as a child process and communicates with it via JSONL over stdin/stdout. The agent uses the pi-coding-agent framework with the AI provider of your choice. Resource staging, organization, memory, and session data are local; model requests go to the provider you configure.

## Philosophy

- **Files should stay local.** Your documents don't belong in an app-owned cloud.
- **Tools should feel native.** If it's a Mac app, it should look and behave like one.
- **Your rules, your file.** Preferences live in plain Markdown. No proprietary formats, no vendor lock-in.
- **Zero telemetry.** Blackhole does not collect analytics or usage data.

## Contributing

Contributions are welcome! Start with [CONTRIBUTING.md](./CONTRIBUTING.md). Agent-facing architecture notes live in [AGENTS.md](./AGENTS.md).

Before opening a PR:
- Run `swift build` and verify it compiles cleanly
- Run `node --check Sources/QuietMenuBar/Resources/pi-agent/server.mjs` to validate the agent
- Run `npm audit --omit=dev --registry=https://registry.npmjs.org`
- Keep UI changes native (no Electron, no web views)

## License

MIT © [Sida](https://github.com/s1dashu)

---

<p align="center">
  <sub>Built with ❤️ for Mac. No cloud strings attached.</sub>
</p>
