import AppKit
import LucideIcons
import MarkdownUI
import SwiftUI
import UniformTypeIdentifiers

private let neatAppName = "Neat"
private let neatWindowDefaultSize = NSSize(width: 380, height: 520)
private let neatWindowMinimumSize = NSSize(width: 340, height: 420)
private let messageBottomAnchorId = "message-bottom-anchor"
private let neatDropTypeIdentifiers = [
    UTType.fileURL.identifier,
    UTType.url.identifier,
]
private let neatChatText = Color(red: 0.14, green: 0.12, blue: 0.10)
private let neatChatMutedText = neatChatText.opacity(0.62)

private extension Notification.Name {
    static let neatFocusComposer = Notification.Name("NeatFocusComposer")
}

private func fileURL(fromDropItem item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url.isFileURL ? url : nil
    }
    if let url = item as? NSURL {
        let bridged = url as URL
        return bridged.isFileURL ? bridged : nil
    }
    if let data = item as? Data,
       let url = URL(dataRepresentation: data, relativeTo: nil) {
        return url.isFileURL ? url : nil
    }
    if let text = item as? String {
        if let url = URL(string: text), url.isFileURL {
            return url
        }
        if text.hasPrefix("/") {
            return URL(fileURLWithPath: text)
        }
    }
    return nil
}

struct LucideIcon: View {
    let id: String
    let fallbackSystemName: String

    var body: some View {
        if let image = NSImage.image(lucideId: id) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: fallbackSystemName)
                .resizable()
                .scaledToFit()
        }
    }
}

struct GlassIconBacking: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glassEffectView = NSGlassEffectView()
            glassEffectView.style = .clear
            glassEffectView.cornerRadius = cornerRadius
            glassEffectView.tintColor = nil
            glassEffectView.wantsLayer = true
            glassEffectView.layer?.cornerRadius = cornerRadius
            glassEffectView.layer?.cornerCurve = .continuous
            glassEffectView.layer?.masksToBounds = true
            glassEffectView.layer?.borderWidth = 0
            return glassEffectView
        }

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .underWindowBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.cornerCurve = .continuous
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.backgroundColor = NSColor.clear.cgColor
        visualEffectView.layer?.borderWidth = 0
        return visualEffectView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *),
           let glassEffectView = nsView as? NSGlassEffectView {
            glassEffectView.cornerRadius = cornerRadius
            glassEffectView.layer?.cornerRadius = cornerRadius
        } else if let visualEffectView = nsView as? NSVisualEffectView {
            visualEffectView.layer?.cornerRadius = cornerRadius
        }
    }
}

struct GlassIconButtonLabel: View {
    let iconId: String
    let fallbackSystemName: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 14
    var cornerRadius: CGFloat? = nil

    var body: some View {
        let radius = cornerRadius ?? size / 2
        LucideIcon(id: iconId, fallbackSystemName: fallbackSystemName)
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: iconSize, height: iconSize)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white.opacity(0.001))
                    .background {
                        GlassIconBacking(cornerRadius: radius)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(.white.opacity(0.30), lineWidth: 0.7)
                    }
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.34), .white.opacity(0.04), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(color: .black.opacity(0.13), radius: 2.5, x: 0, y: 1)
            .shadow(color: .white.opacity(0.16), radius: 1, x: 0, y: -0.5)
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
        case system
        case tool
    }

    enum ToolStatus: Equatable {
        case running
        case finished
        case failed
    }

    enum MessageStatus: Equatable {
        case streaming
        case finished
    }

    let id: String
    let role: Role
    var text: String
    var toolName = ""
    var toolSummary = ""
    var toolResult = ""
    var toolStatus: ToolStatus = .finished
    var toolExpanded = false
    var messageStatus: MessageStatus = .finished
}

final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func paths() -> [String] {
        lock.lock()
        let paths = urls.map(\.path).sorted()
        lock.unlock()
        return paths
    }
}

