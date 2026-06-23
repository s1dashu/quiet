<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./assets/app-icon/quiet-icon-1024.png">
    <img alt="Quiet" src="./assets/app-icon/quiet-icon-1024.png" width="128" height="128">
  </picture>
</p>

<h1 align="center">Quiet</h1>

<p align="center">
  <strong>A native macOS menu-bar app that organizes files, links, snippets, and loose resources locally.<br>Drop in the mess. Get back your calm.</strong>
</p>

<p align="center">
  <a href="https://github.com/s1dashu/quiet/releases"><img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&style=flat" alt="macOS 14+"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://swiftpackageindex.com"><img src="https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift&style=flat" alt="Swift 6.0"></a>
</p>

---

## What is Quiet?

Quiet is a tiny menu-bar app for macOS that tidies files, links, snippets, and saved references so you don't have to.

You drag files and folders onto its icon, or paste links and text directly into the window. Quiet figures out what they are, places new drops in a visible Johnny.Decimal inbox, and moves everything into a clean numbered folder system on your own Mac. No account, no Quiet-hosted cloud, and no telemetry.

It's like a smart `~/Documents` that absorbs loose resources and sorts itself from the menu bar.

<video src="./landing/assets/quiet-demo.mp4" width="100%" autoplay muted loop playsinline controls></video>

## Why Quiet?

| Problem | Quiet's answer |
| --- | --- |
| Downloads folder is a graveyard | Drag it in. Quiet sorts by type, date, or your own rules. |
| Links and copied notes scatter across apps | Paste them in. Quiet captures each item as a local resource. |
| Screenshots pile up on your desktop | Drop them anytime. Quiet files them without you opening Finder. |
| You have an organizing system in your head | Tell Quiet once. It remembers and keeps doing it. |
| "AI organizers" want your files in the cloud | Quiet stores and organizes resources locally, under folders you control. |
| Electron apps feel sluggish and heavy | Quiet is built with Swift + AppKit. It starts instantly and uses almost no memory. |

## How It Works

```
You drop files, paste links, or paste snippets
              │
              ▼
    Quiet places them in 00.01 Inbox for the system
              │
              ▼
    The local agent inspects content, follows your rules,
    and moves everything into ~/Documents/Quiet/<area>/<category>/<AC.ID>
              │
              ▼
    Done. Your resources are organized. You got a summary.
```

1. **Drop or paste anything** — files, folders, screenshots, archives, URLs, notes, prompts, and copied references.
2. **Quiet understands them** — it reads filenames, saved link files, snippets, and content to decide where each resource belongs.
3. **Everything lands in `~/Documents/Quiet`** — new installs first ask whether you prefer PARA, Johnny.Decimal, or your own custom organizing method. Johnny.Decimal mode creates the numbered area/category skeleton and the system inbox, but it does not pre-create every category's standard-zero folders.

If you tell Quiet "I like links sorted by research topic," it writes that rule to `~/.quiet/memory.md`. From then on, it follows your preference automatically.

## Features

### 🧘‍♂️ Drag and forget
Drop files, paste links, or paste snippets and go back to your work. Quiet handles categorization, naming, and placement in the background. No Finder windows, no manual sorting.

### 🪟 Native macOS experience
Quiet isn't a web app in a shell. It's built with Swift, SwiftUI, and AppKit. This experiment uses a solid black native menu-bar window for dependable contrast across wallpapers, starts with your Mac, and sits at a few megabytes of memory.

### 🔒 Local-first
Quiet bundles its own Node runtime so you don't even need Node installed. Resources stay in `~/Documents/Quiet`, runtime data stays in `~/.quiet`, and Quiet does not collect telemetry or analytics.

Quiet uses the model provider you configure in Settings. If you choose a remote provider, prompts and resource-derived context needed for the task may be sent to that provider. Quiet does not run a hosted backend or upload your files to a Quiet-owned server.

### 📝 Remembers your preferences
When you tell Quiet how you like things organized, it writes your rules to a plain Markdown file at `~/.quiet/memory.md`. Edit it anytime. It's just a text file you own.

### 💬 Built-in chat interface
Want more than capture? Open the Quiet window and chat directly with the agent. Ask it to reorganize a folder, clean up duplicates, or follow a new naming convention.

## Installation

### Option 1 — Download the app

Download the latest `Quiet.zip` or `Quiet.dmg` from [Releases](https://github.com/s1dashu/quiet/releases), unzip or mount it, and drag `Quiet.app` to your Applications folder.

Quiet comes with everything bundled — no dependencies to install.

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
open dist/Quiet.app
```

The packaged app embeds Node automatically. End users don't need anything installed.

## Configuration

### API Key

Quiet needs an API key from your model provider to work. Open the Settings panel inside the app, paste your key, and you're done. The key is stored locally at `~/.quiet/secrets.json` with user-only file permissions.

### Organizing rules

Quiet reads `~/.quiet/memory.md` for your resource-organizing preferences. This file is created automatically, and you can edit it directly. The agent also updates it when you express durable preferences during chat.

```markdown
# Quiet Memory

## Method Initialization
Status: uninitialized

Quiet will ask whether you prefer PARA, Johnny.Decimal, or a custom method.

## Candidate Method: PARA
- Projects, Areas, Resources, Archives.

## Candidate Method: Johnny.Decimal
- Areas, categories, and specific AC.ID content folders.
- Quiet does not automatically create AC.00/01/02/03/04/09 inside every category.
```

## Under the Hood

| Layer | Technology |
| --- | --- |
| UI | Swift, SwiftUI, AppKit, native black menu-bar window |
| Agent runtime | Bundled Node.js + `@earendil-works/pi-coding-agent` |
| IPC | JSON Lines over stdin/stdout |
| File system | `~/Documents/Quiet` (user resources), `~/.quiet` (runtime data) |
| Build | Swift Package Manager + shell packaging script |

Quiet launches the Node agent as a child process and communicates with it via JSONL over stdin/stdout. The agent uses the pi-coding-agent framework with the AI provider of your choice. Resource inboxing, organization, memory, and session data are local; model requests go to the provider you configure.

## Philosophy

- **Files should stay local.** Your documents don't belong in an app-owned cloud.
- **Tools should feel native.** If it's a Mac app, it should look and behave like one.
- **Your rules, your file.** Preferences live in plain Markdown. No proprietary formats, no vendor lock-in.
- **Zero telemetry.** Quiet does not collect analytics or usage data.

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