@MainActor
final class AgentStore: ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            text: "把文件拖进来，Neat 会先放入 ~/.neat/inbox，再由 pi 整理到 ~/.neat/files。创作内容会写到 ~/.neat/output。"
        )
    ]
    @Published var inputText = ""
    @Published var status = "启动中"
    @Published var isAgentReady = false
    @Published var isAgentWorking = false
    @Published var showTurnWaitIndicator = false
    @Published var lastDroppedPaths: [String] = []
    @Published var filesPath = ""
    @Published var modelProvider: String
    @Published var modelId: String
    @Published var thinkingLevel: String

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()
    private var assistantMessageIdsByAgentId: [String: String] = [:]
    private var toolMessageIdsByToolId: [String: String] = [:]
    private var turnWaitTask: Task<Void, Never>?
    private var isRestartingAgent = false

    init() {
        modelProvider = UserDefaults.standard.string(forKey: "neat.model.provider") ?? "deepseek"
        modelId = UserDefaults.standard.string(forKey: "neat.model.id") ?? "deepseek-v4-flash"
        thinkingLevel = UserDefaults.standard.string(forKey: "neat.thinking.level") ?? "medium"
        startAgent()
    }

    deinit {
        process?.terminate()
    }

    func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !lastDroppedPaths.isEmpty else { return }
        inputText = ""
        send(text: text, paths: lastDroppedPaths)
        lastDroppedPaths = []
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let collector = DroppedURLCollector()
        let group = DispatchGroup()
        var requestedFileURLs = false

        for provider in providers {
            guard let typeIdentifier = neatDropTypeIdentifiers.first(where: {
                provider.hasItemConformingToTypeIdentifier($0)
            }) else {
                continue
            }
            requestedFileURLs = true
            group.enter()
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = fileURL(fromDropItem: item) {
                    collector.append(url)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let paths = collector.paths()
            guard !paths.isEmpty else {
                self?.messages.append(ChatMessage(
                    id: UUID().uuidString,
                    role: .system,
                    text: "没有读到可整理的文件路径。请从 Finder 直接拖入文件或文件夹。"
                ))
                return
            }
            self?.lastDroppedPaths = []
            self?.send(text: "自动整理这些文件", paths: paths)
        }

        return requestedFileURLs
    }

    private func startAgent() {
        guard let agentURL = Bundle.module.url(
            forResource: "server",
            withExtension: "mjs",
            subdirectory: "pi-agent"
        ) else {
            status = "找不到 agent/server.mjs"
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        if let bundledNode = bundledNodeURL() {
            process.executableURL = bundledNode
            process.arguments = [agentURL.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", agentURL.path]
        }
        if let projectDirectory = projectDirectoryURL() {
            process.currentDirectoryURL = projectDirectory
        }

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        var environment = ProcessInfo.processInfo.environment
        environment.merge([
            "NODE_ENV": environment["NODE_ENV"] ?? "production",
            "NEAT_HOME": applicationSupportDirectory().path,
            "NEAT_MODEL_PROVIDER": modelProvider.trimmingCharacters(in: .whitespacesAndNewlines),
            "NEAT_MODEL_ID": modelId.trimmingCharacters(in: .whitespacesAndNewlines),
            "NEAT_THINKING_LEVEL": thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines),
            "PI_AGENT_HOME": applicationSupportDirectory().path,
            "PATH": mergedPath(),
        ]) { _, new in new }
        if let projectDirectory = projectDirectoryURL() {
            environment["NEAT_PROJECT_ROOT"] = projectDirectory.path
        }
        process.environment = environment

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in
                self?.consumeOutput(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.status = "agent stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard self?.isRestartingAgent != true else { return }
                self?.isAgentReady = false
                self?.status = "agent 已退出：\(process.terminationStatus)"
            }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = inputPipe
            isRestartingAgent = false
            status = "连接 agent 中"
        } catch {
            isRestartingAgent = false
            status = "启动失败：\(error.localizedDescription)"
            messages.append(ChatMessage(id: UUID().uuidString, role: .system, text: status))
        }
    }

    private func send(text: String, paths: [String]) {
        if !text.isEmpty {
            messages.append(ChatMessage(id: UUID().uuidString, role: .user, text: text))
        }
        if !paths.isEmpty {
            let fileText = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "、")
            messages.append(ChatMessage(id: UUID().uuidString, role: .system, text: "已拖入：\(fileText)"))
        }

        let payload: [String: Any] = [
            "type": "user_message",
            "text": text,
            "paths": paths,
        ]
        isAgentWorking = true
        updateTurnWaitIndicator()
        writeJSONLine(payload)
    }

    private func writeJSONLine(_ payload: [String: Any]) {
        guard let inputPipe else { return }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line.append("\n")
        inputPipe.fileHandleForWriting.write(Data(line.utf8))
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)

        while let newlineRange = outputBuffer.firstRange(of: Data([0x0A])) {
            let lineData = outputBuffer.subdata(in: outputBuffer.startIndex..<newlineRange.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex...newlineRange.lowerBound)
            guard !lineData.isEmpty else { continue }
            handleAgentLine(lineData)
        }
    }

    private func handleAgentLine(_ lineData: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            isAgentReady = true
            filesPath = object["filesRoot"] as? String ?? filesPath
            status = "agent 就绪"
        case "status":
            status = object["value"] as? String ?? status
            if status.contains("完成") || status.contains("撤回完成") || status.contains("失败") {
                isAgentWorking = false
                updateTurnWaitIndicator()
            } else if status.contains("正在") || status.contains("理解") || status.contains("整理") || status.contains("工作中") {
                isAgentWorking = true
                updateTurnWaitIndicator()
            }
        case "assistant_start":
            isAgentWorking = true
            let agentId = object["id"] as? String ?? UUID().uuidString
            let messageId = UUID().uuidString
            assistantMessageIdsByAgentId[agentId] = messageId
            messages.append(ChatMessage(id: messageId, role: .assistant, text: "", messageStatus: .streaming))
            updateTurnWaitIndicator()
        case "assistant_delta":
            guard let agentId = object["id"] as? String,
                  let messageId = assistantMessageIdsByAgentId[agentId],
                  let delta = object["text"] as? String,
                  let index = messages.firstIndex(where: { $0.id == messageId }) else {
                return
            }
            messages[index].text += delta
            messages[index].messageStatus = .streaming
            updateTurnWaitIndicator()
        case "assistant_done":
            if let agentId = object["id"] as? String,
               let messageId = assistantMessageIdsByAgentId[agentId],
               let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].messageStatus = .finished
            }
            updateTurnWaitIndicator()
        case "plan":
            break
        case "organized":
            if let filesRoot = object["filesRoot"] as? String {
                filesPath = filesRoot
            }
        case "tool_start":
            isAgentWorking = true
            let id = object["id"] as? String ?? UUID().uuidString
            let name = object["name"] as? String ?? "tool"
            let summary = summarizeToolArgs(name: name, value: object["args"])
            let messageId = UUID().uuidString
            toolMessageIdsByToolId[id] = messageId
            messages.append(ChatMessage(
                id: messageId,
                role: .tool,
                text: summary,
                toolName: name,
                toolSummary: summary,
                toolStatus: .running,
                toolExpanded: shouldAutoExpandTool(name)
            ))
            updateTurnWaitIndicator()
        case "tool_update":
            status = "agent 工作中"
            if let id = object["id"] as? String,
               let messageId = toolMessageIdsByToolId[id],
               let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].toolStatus = .running
            }
            updateTurnWaitIndicator()
        case "tool_end":
            let id = object["id"] as? String ?? UUID().uuidString
            let name = object["name"] as? String ?? "tool"
            let isError = object["isError"] as? Bool ?? false
            let result = summarizeToolResult(object["result"])
            if let messageId = toolMessageIdsByToolId[id],
               let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].toolStatus = isError ? .failed : .finished
                messages[index].toolResult = result
                if !result.isEmpty {
                    messages[index].text = result
                }
                autoCollapseToolIfNeeded(messageId: messageId, name: name)
            } else {
                messages.append(ChatMessage(
                    id: UUID().uuidString,
                    role: .tool,
                    text: result,
                    toolName: name,
                    toolSummary: "",
                    toolResult: result,
                    toolStatus: isError ? .failed : .finished,
                    toolExpanded: false
                ))
            }
            updateTurnWaitIndicator()
        case "thinking_start":
            isAgentWorking = true
            status = "agent 工作中"
            updateTurnWaitIndicator()
        case "thinking_delta":
            isAgentWorking = true
            status = "agent 工作中"
            updateTurnWaitIndicator()
        case "thinking_end":
            updateTurnWaitIndicator()
        case "error":
            isAgentWorking = false
            updateTurnWaitIndicator()
            let message = object["message"] as? String ?? "未知错误"
            messages.append(ChatMessage(id: UUID().uuidString, role: .system, text: "agent error: \(message)"))
        default:
            break
        }
    }

    private func bundledNodeURL() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("node"),
            Bundle.module.resourceURL?.appendingPathComponent("node"),
            Bundle.module.resourceURL?.appendingPathComponent("Resources/node"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func mergedPath() -> String {
        let defaults = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/Users/sida/.local/share/mise/installs/node/lts/bin",
        ]
        let inherited = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        return (defaults + inherited).reduce(into: [String]()) { paths, path in
            if !paths.contains(path) {
                paths.append(path)
            }
        }.joined(separator: ":")
    }

    private func applicationSupportDirectory() -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".neat", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("inbox", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("files", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("output", isDirectory: true), withIntermediateDirectories: true)
        return url
    }

    private func projectDirectoryURL() -> URL? {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let sourceRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("Package.swift").path) else {
            return nil
        }
        return sourceRoot
    }

    func openFiles() {
        let path = filesPath.isEmpty ? applicationSupportDirectory().appendingPathComponent("files", isDirectory: true).path : filesPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func openMemoryFile() {
        let url = applicationSupportDirectory().appendingPathComponent("memory.md", isDirectory: false)
        if !FileManager.default.fileExists(atPath: url.path) {
            let defaultMemory = """
            # Neat Memory

            These are user-editable file organizing rules for Neat.

            ## Learning User Preferences

            - When the user expresses a stable preference for how files should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
            - Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
            - Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
            - This file is located at `NEAT_HOME/memory.md`; you may edit it with bash when updating remembered organizing preferences.

            ## Folder Taxonomy

            - Images: png, jpg, jpeg, gif, webp, heic, tiff, svg, psd, ai, sketch, fig
            - Documents: pdf, doc, docx, txt, md, rtf, pages, epub
            - Sheets: xls, xlsx, csv, numbers
            - Slides: ppt, pptx, key
            - Archives: zip, rar, 7z, tar, gz, dmg, pkg
            - Code: js, jsx, ts, tsx, mjs, cjs, py, rb, go, rs, swift, java, kt, html, css, json, yaml, yml, toml, sh
            - Audio: mp3, wav, aac, flac, m4a
            - Video: mp4, mov, avi, mkv, webm
            - Folders: directories
            - Other: everything else

            ## Destination Pattern

            `NEAT_HOME/files/<category>/<YYYY-MM>/<original-name>`

            ## Conversation Style

            - Be concise.
            - Tell the user what was moved and where.
            - When a problem occurs, name the failed file and continue with the rest.
            - Do not mention internal logs, manifests, or implementation files unless the user asks.
            """
            try? defaultMemory.appending("\n").write(to: url, atomically: true, encoding: .utf8)
        } else if let memory = try? String(contentsOf: url, encoding: .utf8),
                  !memory.contains("## Learning User Preferences") {
            let guidance = """

            ## Learning User Preferences

            - When the user expresses a stable preference for how files should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
            - Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
            - Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
            - This file is located at `NEAT_HOME/memory.md`; you may edit it with bash when updating remembered organizing preferences.
            """
            try? memory.trimmingCharacters(in: .whitespacesAndNewlines)
                .appending("\n")
                .appending(guidance)
                .appending("\n")
                .write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    func saveModelSettings(provider: String, model: String, thinking: String) {
        let nextProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextThinking = thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextProvider.isEmpty, !nextModel.isEmpty else { return }

        modelProvider = nextProvider
        modelId = nextModel
        thinkingLevel = nextThinking.isEmpty ? "medium" : nextThinking
        UserDefaults.standard.set(modelProvider, forKey: "neat.model.provider")
        UserDefaults.standard.set(modelId, forKey: "neat.model.id")
        UserDefaults.standard.set(thinkingLevel, forKey: "neat.thinking.level")
        restartAgent()
    }

    private func restartAgent() {
        isRestartingAgent = true
        isAgentReady = false
        isAgentWorking = false
        showTurnWaitIndicator = false
        status = "正在切换模型"
        inputPipe = nil
        process?.terminate()
        process = nil
        startAgent()
    }

    func toggleToolMessage(id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id && $0.role == .tool }) else { return }
        messages[index].toolExpanded.toggle()
    }

    private func shouldAutoExpandTool(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized == "write"
            || normalized == "edit"
            || normalized == "multi_edit"
            || normalized.contains("write")
            || normalized.contains("edit")
    }

    private func autoCollapseToolIfNeeded(messageId: String, name: String) {
        guard shouldAutoExpandTool(name) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self,
                  let index = self.messages.firstIndex(where: { $0.id == messageId }),
                  self.messages[index].role == .tool,
                  self.messages[index].toolStatus != .running else {
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.messages[index].toolExpanded = false
            }
        }
    }

    private func updateTurnWaitIndicator() {
        let shouldShow = isAgentWorking && !hasActiveStreamingItem
        turnWaitTask?.cancel()
        if !shouldShow {
            showTurnWaitIndicator = false
            return
        }
        turnWaitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.showTurnWaitIndicator = self.isAgentWorking && !self.hasActiveStreamingItem
            }
        }
    }

    private var hasActiveStreamingItem: Bool {
        messages.contains { message in
            switch message.role {
            case .assistant:
                message.messageStatus == .streaming
            case .tool:
                message.toolStatus == .running
            case .user, .system:
                false
            }
        }
    }

    private func summarizeToolArgs(name: String, value: Any?) -> String {
        guard let dict = value as? [String: Any] else {
            return truncateText(stringifyJSON(value), maxLength: 120)
        }
        if name == "bash", let command = dict["command"] as? String {
            let firstLine = command
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? command
            return truncateText(firstLine, maxLength: 120)
        }
        if let path = dict["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return truncateText(stringifyJSON(value), maxLength: 120)
    }

    private func summarizeToolResult(_ value: Any?) -> String {
        guard let dict = value as? [String: Any],
              let content = dict["content"] as? [[String: Any]] else {
            return truncateText(stringifyJSON(value), maxLength: 120)
        }
        let text = content
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return truncateText(text, maxLength: 120)
    }

    private func stringifyJSON(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String {
            return string
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }

    private func truncateText(_ value: String, maxLength: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxLength else { return normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return "\(normalized[..<index])..."
    }
}

struct WidgetView: View {
    @StateObject private var store = AgentStore()
    @FocusState private var isInputFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 1
    @State private var scrollViewportHeight: CGFloat = 1
    @State private var isFollowingLatest = true
    @State private var showFollowButton = false
    @State private var isSettingsPresented = false

    var body: some View {
        Group {
            if isSettingsPresented {
                SettingsPanel(store: store) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSettingsPresented = false
                    }
                }
                .transition(.opacity)
            } else {
                chatPage
                    .transition(.opacity)
            }
        }
        .frame(minWidth: neatWindowMinimumSize.width, minHeight: neatWindowMinimumSize.height)
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle()
                .frame(width: 22, height: 22)
                .padding(3)
        }
        .background(Color.clear)
        .onDrop(of: neatDropTypeIdentifiers, isTargeted: nil, perform: store.handleDrop)
        .onReceive(NotificationCenter.default.publisher(for: .neatFocusComposer)) { _ in
            guard !isSettingsPresented else { return }
            isInputFocused = true
        }
    }

    private var chatPage: some View {
        VStack(spacing: 0) {
            header

            messageList

            composer
        }
    }

    private var messageList: some View {
        GeometryReader { viewport in
            ZStack(alignment: .trailing) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: max(0, -geometry.frame(in: .named("neatMessages")).minY)
                                )
                            }
                            .frame(height: 0)

                            ForEach(store.messages) { message in
                                MessageBubble(message: message) {
                                    store.toggleToolMessage(id: message.id)
                                }
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            if store.showTurnWaitIndicator {
                                AgentTurnWaitIndicator()
                                    .id("turn-wait")
                                    .transition(.opacity)
                            }

                            Color.clear
                                .frame(height: 44)
                                .id(messageBottomAnchorId)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ScrollContentHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                    }
                    .coordinateSpace(name: "neatMessages")
                    .onChange(of: store.messages.last?.id) { _, id in
                        if isFollowingLatest, id != nil {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: store.messages.last?.text) { _, _ in
                        guard isFollowingLatest else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
                        }
                    }
                    .onChange(of: store.showTurnWaitIndicator) { _, isVisible in
                        guard isFollowingLatest, isVisible else { return }
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
                        }
                    }

                    if showFollowButton {
                        VStack {
                            Spacer()
                            Button {
                                isFollowingLatest = true
                                showFollowButton = false
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    LucideIcon(id: "arrow-down", fallbackSystemName: "arrow.down")
                                        .frame(width: 10, height: 10)
                                    Text("跟随")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.13))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.78), in: Capsule())
                                .overlay {
                                    Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.6)
                                }
                                .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 5)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }

                WeakScrollIndicator(
                    viewportHeight: viewport.size.height,
                    contentHeight: scrollContentHeight,
                    offset: scrollOffset
                )
                .padding(.trailing, 5)
            }
            .onAppear {
                scrollViewportHeight = viewport.size.height
            }
            .onChange(of: viewport.size.height) { _, height in
                scrollViewportHeight = height
                updateFollowState(offset: scrollOffset, contentHeight: scrollContentHeight, viewportHeight: height)
            }
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            scrollOffset = offset
            updateFollowState(offset: offset, contentHeight: scrollContentHeight, viewportHeight: scrollViewportHeight)
        }
        .onPreferenceChange(ScrollContentHeightPreferenceKey.self) { height in
            scrollContentHeight = max(1, height)
            updateFollowState(offset: scrollOffset, contentHeight: max(1, height), viewportHeight: scrollViewportHeight)
        }
        .animation(.easeOut(duration: 0.16), value: scrollOffset)
    }

    private func updateFollowState(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let distanceFromBottom = contentHeight - offset - viewportHeight
        let isAtLatest = distanceFromBottom < 28
        if isAtLatest {
            isFollowingLatest = true
            showFollowButton = false
        } else if offset > 6 {
            isFollowingLatest = false
            showFollowButton = true
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text(neatAppName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.14, green: 0.12, blue: 0.10))
                Text(store.status)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.34))
            }

            Spacer()

            Button {
                store.openFiles()
            } label: {
                GlassIconButtonLabel(iconId: "folder", fallbackSystemName: "folder", size: 30, iconSize: 14)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSettingsPresented = true
                }
            } label: {
                GlassIconButtonLabel(iconId: "settings", fallbackSystemName: "gearshape", size: 30, iconSize: 14)
                }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("继续对话，或输入“撤回”...", text: $store.inputText, axis: .vertical)
                .focused($isInputFocused)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .submitLabel(.send)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isInputFocused ? Color.black.opacity(0.13) : Color.white.opacity(0.28), lineWidth: 0.8)
                }
                .onSubmit {
                    store.sendCurrentMessage()
                }

            Button {
                store.sendCurrentMessage()
            } label: {
                LucideIcon(id: "arrow-up", fallbackSystemName: "arrow.up")
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .frame(width: 32, height: 32)
                    .background(Color(red: 0.14, green: 0.12, blue: 0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.clear)
    }
}

struct WindowResizeHandle: View {
    var body: some View {
        WindowResizeHandleRepresentable()
            .overlay(alignment: .bottomTrailing) {
                Canvas { context, size in
                    var path = Path()
                    for offset in stride(from: CGFloat(6), through: CGFloat(16), by: CGFloat(5)) {
                        path.move(to: CGPoint(x: size.width - offset, y: size.height - 3))
                        path.addLine(to: CGPoint(x: size.width - 3, y: size.height - offset))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.38)), lineWidth: 1.1)
                }
                .frame(width: 18, height: 18)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
    }
}

struct WindowResizeHandleRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleNSView {
        ResizeHandleNSView()
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {}
}

final class ResizeHandleNSView: NSView {
    private var initialFrame: NSRect = .zero
    private var initialMouseLocation: NSPoint = .zero

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialFrame = window.frame
        initialMouseLocation = window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let mouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        let deltaX = mouseLocation.x - initialMouseLocation.x
        let deltaY = mouseLocation.y - initialMouseLocation.y
        let width = max(neatWindowMinimumSize.width, initialFrame.width + deltaX)
        let height = max(neatWindowMinimumSize.height, initialFrame.height - deltaY)
        let frame = NSRect(
            x: initialFrame.minX,
            y: initialFrame.maxY - height,
            width: width,
            height: height
        )

        window.setFrame(frame, display: true)
    }
}

struct SettingsPanel: View {
    @ObservedObject var store: AgentStore
    let onClose: () -> Void

    @State private var provider: String
    @State private var model: String
    @State private var thinking: String

    init(store: AgentStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _provider = State(initialValue: store.modelProvider)
        _model = State(initialValue: store.modelId)
        _thinking = State(initialValue: store.thinkingLevel)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("设置")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("模型与应用")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.34))
                }
                Spacer()
                Button(action: onClose) {
                    GlassIconButtonLabel(iconId: "x", fallbackSystemName: "xmark", size: 30, iconSize: 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 12) {
                SettingsField(title: "Provider", text: $provider, placeholder: "deepseek")
                SettingsField(title: "Model", text: $model, placeholder: "deepseek-v4-flash")
                SettingsField(title: "Thinking", text: $thinking, placeholder: "medium")

                VStack(alignment: .leading, spacing: 5) {
                    Text("整理规则")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.34))

                    Button {
                        store.openMemoryFile()
                    } label: {
                        HStack(spacing: 8) {
                            LucideIcon(id: "file-pen-line", fallbackSystemName: "square.and.pencil")
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("编辑整理规则")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("打开 ~/.neat/memory.md，保存后重启 agent 生效")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.34))
                            }
                            Spacer()
                            LucideIcon(id: "external-link", fallbackSystemName: "arrow.up.right")
                                .frame(width: 13, height: 13)
                                .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.34))
                        }
                        .foregroundStyle(Color(red: 0.14, green: 0.12, blue: 0.10))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    store.saveModelSettings(provider: provider, model: model, thinking: thinking)
                    onClose()
                } label: {
                    Text("保存并重启 agent")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(.white)
                        .background(Color(red: 0.14, green: 0.12, blue: 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Divider()
                    .opacity(0.22)
                    .padding(.vertical, 4)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack {
                        LucideIcon(id: "power", fallbackSystemName: "power")
                            .frame(width: 14, height: 14)
                        Text("退出 Neat")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color(red: 0.70, green: 0.13, blue: 0.10))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

struct SettingsField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.34))
            TextField(placeholder, text: $text)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 0.6)
                }
        }
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WeakScrollIndicator: View {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let offset: CGFloat

    var body: some View {
        let isScrollable = contentHeight > viewportHeight + 8
        let trackHeight = max(1, viewportHeight - 20)
        let thumbHeight = max(28, min(trackHeight, viewportHeight / contentHeight * trackHeight))
        let maxOffset = max(1, contentHeight - viewportHeight)
        let travel = max(0, trackHeight - thumbHeight)
        let y = min(max(0, offset / maxOffset * travel), travel)

        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.16))
                .frame(width: 3, height: thumbHeight)
                .offset(y: y)
                .opacity(isScrollable ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(width: 8, height: trackHeight, alignment: .top)
        .padding(.vertical, 10)
        .allowsHitTesting(false)
    }
}

struct AgentTurnWaitIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(neatChatMutedText)
                    .frame(width: 5, height: 5)
                    .scaleEffect(1)
                    .modifier(WaveDot(delay: Double(index) * 0.12))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .padding(.horizontal, 4)
        .accessibilityLabel("等待下一步")
    }
}

struct WaveDot: ViewModifier {
    let delay: Double
    @State private var isRaised = false

    func body(content: Content) -> some View {
        content
            .offset(y: isRaised ? -3 : 0)
            .opacity(isRaised ? 1 : 0.55)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.45)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                ) {
                    isRaised = true
                }
            }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let onToggleTool: () -> Void

    var body: some View {
        if message.role == .tool {
            ToolCallBubble(message: message, onToggle: onToggleTool)
        } else {
            messageBubble
        }
    }

    private var messageBubble: some View {
        HStack(spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 28)
            }

            MessageContentView(message: message)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(foreground)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: message.role == .user ? nil : .infinity, alignment: .leading)
                .background(bubbleFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(border, lineWidth: 0.6)
                }

            if message.role != .user {
                Spacer(minLength: 0)
            }
        }
    }

    private var foreground: Color {
        switch message.role {
        case .user:
            Color.white
        case .assistant:
            neatChatText
        case .system:
            neatChatText
        case .tool:
            neatChatText
        }
    }

    private var bubbleFill: Color {
        switch message.role {
        case .user:
            Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.82)
        case .assistant:
            Color.white.opacity(0.34)
        case .system:
            Color.white.opacity(0.34)
        case .tool:
            Color.white.opacity(0.34)
        }
    }

    private var border: Color {
        switch message.role {
        case .user:
            .clear
        case .assistant:
            .white.opacity(0.42)
        case .system:
            .white.opacity(0.42)
        case .tool:
            .white.opacity(0.42)
        }
    }
}

struct MessageContentView: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .assistant {
            Markdown(message.text.isEmpty ? "..." : message.text)
        } else {
            Text(message.text.isEmpty ? "..." : message.text)
        }
    }
}

struct ToolCallBubble: View {
    let message: ChatMessage
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 7) {
                    LucideIcon(id: iconId, fallbackSystemName: fallbackSystemName)
                        .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.15))
                        .frame(width: 14, height: 14)
                        .frame(width: 18, height: 18)

                    Text(displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(neatChatText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(compactSummary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(neatChatMutedText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    statusBadge
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if message.toolExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    if !message.toolSummary.isEmpty {
                        ToolPayloadLine(title: "输入", text: message.toolSummary)
                    }
                    if !message.toolResult.isEmpty {
                        ToolPayloadLine(title: message.toolStatus == .failed ? "错误" : "结果", text: message.toolResult)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 0.6)
        }
        .animation(.easeInOut(duration: 0.18), value: message.toolExpanded)
    }

    private var compactSummary: String {
        let raw = message.toolSummary.isEmpty ? message.toolResult : message.toolSummary
        return truncate(raw, maxLength: 34)
    }

    private func truncate(_ value: String, maxLength: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxLength else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return "\(normalized[..<end])..."
    }

    private var displayName: String {
        switch message.toolName.lowercased() {
        case "bash":
            "Bash"
        case "read":
            "Read"
        case "write":
            "Write"
        case "edit", "multi_edit":
            "Edit"
        default:
            message.toolName.isEmpty ? "Tool" : message.toolName
        }
    }

    private var iconId: String {
        switch message.toolName.lowercased() {
        case "bash":
            "terminal"
        case "read":
            "file-text"
        case "write":
            "square-pen"
        case "edit", "multi_edit":
            "pencil"
        case "find", "grep":
            "search"
        case "ls":
            "folder"
        default:
            "wrench"
        }
    }

    private var fallbackSystemName: String {
        switch message.toolName.lowercased() {
        case "bash":
            "terminal"
        case "read":
            "doc.text"
        case "write":
            "square.and.pencil"
        case "edit", "multi_edit":
            "pencil"
        case "find", "grep":
            "magnifyingglass"
        case "ls":
            "folder"
        default:
            "wrench.and.screwdriver"
        }
    }

    private var statusBadge: some View {
        ZStack {
            if message.toolStatus == .running {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .frame(width: 16, height: 16)
            } else {
                LucideIcon(
                    id: message.toolStatus == .failed ? "circle-alert" : "circle-check",
                    fallbackSystemName: message.toolStatus == .failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                )
                    .frame(width: 12, height: 12)
            }
        }
        .foregroundStyle(statusColor)
        .frame(width: 18, height: 18)
    }

    private var statusColor: Color {
        switch message.toolStatus {
        case .running:
            Color(red: 0.10, green: 0.42, blue: 0.86)
        case .finished:
            Color(red: 0.03, green: 0.55, blue: 0.22)
        case .failed:
            Color(red: 0.74, green: 0.12, blue: 0.10)
        }
    }
}

struct ToolPayloadLine: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.34).opacity(0.76))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(neatChatText)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

final class NeatWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var frameKeeper: WindowFrameKeeper?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupStatusItem()

        let rootView: NSView
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        if #available(macOS 26.0, *) {
            let glassEffectView = NSGlassEffectView()
            glassEffectView.style = .clear
            glassEffectView.cornerRadius = 24
            glassEffectView.tintColor = nil
            glassEffectView.contentView = contentView
            glassEffectView.wantsLayer = true
            glassEffectView.layer?.cornerRadius = 24
            glassEffectView.layer?.cornerCurve = .continuous
            glassEffectView.layer?.masksToBounds = true
            glassEffectView.layer?.borderWidth = 0.8
            glassEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.52).cgColor
            rootView = glassEffectView
        } else {
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .underWindowBackground
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = 24
            visualEffectView.layer?.cornerCurve = .continuous
            visualEffectView.layer?.masksToBounds = true
            visualEffectView.layer?.borderWidth = 0.8
            visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
            visualEffectView.addSubview(contentView)
            rootView = visualEffectView
        }

        let hostingView = NSHostingView(rootView: WidgetView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let defaultFrame = NSRect(
            x: 96,
            y: 420,
            width: neatWindowDefaultSize.width,
            height: neatWindowDefaultSize.height
        )
        let window = NeatWindow(
            contentRect: Self.savedFrame() ?? defaultFrame,
            styleMask: [.borderless, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = rootView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.invalidateShadow()
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = true
        window.minSize = neatWindowMinimumSize
        window.contentMinSize = neatWindowMinimumSize
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.orderOut(nil)

        let frameKeeper = WindowFrameKeeper()
        window.delegate = frameKeeper
        self.frameKeeper = frameKeeper
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: neatAppName)
        appMenu.addItem(
            withTitle: "退出 \(neatAppName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: neatAppName)
                ?? NSImage(systemSymbolName: "tray.fill", accessibilityDescription: neatAppName)
                ?? NSImage.image(lucideId: "inbox")
                ?? NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: neatAppName)
                ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: neatAppName)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "\(neatAppName) - 拖入文件整理"
            button.target = self
            button.action = #selector(toggleWindowFromStatusItem)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem
    }

    @objc private func toggleWindowFromStatusItem() {
        guard let window else { return }

        if window.isVisible {
            window.orderOut(nil)
            return
        }

        positionWindowUnderStatusItem(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .neatFocusComposer, object: nil)
        }
    }

    private func positionWindowUnderStatusItem(_ window: NSWindow) {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            return
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 12
        let gap: CGFloat = 0
        let horizontalOffset: CGFloat = 0
        let windowSize = window.frame.size

        let targetX = buttonRect.minX + horizontalOffset
        let x = min(
            max(targetX, visibleFrame.minX + margin),
            visibleFrame.maxX - windowSize.width - margin
        )
        let targetY = buttonRect.minY - windowSize.height - gap
        let y = max(targetY, visibleFrame.minY + margin)

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private static func savedFrame() -> NSRect? {
        let raw = UserDefaults.standard.string(forKey: "neat.window.frame")
        guard let raw, !raw.isEmpty else { return nil }
        var frame = NSRectFromString(raw)
        if frame.width < neatWindowMinimumSize.width {
            frame.size.width = neatWindowMinimumSize.width
        }
        if frame.height < neatWindowMinimumSize.height {
            frame.size.height = neatWindowMinimumSize.height
        }
        return frame
    }
}

@MainActor
final class WindowFrameKeeper: NSObject, NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        save(notification)
    }

    func windowDidResize(_ notification: Notification) {
        save(notification)
    }

    private func save(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "neat.window.frame")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
