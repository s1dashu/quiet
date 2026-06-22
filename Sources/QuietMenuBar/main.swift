import AppKit
import Carbon
import LucideIcons
import MarkdownUI
import SwiftUI
import UniformTypeIdentifiers

private let quietAppName = "Quiet"
private let quietWindowDefaultSize = NSSize(width: 380, height: 520)
private let quietWindowMinimumSize = NSSize(width: 340, height: 420)
private let quietDesktopWindowDefaultSize = NSSize(width: 820, height: 540)
private let quietDesktopWindowMinimumSize = NSSize(width: 640, height: 440)
private let quietHeaderHeight: CGFloat = 54
private let quietDesktopHeaderLeadingInset: CGFloat = 78
private let quietDesktopTrafficLightFallbackInset: CGFloat = 20
private let quietAppIconResourcePath = "app-icon/quiet-app-icon.png"
private let quietSwiftPMResourceBundleName = "Quiet_QuietMenuBar.bundle"
private let quietRuntimeDirectoryName = ".quiet"
private let quietLegacyRuntimeDirectoryName = ".blackhole"
private let quietContentDirectoryName = "Quiet"
private let quietLegacyContentDirectoryName = "Blackhole"
private let messageBottomAnchorId = "message-bottom-anchor"
private let quietAppearanceModeKey = "quiet.appearance.mode"
private let quietLegacyModelApiKeyKey = "quiet.model.apiKey"
private let quietDropTypeIdentifiers = [
    UTType.fileURL.identifier,
    UTType.url.identifier,
    UTType.image.identifier,
    UTType.png.identifier,
    UTType.jpeg.identifier,
    UTType.tiff.identifier,
    UTType.plainText.identifier,
    UTType.utf8PlainText.identifier,
]

private func quietBundledResourceURL(path: String) -> URL? {
    let candidates = [
        Bundle.module.resourceURL?.appendingPathComponent(path),
        Bundle.main.resourceURL?.appendingPathComponent(path),
        Bundle.main.resourceURL?
            .appendingPathComponent(quietSwiftPMResourceBundleName)
            .appendingPathComponent("Resources")
            .appendingPathComponent(path),
        Bundle.main.bundleURL
            .appendingPathComponent(quietSwiftPMResourceBundleName)
            .appendingPathComponent("Resources")
            .appendingPathComponent(path),
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent(path),
    ]
    return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
}

private func quietApplicationSupportURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let url = home.appendingPathComponent(quietRuntimeDirectoryName, isDirectory: true)
    let legacyURL = home.appendingPathComponent(quietLegacyRuntimeDirectoryName, isDirectory: true)
    quietMigrateDirectoryIfNeeded(from: legacyURL, to: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func quietContentRootURL() -> URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    let url = documents.appendingPathComponent(quietContentDirectoryName, isDirectory: true)
    let legacyURL = documents.appendingPathComponent(quietLegacyContentDirectoryName, isDirectory: true)
    quietMigrateDirectoryIfNeeded(from: legacyURL, to: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func quietMigrateDirectoryIfNeeded(from legacyURL: URL, to url: URL) {
    let fileManager = FileManager.default
    guard legacyURL.path != url.path,
          fileManager.fileExists(atPath: legacyURL.path) else {
        return
    }

    if !fileManager.fileExists(atPath: url.path) {
        try? fileManager.moveItem(at: legacyURL, to: url)
        return
    }

    guard let entries = try? fileManager.contentsOfDirectory(at: legacyURL, includingPropertiesForKeys: nil) else {
        return
    }
    for entry in entries {
        let destination = quietUniqueDestination(in: url, named: entry.lastPathComponent)
        try? fileManager.moveItem(at: entry, to: destination)
    }
    try? fileManager.removeItem(at: legacyURL)
}

private func quietUniqueDestination(in directory: URL, named name: String) -> URL {
    let fileManager = FileManager.default
    let baseURL = directory.appendingPathComponent(name)
    guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }

    let ext = baseURL.pathExtension
    let stem = ext.isEmpty ? baseURL.lastPathComponent : String(baseURL.lastPathComponent.dropLast(ext.count + 1))
    for index in 2...999 {
        let candidateName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
        let candidateURL = directory.appendingPathComponent(candidateName)
        if !fileManager.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    let suffix = ext.isEmpty ? "" : ".\(ext)"
    return directory.appendingPathComponent("\(stem) \(UUID().uuidString)\(suffix)")
}

private enum QuietSecrets {
    private static let modelApiKeyKey = "modelApiKey"

    static func readModelApiKey() -> String {
        guard let data = try? Data(contentsOf: secretsURL()),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[modelApiKeyKey] as? String else {
            return ""
        }
        return value
    }

    static func saveModelApiKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = secretsURL()
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }

        let object: [String: Any] = [modelApiKeyKey: trimmed]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func secretsURL() -> URL {
        quietApplicationSupportURL()
            .appendingPathComponent("secrets.json", isDirectory: false)
    }
}
private func quietDynamicNSColor(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? dark : light
    }
}

private func quietDynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: quietDynamicNSColor(light: light, dark: dark))
}

private func quietResolvedCGColor(_ color: NSColor, colorScheme: ColorScheme) -> CGColor {
    let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
    return quietResolvedCGColor(color, appearance: NSAppearance(named: appearanceName))
}

private func quietResolvedCGColor(_ color: NSColor, appearance: NSAppearance?) -> CGColor {
    var resolvedColor = color.cgColor
    if let appearance {
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
    }
    return resolvedColor
}

private let quietChatText = quietDynamicColor(
    light: NSColor(calibratedWhite: 0.08, alpha: 1),
    dark: NSColor(calibratedWhite: 0.94, alpha: 1)
)
private let quietChatMutedText = quietChatText.opacity(0.62)
private let quietNonUserMessageText = quietDynamicColor(
    light: NSColor(calibratedWhite: 0.12, alpha: 1),
    dark: NSColor(calibratedWhite: 0.96, alpha: 1)
)
private let quietNonUserBubbleFill = quietDynamicColor(
    light: NSColor(calibratedWhite: 0.92, alpha: 1),
    dark: NSColor(calibratedWhite: 0.115, alpha: 1)
)
private let quietNonUserBubbleBorder = quietDynamicColor(
    light: NSColor.black.withAlphaComponent(0.12),
    dark: NSColor.white.withAlphaComponent(0.12)
)
private let quietSettingsControlFill = quietNonUserBubbleFill
private let quietSettingsControlBorder = quietNonUserBubbleBorder
private let quietSubtleText = quietDynamicColor(
    light: NSColor(calibratedWhite: 0.38, alpha: 1),
    dark: NSColor(calibratedWhite: 0.66, alpha: 1)
)
private let quietPrimaryFill = quietDynamicColor(
    light: NSColor(calibratedWhite: 0.05, alpha: 1),
    dark: NSColor.white
)
private let quietPrimaryText = quietDynamicColor(
    light: NSColor.white,
    dark: NSColor.black
)
private let quietSecondaryButtonFill = quietDynamicColor(
    light: NSColor.white,
    dark: NSColor(calibratedWhite: 0.08, alpha: 1)
)
private let quietSecondaryButtonText = quietDynamicColor(
    light: NSColor(calibratedWhite: 0.06, alpha: 1),
    dark: NSColor(calibratedWhite: 0.94, alpha: 1)
)
private let quietSecondaryButtonBorder = quietDynamicColor(
    light: NSColor.black.withAlphaComponent(0.14),
    dark: NSColor.white.withAlphaComponent(0.16)
)
private let quietComposerFill = quietDynamicColor(
    light: NSColor(calibratedWhite: 0.96, alpha: 1),
    dark: NSColor(calibratedWhite: 0.09, alpha: 1)
)
private let quietHoverFill = quietDynamicColor(
    light: NSColor.black.withAlphaComponent(0.06),
    dark: NSColor.white.withAlphaComponent(0.08)
)
private let quietSelectedFill = quietDynamicColor(
    light: NSColor.black.withAlphaComponent(0.08),
    dark: NSColor.white.withAlphaComponent(0.12)
)
private let quietHairline = quietDynamicColor(
    light: NSColor.black.withAlphaComponent(0.11),
    dark: NSColor.white.withAlphaComponent(0.10)
)
private let quietMarkdownCodeFill = quietDynamicColor(
    light: NSColor.black.withAlphaComponent(0.08),
    dark: NSColor.black.withAlphaComponent(0.34)
)
private let quietWindowFill = quietDynamicNSColor(
    light: NSColor.white,
    dark: NSColor(calibratedWhite: 0.04, alpha: 1)
)
private let quietPanelFill = quietDynamicNSColor(
    light: NSColor.white,
    dark: NSColor(calibratedWhite: 0.075, alpha: 1)
)
private let quietSidebarFill = quietDynamicNSColor(
    light: NSColor(calibratedWhite: 0.88, alpha: 1),
    dark: NSColor(calibratedWhite: 0.10, alpha: 1)
)
private let quietBorder = quietDynamicNSColor(
    light: NSColor.black.withAlphaComponent(0.12),
    dark: NSColor.white.withAlphaComponent(0.11)
)
private let quietThinkingLevelOrder = ["off", "minimal", "low", "medium", "high", "xhigh"]

private func closestThinkingLevel(to requestedLevel: String, in supportedLevels: [String]) -> String {
    let supported = supportedLevels.isEmpty ? ["off"] : supportedLevels
    let normalizedRequest = requestedLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if supported.contains(normalizedRequest) {
        return normalizedRequest
    }
    guard let requestedIndex = quietThinkingLevelOrder.firstIndex(of: normalizedRequest) else {
        return supported.first ?? "off"
    }
    for index in requestedIndex..<quietThinkingLevelOrder.count {
        let candidate = quietThinkingLevelOrder[index]
        if supported.contains(candidate) {
            return candidate
        }
    }
    if requestedIndex > 0 {
        for index in stride(from: requestedIndex - 1, through: 0, by: -1) {
            let candidate = quietThinkingLevelOrder[index]
            if supported.contains(candidate) {
                return candidate
            }
        }
    }
    return supported.first ?? "off"
}

enum QuietLanguage: String, CaseIterable, Identifiable {
    case en
    case zh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .en: "English"
        case .zh: "中文"
        }
    }

    static func normalized(_ raw: String?) -> QuietLanguage {
        raw == "zh" ? .zh : .en
    }
}

enum QuietAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    static func normalized(_ raw: String?) -> QuietAppearanceMode {
        QuietAppearanceMode(rawValue: raw ?? "") ?? .system
    }
}

struct QuietCopy {
    let initialMessage: String
    let startingStatus: String
    let connectingStatus: String
    let readyStatus: String
    let workingStatus: String
    let switchingModelStatus: String
    let launchFailedPrefix: String
    let agentExitedPrefix: String
    let droppedPrefix: String
    let capturedPrefix: String
    let noReadableFiles: String
    let noReadableResources: String
    let autoOrganizeFiles: String
    let autoOrganizeResources: String
    let settingsTitle: String
    let settingsSubtitle: String
    let language: String
    let provider: String
    let model: String
    let apiKey: String
    let apiKeyPlaceholder: String
    let thinking: String
    let appearance: String
    let appearanceSystem: String
    let appearanceLight: String
    let appearanceDark: String
    let quietRules: String
    let editQuietRules: String
    let quietRulesHelp: String
    let saveAndRestart: String
    let newSession: String
    let moreActions: String
    let openDesktopClient: String
    let openFiles: String
    let quit: String
    let composerPlaceholder: String
    let dropOverlay: String
    let statusTooltip: String
    let unknownError: String
    let agentErrorPrefix: String
    let providerUnavailable: String
}

func quietCopy(_ language: QuietLanguage) -> QuietCopy {
    switch language {
    case .en:
        QuietCopy(
            initialMessage: "Drop files, links, or snippets here. The agent will organize them automatically.",
            startingStatus: "Starting",
            connectingStatus: "Connecting agent",
            readyStatus: "Agent ready",
            workingStatus: "Agent working",
            switchingModelStatus: "Switching model",
            launchFailedPrefix: "Launch failed",
            agentExitedPrefix: "Agent exited",
            droppedPrefix: "Moved in",
            capturedPrefix: "Captured",
            noReadableFiles: "No readable resources found. Drop files, links, or text snippets.",
            noReadableResources: "No readable resources found. Drop files, links, or text snippets.",
            autoOrganizeFiles: "Handle this content",
            autoOrganizeResources: "Handle this content",
            settingsTitle: "Settings",
            settingsSubtitle: "Model and app",
            language: "Language",
            provider: "Provider",
            model: "Model",
            apiKey: "API Key",
            apiKeyPlaceholder: "Use environment key or paste one here",
            thinking: "Thinking",
            appearance: "Appearance",
            appearanceSystem: "Follow System",
            appearanceLight: "Light",
            appearanceDark: "Dark",
            quietRules: "Resource organizing rules",
            editQuietRules: "Edit rules",
            quietRulesHelp: "Open ~/.quiet/memory.md. Restart the agent after saving.",
            saveAndRestart: "Save and restart agent",
            newSession: "New session",
            moreActions: "More actions",
            openDesktopClient: "Open desktop app",
            openFiles: "Open files",
            quit: "Quit Quiet",
            composerPlaceholder: "Drop files, links, snippets, or type a message...",
            dropOverlay: "Release to capture resources",
            statusTooltip: "\(quietAppName) - drop files, links, or snippets",
            unknownError: "Unknown error",
            agentErrorPrefix: "agent error",
            providerUnavailable: "Loading providers..."
        )
    case .zh:
        QuietCopy(
            initialMessage: "把文件、链接或文本片段丢进来，Agent 会自动帮你整理。",
            startingStatus: "启动中",
            connectingStatus: "连接 agent 中",
            readyStatus: "agent 就绪",
            workingStatus: "agent 工作中",
            switchingModelStatus: "正在切换模型",
            launchFailedPrefix: "启动失败",
            agentExitedPrefix: "agent 已退出",
            droppedPrefix: "已移入",
            capturedPrefix: "已捕获",
            noReadableFiles: "没有读到可处理的资源。请拖入文件、链接，或粘贴文本片段。",
            noReadableResources: "没有读到可处理的资源。请拖入文件、链接，或粘贴文本片段。",
            autoOrganizeFiles: "帮我处理这些内容",
            autoOrganizeResources: "帮我处理这些内容",
            settingsTitle: "设置",
            settingsSubtitle: "模型与应用",
            language: "语言",
            provider: "供应商",
            model: "模型",
            apiKey: "API Key",
            apiKeyPlaceholder: "使用环境变量，或在这里填入",
            thinking: "Thinking",
            appearance: "外观",
            appearanceSystem: "跟随系统",
            appearanceLight: "浅色",
            appearanceDark: "深色",
            quietRules: "资源整理规则",
            editQuietRules: "编辑规则",
            quietRulesHelp: "打开 ~/.quiet/memory.md，保存后重启 agent 生效",
            saveAndRestart: "保存并重启 agent",
            newSession: "新建会话",
            moreActions: "更多操作",
            openDesktopClient: "打开桌面客户端",
            openFiles: "打开文件夹",
            quit: "退出 Quiet",
            composerPlaceholder: "粘贴链接、片段，或输入消息...",
            dropOverlay: "松手捕获资源",
            statusTooltip: "\(quietAppName) - 拖入文件、链接或片段",
            unknownError: "未知错误",
            agentErrorPrefix: "agent error",
            providerUnavailable: "正在加载供应商..."
        )
    }
}

struct AvailableModel: Identifiable, Equatable {
    let id: String
    let provider: String
    let modelId: String
    let name: String
    let label: String
    let thinkingLevels: [String]
}

struct ModelProviderOption: Identifiable, Equatable {
    let id: String
    let name: String
    let models: [AvailableModel]
}

private extension Notification.Name {
    static let quietFocusComposer = Notification.Name("QuietFocusComposer")
    static let quietRestoreFollowLatest = Notification.Name("QuietRestoreFollowLatest")
    static let quietAppearanceDidChange = Notification.Name("QuietAppearanceDidChange")
    static let quietOpenDesktopClient = Notification.Name("QuietOpenDesktopClient")
    static let quietWindowChromeModeDidChange = Notification.Name("QuietWindowChromeModeDidChange")
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

struct CapturedResource: Equatable {
    let kind: String
    let value: String
    var name: String?
    var mimeType: String?

    var payload: [String: String] {
        var payload = [
            "kind": kind,
            "value": value,
        ]
        if let name {
            payload["name"] = name
        }
        if let mimeType {
            payload["mimeType"] = mimeType
        }
        return payload
    }

    var displayName: String {
        switch kind {
        case "link":
            URL(string: value)?.host(percentEncoded: false) ?? value
        case "image":
            name ?? "Pasted image"
        default:
            truncateResourceLabel(value)
        }
    }
}

private func capturedResource(from text: String) -> CapturedResource? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let url = URL(string: trimmed), url.scheme != nil, !url.isFileURL {
        return CapturedResource(kind: "link", value: trimmed)
    }
    return CapturedResource(kind: "text", value: trimmed)
}

private func capturedResource(fromDropItem item: NSSecureCoding?, typeIdentifier: String? = nil) -> CapturedResource? {
    if let typeIdentifier,
       let type = UTType(typeIdentifier),
       type.conforms(to: .image),
       let resource = capturedImageResource(fromDropItem: item) {
        return resource
    }
    if let url = item as? URL, !url.isFileURL {
        return CapturedResource(kind: "link", value: url.absoluteString)
    }
    if let url = item as? NSURL {
        let bridged = url as URL
        if !bridged.isFileURL {
            return CapturedResource(kind: "link", value: bridged.absoluteString)
        }
    }
    if let text = item as? String {
        return capturedResource(from: text)
    }
    if let data = item as? Data,
       let text = String(data: data, encoding: .utf8) {
        return capturedResource(from: text)
    }
    return nil
}

private func capturedResources(from pasteboard: NSPasteboard) -> (paths: [String], resources: [CapturedResource]) {
    var paths: [String] = []
    var resources: [CapturedResource] = []

    if let urls = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: false]
    ) as? [URL] {
        for url in urls {
            if url.isFileURL {
                paths.append(url.path)
            } else {
                resources.append(CapturedResource(kind: "link", value: url.absoluteString))
            }
        }
    }

    if let text = pasteboard.string(forType: .string),
       let resource = capturedResource(from: text),
       !resources.contains(resource),
       !paths.contains(where: { $0 == resource.value }) {
        resources.append(resource)
    }

    if paths.isEmpty,
       let image = NSImage(pasteboard: pasteboard),
       let data = pngData(from: image) {
        resources.append(CapturedResource(
            kind: "image",
            value: data.base64EncodedString(),
            name: "Pasted image \(quietTimestampForFilename()).png",
            mimeType: "image/png"
        ))
    }

    return (paths.sorted(), resources)
}

private func capturedImageResource(fromDropItem item: NSSecureCoding?) -> CapturedResource? {
    let data: Data?
    if let image = item as? NSImage {
        data = pngData(from: image)
    } else if let rawData = item as? Data {
        data = normalizedImageData(from: rawData)
    } else {
        data = nil
    }
    guard let data else { return nil }
    return CapturedResource(
        kind: "image",
        value: data.base64EncodedString(),
        name: "Pasted image \(quietTimestampForFilename()).png",
        mimeType: "image/png"
    )
}

private func normalizedImageData(from data: Data) -> Data? {
    if let image = NSImage(data: data) {
        return pngData(from: image)
    }
    return nil
}

private func pngData(from image: NSImage) -> Data? {
    var proposedRect = NSRect(origin: .zero, size: image.size)
    if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }
    return bitmap.representation(using: .png, properties: [:])
}

private func quietTimestampForFilename() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    return formatter.string(from: Date())
}

private func truncateResourceLabel(_ value: String, maxLength: Int = 42) -> String {
    let normalized = value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > maxLength else { return normalized }
    let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
    return "\(normalized[..<index])..."
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
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = quietResolvedCGColor(quietPanelFill, colorScheme: context.environment.colorScheme)
        view.layer?.borderWidth = 0
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.backgroundColor = quietResolvedCGColor(quietPanelFill, colorScheme: context.environment.colorScheme)
    }
}

struct GlassIconButtonLabel: View {
    let iconId: String
    let fallbackSystemName: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 14
    var cornerRadius: CGFloat? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let radius = cornerRadius ?? size / 2
        LucideIcon(id: iconId, fallbackSystemName: fallbackSystemName)
            .foregroundStyle(quietChatText.opacity(0.92))
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
                            .stroke(quietHairline, lineWidth: 0.7)
                    }
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.28 : 0.10),
                radius: colorScheme == .dark ? 3 : 1.5,
                x: 0,
                y: colorScheme == .dark ? 1 : 0.5
            )
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
    var usesPlainTextRendering = false
}

struct QuietSessionSummary: Identifiable, Equatable {
    let id: String
    let path: String
    let title: String
    let modified: String
    let messageCount: Int
}

final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var resources: [CapturedResource] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    fileprivate func append(_ resource: CapturedResource) {
        lock.lock()
        resources.append(resource)
        lock.unlock()
    }

    func paths() -> [String] {
        lock.lock()
        let paths = urls.map(\.path).sorted()
        lock.unlock()
        return paths
    }

    fileprivate func capturedResources() -> [CapturedResource] {
        lock.lock()
        let values = resources
        lock.unlock()
        return values
    }
}

@MainActor
final class AgentStore: ObservableObject {
    @Published var messages: [ChatMessage]
    @Published var inputText = ""
    @Published var status: String
    @Published var isAgentReady = false
    @Published var isAgentWorking = false
    @Published var showTurnWaitIndicator = false
    @Published var lastDroppedPaths: [String] = []
    @Published var inputContainsPastedResource = false
    @Published var filesPath = ""
    @Published var language: String
    @Published var modelProvider: String
    @Published var modelId: String
    @Published var modelApiKey: String
    @Published var thinkingLevel: String
    @Published var appearanceMode: QuietAppearanceMode
    @Published var modelProviders: [ModelProviderOption] = []
    @Published var sessions: [QuietSessionSummary] = []
    @Published var currentSessionPath = ""
    @Published var sessionScrollRequest = 0
    @Published var hasMoreHistory = false
    @Published var isLoadingHistory = false
    @Published private(set) var historyAnchorMessageId: String?
    @Published private(set) var historyAnchorScrollRequest = 0

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()
    private var assistantMessageIdsByAgentId: [String: String] = [:]
    private var toolMessageIdsByToolId: [String: String] = [:]
    private var turnWaitTask: Task<Void, Never>?
    private var isRestartingAgent = false
    private var isAwaitingSessionActivation = false
    private var lastHistoryLoadAt = Date.distantPast
    private var pendingHistoryAnchorMessageId: String?

    init() {
        let storedLanguage = QuietLanguage.normalized(UserDefaults.standard.string(forKey: "quiet.language"))
        let copy = quietCopy(storedLanguage)
        language = storedLanguage.rawValue
        modelProvider = UserDefaults.standard.string(forKey: "quiet.model.provider") ?? "deepseek"
        modelId = UserDefaults.standard.string(forKey: "quiet.model.id") ?? "deepseek-v4-flash"
        let legacyApiKey = UserDefaults.standard.string(forKey: quietLegacyModelApiKeyKey) ?? ""
        let secretsApiKey = QuietSecrets.readModelApiKey()
        if secretsApiKey.isEmpty, !legacyApiKey.isEmpty {
            QuietSecrets.saveModelApiKey(legacyApiKey)
            UserDefaults.standard.removeObject(forKey: quietLegacyModelApiKeyKey)
            modelApiKey = legacyApiKey
        } else {
            UserDefaults.standard.removeObject(forKey: quietLegacyModelApiKeyKey)
            modelApiKey = secretsApiKey
        }
        thinkingLevel = UserDefaults.standard.string(forKey: "quiet.thinking.level") ?? "medium"
        appearanceMode = QuietAppearanceMode.normalized(UserDefaults.standard.string(forKey: quietAppearanceModeKey))
        status = copy.startingStatus
        messages = []
        startAgent()
    }

    deinit {
        process?.terminate()
    }

    func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pastedResource = inputContainsPastedResource ? capturedResource(from: text) : nil
        guard !text.isEmpty || !lastDroppedPaths.isEmpty else { return }
        inputText = ""
        inputContainsPastedResource = false
        send(
            text: pastedResource == nil ? text : copy.autoOrganizeResources,
            paths: lastDroppedPaths,
            resources: pastedResource.map { [$0] } ?? []
        )
        lastDroppedPaths = []
    }

    func sendCapturedPasteboardContent(from pasteboard: NSPasteboard = .general) -> Bool {
        let captured = capturedResources(from: pasteboard)
        guard !captured.paths.isEmpty || !captured.resources.isEmpty else { return false }
        sendCapturedContent(paths: captured.paths, resources: captured.resources)
        return true
    }

    func sendCapturedContent(paths: [String], resources: [CapturedResource]) {
        guard !paths.isEmpty || !resources.isEmpty else { return }
        lastDroppedPaths = []
        inputText = ""
        inputContainsPastedResource = false
        send(
            text: copy.autoOrganizeResources,
            paths: paths,
            resources: resources
        )
    }

    var hasUsableModelCredential: Bool {
        !modelProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!modelApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(ProcessInfo.processInfo.environment["QUIET_MODEL_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func startNewSession() {
        inputText = ""
        lastDroppedPaths = []
        inputContainsPastedResource = false
        resetStreamingState()
        resetHistoryPagination()
        isAwaitingSessionActivation = true
        status = copy.readyStatus
        messages = []
        writeJSONLine(["type": "new_session"])
    }

    func requestSessionList() {
        guard sessions.isEmpty else { return }
        writeJSONLine(["type": "list_sessions"])
    }

    func refreshSessionList() {
        writeJSONLine(["type": "list_sessions"])
    }

    func openSession(_ session: QuietSessionSummary) {
        guard session.path != currentSessionPath else { return }
        inputText = ""
        lastDroppedPaths = []
        inputContainsPastedResource = false
        resetStreamingState()
        isAwaitingSessionActivation = true
        currentSessionPath = session.path
        writeJSONLine(["type": "open_session", "path": session.path])
    }

    func deleteSession(_ session: QuietSessionSummary) {
        sessions.removeAll { $0.path == session.path }
        writeJSONLine(["type": "delete_session", "path": session.path])
    }

    func loadMoreHistoryIfNeeded() {
        let now = Date()
        guard hasMoreHistory,
              !isLoadingHistory,
              !currentSessionPath.isEmpty,
              now.timeIntervalSince(lastHistoryLoadAt) > 0.35 else {
            return
        }
        lastHistoryLoadAt = now
        pendingHistoryAnchorMessageId = messages.first?.id
        isLoadingHistory = true
        writeJSONLine(["type": "load_session_history", "path": currentSessionPath])
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let collector = DroppedURLCollector()
        let group = DispatchGroup()
        var requestedResources = false

        for provider in providers {
            guard let typeIdentifier = quietDropTypeIdentifiers.first(where: {
                provider.hasItemConformingToTypeIdentifier($0)
            }) else {
                continue
            }
            requestedResources = true
            group.enter()
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = fileURL(fromDropItem: item) {
                    collector.append(url)
                } else if let resource = capturedResource(fromDropItem: item, typeIdentifier: typeIdentifier) {
                    collector.append(resource)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let paths = collector.paths()
            let resources = collector.capturedResources()
            guard !paths.isEmpty || !resources.isEmpty else {
                self?.messages.append(ChatMessage(
                    id: UUID().uuidString,
                    role: .system,
                    text: self?.copy.noReadableResources ?? "No readable resources found."
                ))
                return
            }
            self?.sendCapturedContent(paths: paths, resources: resources)
        }

        return requestedResources
    }

    private func startAgent() {
        guard let agentURL = bundledResourceURL(path: "pi-agent/server.mjs") else {
            status = "\(copy.launchFailedPrefix): agent/server.mjs"
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
        let configuredApiKey = modelApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let inheritedApiKey = (environment["QUIET_MODEL_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        environment.merge([
            "NODE_ENV": environment["NODE_ENV"] ?? "production",
            "QUIET_HOME": applicationSupportDirectory().path,
            "QUIET_CONTENT_HOME": contentDirectory().path,
            "QUIET_LANGUAGE": currentLanguage.rawValue,
            "QUIET_MODEL_PROVIDER": modelProvider.trimmingCharacters(in: .whitespacesAndNewlines),
            "QUIET_MODEL_ID": modelId.trimmingCharacters(in: .whitespacesAndNewlines),
            "QUIET_MODEL_API_KEY": configuredApiKey.isEmpty ? inheritedApiKey : configuredApiKey,
            "QUIET_THINKING_LEVEL": thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines),
            "PI_AGENT_HOME": applicationSupportDirectory().path,
            "PATH": mergedPath(),
        ]) { _, new in new }
        if let projectDirectory = projectDirectoryURL() {
            environment["QUIET_PROJECT_ROOT"] = projectDirectory.path
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
                self?.status = "\(self?.copy.agentExitedPrefix ?? "Agent exited"): \(process.terminationStatus)"
            }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = inputPipe
            isRestartingAgent = false
            status = copy.connectingStatus
        } catch {
            isRestartingAgent = false
            status = "\(copy.launchFailedPrefix): \(error.localizedDescription)"
            messages.append(ChatMessage(id: UUID().uuidString, role: .system, text: status))
        }
    }

    private func send(text: String, paths: [String], resources: [CapturedResource] = []) {
        if !paths.isEmpty {
            let fileText = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "、")
            messages.append(ChatMessage(id: UUID().uuidString, role: .system, text: "\(copy.droppedPrefix): \(fileText)"))
        }
        if !resources.isEmpty {
            let resourceText = resources.map(\.displayName).joined(separator: "、")
            messages.append(ChatMessage(id: UUID().uuidString, role: .system, text: "\(copy.capturedPrefix): \(resourceText)"))
        }
        if !text.isEmpty {
            messages.append(ChatMessage(id: UUID().uuidString, role: .user, text: text))
        }
        NotificationCenter.default.post(name: .quietRestoreFollowLatest, object: nil)

        let payload: [String: Any] = [
            "type": "user_message",
            "text": text,
            "paths": paths,
            "resources": resources.map(\.payload),
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
            status = copy.readyStatus
            requestSessionList()
        case "session_current":
            currentSessionPath = object["path"] as? String ?? currentSessionPath
        case "session_reset":
            isAgentReady = true
            currentSessionPath = object["path"] as? String ?? currentSessionPath
            isAwaitingSessionActivation = false
            resetStreamingState()
            resetHistoryPagination()
            status = copy.readyStatus
        case "session_list":
            updateSessionList(from: object)
        case "session_opened":
            currentSessionPath = object["path"] as? String ?? currentSessionPath
            isAwaitingSessionActivation = false
            restoreMessages(from: object["messages"] as? [[String: Any]] ?? [])
            resetStreamingState()
            hasMoreHistory = object["hasMore"] as? Bool ?? false
            isLoadingHistory = false
            lastHistoryLoadAt = .distantPast
            pendingHistoryAnchorMessageId = nil
            historyAnchorMessageId = nil
            sessionScrollRequest += 1
            status = copy.readyStatus
        case "session_history_batch":
            guard (object["path"] as? String) == currentSessionPath else { return }
            let insertedHistory = mergeSessionHistoryBatch(
                object["messages"] as? [[String: Any]] ?? [],
                prepend: object["prepend"] as? Bool ?? false
            )
            hasMoreHistory = object["hasMore"] as? Bool ?? false
            isLoadingHistory = false
            if insertedHistory, let anchorId = pendingHistoryAnchorMessageId {
                historyAnchorMessageId = anchorId
                historyAnchorScrollRequest += 1
            }
            pendingHistoryAnchorMessageId = nil
        case "session_ready":
            currentSessionPath = object["path"] as? String ?? currentSessionPath
            isAwaitingSessionActivation = false
            resetStreamingState()
            status = copy.readyStatus
        case "session_deleted":
            if let path = object["path"] as? String {
                sessions.removeAll { $0.path == path }
            }
        case "model_registry":
            updateModelRegistry(from: object)
        case "status":
            guard shouldAcceptSessionEvent(object) else { return }
            status = object["value"] as? String ?? status
            let normalizedStatus = status.lowercased()
            if status.contains("完成") || status.contains("失败") || normalizedStatus.contains("done") || normalizedStatus.contains("complete") || normalizedStatus.contains("failed") {
                isAgentWorking = false
                updateTurnWaitIndicator()
            } else if status.contains("正在") || status.contains("理解") || status.contains("整理") || status.contains("工作中") || normalizedStatus.contains("working") || normalizedStatus.contains("scanning") || normalizedStatus.contains("organizing") {
                isAgentWorking = true
                updateTurnWaitIndicator()
            }
        case "assistant_start":
            guard shouldAcceptSessionEvent(object) else { return }
            isAgentWorking = true
            let agentId = object["id"] as? String ?? UUID().uuidString
            let messageId = UUID().uuidString
            assistantMessageIdsByAgentId[agentId] = messageId
            messages.append(ChatMessage(id: messageId, role: .assistant, text: "", messageStatus: .streaming))
            updateTurnWaitIndicator()
        case "assistant_delta":
            guard shouldAcceptSessionEvent(object) else { return }
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
            guard shouldAcceptSessionEvent(object) else { return }
            if let agentId = object["id"] as? String,
               let messageId = assistantMessageIdsByAgentId[agentId],
               let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].messageStatus = .finished
            }
            updateTurnWaitIndicator()
        case "plan":
            break
        case "organized":
            guard shouldAcceptSessionEvent(object) else { return }
            if let filesRoot = object["filesRoot"] as? String {
                filesPath = filesRoot
            }
        case "tool_start":
            guard shouldAcceptSessionEvent(object) else { return }
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
            guard shouldAcceptSessionEvent(object) else { return }
            status = copy.workingStatus
            if let id = object["id"] as? String,
               let messageId = toolMessageIdsByToolId[id],
               let index = messages.firstIndex(where: { $0.id == messageId }) {
                let name = object["name"] as? String ?? messages[index].toolName
                let value = object["value"]
                let phase = object["phase"] as? String
                messages[index].toolName = name
                messages[index].toolStatus = .running
                if phase == "input" {
                    let summary = summarizeToolArgs(name: name, value: value)
                    if !summary.isEmpty {
                        messages[index].toolSummary = summary
                        messages[index].text = summary
                        if shouldAutoExpandTool(name) {
                            messages[index].toolExpanded = true
                        }
                    }
                } else {
                    let result = formatToolPayload(value)
                    if !result.isEmpty {
                        messages[index].toolResult = result
                        messages[index].text = result
                        if shouldAutoExpandTool(name) {
                            messages[index].toolExpanded = true
                        }
                    }
                }
            }
            updateTurnWaitIndicator()
        case "tool_end":
            guard shouldAcceptSessionEvent(object) else { return }
            let id = object["id"] as? String ?? UUID().uuidString
            let name = object["name"] as? String ?? "tool"
            let isError = object["isError"] as? Bool ?? false
            let result = formatToolPayload(object["result"])
            if let messageId = toolMessageIdsByToolId[id],
               let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].toolStatus = isError ? .failed : .finished
                messages[index].toolResult = result
                if !result.isEmpty {
                    messages[index].text = result
                }
                autoCollapseToolIfNeeded(messageId: messageId, name: name)
                autoCollapseFastToolIfNeeded(messageId: messageId, name: name)
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
            guard shouldAcceptSessionEvent(object) else { return }
            isAgentWorking = true
            status = copy.workingStatus
            updateTurnWaitIndicator()
        case "thinking_delta":
            guard shouldAcceptSessionEvent(object) else { return }
            isAgentWorking = true
            status = copy.workingStatus
            updateTurnWaitIndicator()
        case "thinking_end":
            guard shouldAcceptSessionEvent(object) else { return }
            updateTurnWaitIndicator()
        case "error":
            guard shouldAcceptSessionEvent(object) else { return }
            isAgentWorking = false
            updateTurnWaitIndicator()
            let message = object["message"] as? String ?? copy.unknownError
            messages.append(ChatMessage(id: UUID().uuidString, role: .system, text: "\(copy.agentErrorPrefix): \(message)"))
        default:
            break
        }
    }

    private var currentLanguage: QuietLanguage {
        QuietLanguage.normalized(language)
    }

    var copy: QuietCopy {
        quietCopy(currentLanguage)
    }

    private func resetStreamingState() {
        isAgentWorking = false
        showTurnWaitIndicator = false
        assistantMessageIdsByAgentId.removeAll()
        toolMessageIdsByToolId.removeAll()
        turnWaitTask?.cancel()
        turnWaitTask = nil
    }

    private func shouldAcceptSessionEvent(_ object: [String: Any]) -> Bool {
        guard let eventSessionPath = object["sessionPath"] as? String,
              !eventSessionPath.isEmpty else {
            return !isAwaitingSessionActivation
        }

        guard !isAwaitingSessionActivation else { return false }
        return eventSessionPath == currentSessionPath
    }

    private func resetHistoryPagination() {
        hasMoreHistory = false
        isLoadingHistory = false
        lastHistoryLoadAt = .distantPast
        pendingHistoryAnchorMessageId = nil
        historyAnchorMessageId = nil
    }

    private func updateSessionList(from object: [String: Any]) {
        currentSessionPath = object["currentPath"] as? String ?? currentSessionPath
        let rawSessions = object["sessions"] as? [[String: Any]] ?? []
        sessions = rawSessions.compactMap { raw in
            guard let id = raw["id"] as? String,
                  let path = raw["path"] as? String else {
                return nil
            }
            let title = (raw["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let modified = raw["modified"] as? String ?? ""
            let messageCount = raw["messageCount"] as? Int ?? 0
            return QuietSessionSummary(
                id: id,
                path: path,
                title: title?.isEmpty == false ? title! : "新会话",
                modified: modified,
                messageCount: messageCount
            )
        }
    }

    private func restoreMessages(from rawMessages: [[String: Any]]) {
        let restored = sessionMessages(from: rawMessages)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            messages = restored
        }
    }

    private func mergeSessionHistoryBatch(_ rawMessages: [[String: Any]], prepend: Bool) -> Bool {
        let incoming = sessionMessages(from: rawMessages)
        guard !incoming.isEmpty else { return false }
        let existingIds = Set(messages.map(\.id))
        let uniqueIncoming = incoming.filter { !existingIds.contains($0.id) }
        guard !uniqueIncoming.isEmpty else { return false }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if prepend {
                messages.insert(contentsOf: uniqueIncoming, at: 0)
            } else {
                messages.append(contentsOf: uniqueIncoming)
            }
        }
        return true
    }

    private func sessionMessages(from rawMessages: [[String: Any]]) -> [ChatMessage] {
        rawMessages.compactMap { raw -> ChatMessage? in
            guard let text = raw["text"] as? String else { return nil }
            let id = raw["id"] as? String ?? UUID().uuidString
            switch raw["role"] as? String {
            case "user":
                return ChatMessage(id: id, role: .user, text: text, usesPlainTextRendering: true)
            case "assistant":
                return ChatMessage(id: id, role: .assistant, text: text)
            default:
                return nil
            }
        }
    }

    private func updateModelRegistry(from object: [String: Any]) {
        guard let providers = object["providers"] as? [[String: Any]] else { return }
        modelProviders = providers.compactMap { providerObject in
            guard let id = providerObject["id"] as? String else { return nil }
            let name = providerObject["name"] as? String ?? id
            let models = (providerObject["models"] as? [[String: Any]] ?? []).compactMap { modelObject -> AvailableModel? in
                let provider = modelObject["provider"] as? String ?? id
                guard let modelId = modelObject["modelId"] as? String else { return nil }
                let name = modelObject["name"] as? String ?? modelId
                let label = modelObject["label"] as? String ?? name
                let thinkingLevels = modelObject["thinkingLevels"] as? [String] ?? ["off"]
                return AvailableModel(
                    id: "\(provider)/\(modelId)",
                    provider: provider,
                    modelId: modelId,
                    name: name,
                    label: label,
                    thinkingLevels: normalizedThinkingLevels(thinkingLevels)
                )
            }
            return ModelProviderOption(id: id, name: name, models: models)
        }
        if let selectedProvider = modelProviders.first(where: { $0.id == modelProvider }),
           !selectedProvider.models.contains(where: { $0.modelId == modelId }),
           let firstModel = selectedProvider.models.first {
            modelId = firstModel.modelId
        } else if !modelProviders.contains(where: { $0.id == modelProvider }),
                  let firstProvider = modelProviders.first {
            modelProvider = firstProvider.id
            modelId = firstProvider.models.first?.modelId ?? modelId
        }
        thinkingLevel = clampedThinkingLevel(thinkingLevel, forProvider: modelProvider, modelId: modelId)
    }

    private func normalizedThinkingLevels(_ levels: [String]) -> [String] {
        let knownLevels = Set(quietThinkingLevelOrder)
        let uniqueLevels = levels.reduce(into: [String]()) { result, level in
            let normalized = level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard knownLevels.contains(normalized), !result.contains(normalized) else { return }
            result.append(normalized)
        }
        let sortedLevels = uniqueLevels.sorted {
            (quietThinkingLevelOrder.firstIndex(of: $0) ?? Int.max) < (quietThinkingLevelOrder.firstIndex(of: $1) ?? Int.max)
        }
        return sortedLevels.isEmpty ? ["off"] : sortedLevels
    }

    private func clampedThinkingLevel(_ level: String, forProvider provider: String, modelId: String) -> String {
        let levels = modelProviders
            .first(where: { $0.id == provider })?
            .models
            .first(where: { $0.modelId == modelId })?
            .thinkingLevels ?? ["off", "minimal", "low", "medium", "high"]
        return closestThinkingLevel(to: level, in: levels)
    }

    private func bundledNodeURL() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("node"),
            bundledResourceURL(path: "node"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func bundledResourceURL(path: String) -> URL? {
        let bundleName = "Quiet_QuietMenuBar.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName).appendingPathComponent("Resources").appendingPathComponent(path),
            Bundle.main.bundleURL.appendingPathComponent(bundleName).appendingPathComponent("Resources").appendingPathComponent(path),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent(path),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func mergedPath() -> String {
        let defaults = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
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
        quietApplicationSupportURL()
    }

    private func johnnyDecimalAreaCategorySpecs() -> [(area: String, categories: [String])] {
        [
            ("10-19 Personal 个人", [
                "10 Management of area 10-19",
                "11 Identity & personal records 身份与个人记录",
                "12 Health 医疗健康",
                "13 Family & household 家庭与家务",
                "14 Education & learning 教育学习",
                "15 Travel & immigration 旅行与出入境",
                "16 Personal correspondence 个人通信",
                "17 Hobbies & interests 兴趣爱好",
                "18 Someday personal 个人将来事项",
                "19 Personal archive 个人归档",
            ]),
            ("20-29 Money 财务", [
                "20 Management of area 20-29",
                "21 Accounts & banking 账户与银行",
                "22 Bills & invoices 账单与发票",
                "23 Expenses & reimbursements 支出与报销",
                "24 Tax 税务",
                "25 Payroll & income 薪资与收入",
                "26 Budgets & planning 预算与计划",
                "27 Investments 投资",
                "28 Accounting & statements 会计与报表",
                "29 Money archive 财务归档",
            ]),
            ("30-39 Work 工作", [
                "30 Management of area 30-39",
                "31 Projects 项目",
                "32 Meetings 会议",
                "33 Vendors & partners 供应商与合作方",
                "34 Reports & analysis 报告与分析",
                "35 Operations & processes 运营与流程",
                "36 Product & research 产品与研究",
                "37 People & HR 人员与人事",
                "38 Someday work 工作将来事项",
                "39 Work archive 工作归档",
            ]),
            ("40-49 Legal & Admin 法务行政", [
                "40 Management of area 40-49",
                "41 Contracts 合同",
                "42 Government & compliance 政务与合规",
                "43 Insurance 保险",
                "44 Certificates & licenses 证明与证照",
                "45 Legal cases & disputes 案件与争议",
                "46 Company admin 公司行政",
                "47 Policies & procedures 制度与流程",
                "48 Someday legal admin 法务行政将来事项",
                "49 Legal admin archive 法务行政归档",
            ]),
            ("50-59 Assets & Property 资产", [
                "50 Management of area 50-59",
                "51 Real estate 房产",
                "52 Vehicles 车辆",
                "53 Devices & equipment 设备",
                "54 Warranties & manuals 保修与手册",
                "55 Inventory & valuables 库存与贵重物品",
                "56 Maintenance & repairs 维护与维修",
                "57 Purchases & receipts 采购与票据",
                "58 Someday assets 资产将来事项",
                "59 Assets archive 资产归档",
            ]),
            ("90-99 Archive 归档", [
                "90 Management of area 90-99",
                "91 Personal archive 个人归档",
                "92 Money archive 财务归档",
                "93 Work archive 工作归档",
                "94 Legal admin archive 法务行政归档",
                "95 Assets archive 资产归档",
                "96 Old projects 旧项目",
                "97 Backups 备份",
                "98 Historical reference 历史参考",
                "99 General archive 总归档",
            ]),
        ]
    }

    private func johnnyDecimalDirectories() -> [String] {
        var dirs = [
            "00-09 System-management area/00 System-management category/00.00 JDex for the system",
            "00-09 System-management area/00 System-management category/00.01 Inbox for the system",
            "00-09 System-management area/00 System-management category/00.02 Task & project management for the system",
            "00-09 System-management area/00 System-management category/00.03 Templates for the system",
            "00-09 System-management area/00 System-management category/00.04 Links for the system",
            "00-09 System-management area/00 System-management category/00.09 Archive for the system",
        ]
        for spec in johnnyDecimalAreaCategorySpecs() {
            dirs.append(spec.area)
            for category in spec.categories {
                let categoryNumber = String(category.prefix(2))
                let scope = categoryNumber.hasSuffix("0")
                    ? "area \(categoryNumber.prefix(1))0-\(categoryNumber.prefix(1))9"
                    : "category \(categoryNumber)"
                let categoryPath = "\(spec.area)/\(category)"
                dirs.append(categoryPath)
                dirs.append("\(categoryPath)/\(categoryNumber).00 JDex for \(scope)")
                dirs.append("\(categoryPath)/\(categoryNumber).01 Inbox for \(scope)")
                dirs.append("\(categoryPath)/\(categoryNumber).02 Task & project management for \(scope)")
                dirs.append("\(categoryPath)/\(categoryNumber).03 Templates for \(scope)")
                dirs.append("\(categoryPath)/\(categoryNumber).04 Links for \(scope)")
                dirs.append("\(categoryPath)/\(categoryNumber).09 Archive for \(scope)")
            }
        }
        return dirs
    }

    private func johnnyDecimalCategoryMap() -> String {
        johnnyDecimalAreaCategorySpecs()
            .map { spec in
                ([ "- `\(spec.area)`" ] + spec.categories.map { "  - `\($0)`" }).joined(separator: "\n")
            }
            .joined(separator: "\n")
    }

    private func contentDirectory() -> URL {
        let url = quietContentRootURL()
        johnnyDecimalDirectories().forEach { name in
            try? FileManager.default.createDirectory(at: url.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
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
        let path = filesPath.isEmpty ? contentDirectory().path : filesPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func openMemoryFile() {
        let url = applicationSupportDirectory().appendingPathComponent("memory.md", isDirectory: false)
        if !FileManager.default.fileExists(atPath: url.path) {
            let defaultMemory = """
            # Quiet Memory

            These are user-editable resource organizing rules for Quiet.

            ## Learning User Preferences

            - When the user expresses a stable preference for how resources should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
            - Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
            - Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
            - This file is located at `QUIET_HOME/memory.md`; you may edit it with bash when updating remembered organizing preferences.

            ## Default Method: Johnny.Decimal System

            This is Quiet's default organizing method. If the user explicitly prefers another method, replace this section with that method.

            More information: https://johnnydecimal.com/

            These pre-created management and standard-zero folders are primarily for the agent's consistency. Users do not need to maintain them manually.

            - Use Quiet's Johnny.Decimal structure directly.
            - New drops enter `00-09 System-management area/00 System-management category/00.01 Inbox for the system`.
            - The JDex lives in `00-09 System-management area/00 System-management category/00.00 JDex for the system`.
            - In-progress or unfiled resources stay in the most specific `.01 Inbox`.
            - Tasks and project-management material belongs in the most specific `.02 Task & project management`.
            - Templates belong in the most specific `.03 Templates`.
            - Links belong in the most specific `.04 Links`.
            - Completed or inactive material that should not be organised belongs in the most specific `.09 Archive`.
            - Prefer existing numbered areas over creating new top-level folders.
            - Do not create or use `.05`, `.06`, `.07`, or `.08`; these are reserved.

            ## Default Areas and Categories

            \(johnnyDecimalCategoryMap())

            ## Destination Pattern

            `QUIET_CONTENT_HOME/<area>/<category>/<AC.ID standard-zero-or-specific-ID>/<original-name>`

            ## Conversation Style

            - Be concise.
            - Tell the user what was captured, moved, and where.
            - When a problem occurs, name the failed file and continue with the rest.
            - Always respond in user's language.
            """
            try? defaultMemory.appending("\n").write(to: url, atomically: true, encoding: .utf8)
        } else if let memory = try? String(contentsOf: url, encoding: .utf8) {
            let preferenceGuidance = """

            ## Learning User Preferences

            - When the user expresses a stable preference for how resources should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
            - Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
            - Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
            - This file is located at `QUIET_HOME/memory.md`; you may edit it with bash when updating remembered organizing preferences.
            """
            let johnnyDecimalGuidance = """

            ## Default Method: Johnny.Decimal System

            This is Quiet's default organizing method. If the user explicitly prefers another method, replace this section with that method.

            More information: https://johnnydecimal.com/

            These pre-created management and standard-zero folders are primarily for the agent's consistency. Users do not need to maintain them manually.

            - Use Quiet's Johnny.Decimal structure directly.
            - New drops enter `00-09 System-management area/00 System-management category/00.01 Inbox for the system`.
            - The JDex lives in `00-09 System-management area/00 System-management category/00.00 JDex for the system`.
            - In-progress or unfiled resources stay in the most specific `.01 Inbox`.
            - Tasks and project-management material belongs in the most specific `.02 Task & project management`.
            - Templates belong in the most specific `.03 Templates`.
            - Links belong in the most specific `.04 Links`.
            - Completed or inactive material that should not be organised belongs in the most specific `.09 Archive`.
            - Prefer existing numbered areas over creating new top-level folders.
            - Do not create or use `.05`, `.06`, `.07`, or `.08`; these are reserved.

            ## Default Areas and Categories

            \(johnnyDecimalCategoryMap())

            ## Destination Pattern

            `QUIET_CONTENT_HOME/<area>/<category>/<AC.ID standard-zero-or-specific-ID>/<original-name>`
            """
            var migrated = memory.trimmingCharacters(in: .whitespacesAndNewlines)
            if !migrated.contains("## Learning User Preferences") {
                migrated.append(preferenceGuidance)
            }
            if let taxonomyRange = migrated.range(
                of: #"(?s)\n## (Subject Taxonomy|Quiet Decimal Taxonomy)\n.*?(?=\n## Conversation Style|\n## Learning User Preferences|$)"#,
                options: .regularExpression
            ) {
                migrated.replaceSubrange(taxonomyRange, with: "\n" + johnnyDecimalGuidance + "\n")
            } else if !migrated.contains("## Default Method: Johnny.Decimal System")
                || !migrated.contains("## Default Areas and Categories")
                || migrated.contains("## Johnny.Decimal System")
                || !migrated.contains("https://johnnydecimal.com/")
                || migrated.contains("Inbox for Blackhole")
                || migrated.contains("Index for Blackhole")
                || migrated.contains("Inbox for Quiet")
                || migrated.contains("Index for Quiet")
                || migrated.contains("Someday material belongs")
                || migrated.contains("00-09 System management/00 System management") {
                if let conversationRange = migrated.range(of: "\n## Conversation Style") {
                    if let currentRange = migrated.range(
                        of: #"(?s)\n## (Default Method: Johnny\.Decimal System|Johnny\.Decimal System)\n.*?(?=\n## Conversation Style|\n## Learning User Preferences|$)"#,
                        options: .regularExpression
                    ) {
                        migrated.replaceSubrange(currentRange, with: "\n" + johnnyDecimalGuidance + "\n")
                    } else {
                        migrated.insert(contentsOf: "\n" + johnnyDecimalGuidance + "\n", at: conversationRange.lowerBound)
                    }
                } else {
                    migrated.append("\n")
                    migrated.append(johnnyDecimalGuidance)
                }
            }
            migrated = migrated.replacingOccurrences(
                of: "`QUIET_CONTENT_HOME/<subject>/<original-name>`",
                with: "`QUIET_CONTENT_HOME/<area>/<category>/<AC.ID standard-zero-or-specific-ID>/<original-name>`"
            )
            migrated = migrated.replacingOccurrences(
                of: "`QUIET_CONTENT_HOME/<numbered-area>/<numbered-category-or-topic>/<original-name>`",
                with: "`QUIET_CONTENT_HOME/<area>/<category>/<AC.ID standard-zero-or-specific-ID>/<original-name>`"
            )
            migrated = migrated
                .replacingOccurrences(of: "Blackhole", with: "Quiet")
                .replacingOccurrences(of: "blackhole", with: "quiet")
                .replacingOccurrences(of: "~/.quiet", with: "~/.quiet")
                .replacingOccurrences(of: "~/Documents/Quiet", with: "~/Documents/Quiet")
            migrated = migrated.replacingOccurrences(
                of: "\n- Do not mention internal logs, manifests, or implementation files unless the user asks.",
                with: ""
            )
            if migrated.contains("## Conversation Style")
                && !migrated.contains("Always respond in user's language.") {
                migrated.append("\n- Always respond in user's language.")
            }
            if migrated.appending("\n") != memory {
                try? migrated.appending("\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
        NSWorkspace.shared.open(url)
    }

    func applyAppearanceMode(_ mode: QuietAppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: quietAppearanceModeKey)
        NotificationCenter.default.post(name: .quietAppearanceDidChange, object: mode.rawValue)
    }

    func applyLanguage(_ nextLanguage: QuietLanguage) {
        language = nextLanguage.rawValue
        UserDefaults.standard.set(language, forKey: "quiet.language")
    }

    func saveSettings(language: String, provider: String, model: String, apiKey: String, thinking: String, appearance: String) {
        let nextLanguage = QuietLanguage.normalized(language)
        let nextProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextThinking = clampedThinkingLevel(thinking, forProvider: nextProvider, modelId: nextModel)
        let nextAppearance = QuietAppearanceMode.normalized(appearance)
        guard !nextProvider.isEmpty, !nextModel.isEmpty else { return }

        let shouldRestart = modelProvider != nextProvider
            || modelId != nextModel
            || modelApiKey != nextApiKey
            || thinkingLevel != nextThinking

        applyLanguage(nextLanguage)
        modelProvider = nextProvider
        modelId = nextModel
        modelApiKey = nextApiKey
        thinkingLevel = nextThinking
        applyAppearanceMode(nextAppearance)
        UserDefaults.standard.set(modelProvider, forKey: "quiet.model.provider")
        UserDefaults.standard.set(modelId, forKey: "quiet.model.id")
        QuietSecrets.saveModelApiKey(modelApiKey)
        UserDefaults.standard.removeObject(forKey: quietLegacyModelApiKeyKey)
        UserDefaults.standard.set(thinkingLevel, forKey: "quiet.thinking.level")
        if shouldRestart {
            restartAgent()
        }
    }

    private func restartAgent() {
        isRestartingAgent = true
        isAgentReady = false
        isAgentWorking = false
        showTurnWaitIndicator = false
        status = copy.switchingModelStatus
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

    private func autoCollapseFastToolIfNeeded(messageId: String, name: String) {
        guard !shouldAutoExpandTool(name) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self,
                  let index = self.messages.firstIndex(where: { $0.id == messageId }),
                  self.messages[index].role == .tool,
                  self.messages[index].toolStatus != .running else {
                return
            }
            self.messages[index].toolExpanded = false
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
            return stringifyJSON(value).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if shouldAutoExpandTool(name) {
            return stringifyJSON(dict).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if name == "bash", let command = dict["command"] as? String {
            return command.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let path = dict["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return stringifyJSON(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func summarizeToolResult(_ value: Any?) -> String {
        return truncateText(formatToolPayload(value), maxLength: 120)
    }

    private func formatToolPayload(_ value: Any?) -> String {
        guard let dict = value as? [String: Any],
              let content = dict["content"] as? [[String: Any]] else {
            return stringifyJSON(value).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

struct QuietView: View {
    @StateObject private var store = AgentStore()
    @State private var isInputFocused = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 1
    @State private var scrollbarContentHeight: CGFloat = 1
    @State private var scrollViewportHeight: CGFloat = 1
    @State private var isScrollbarStabilizing = false
    @State private var scrollbarStabilizationToken = 0
    @State private var isFollowingLatest = true
    @State private var showFollowButton = false
    @State private var isRestoringFollow = false
    @State private var followRestoreToken = 0
    @State private var latestScrollToken = 0
    @State private var isFollowPausedByUser = false
    @State private var isSettingsPresented = false
    @State private var settingsApiKeyFocusRequest = 0
    @State private var showCredentialPrompt = false
    @State private var isDropTargeted = false
    @State private var composerInputHeight: CGFloat = 19
    @State private var isSidebarPresented = false
    @State private var isDesktopChromePresented = false

    private var headerLeadingInset: CGFloat {
        isDesktopChromePresented ? quietDesktopHeaderLeadingInset : 0
    }

    private func sidebarWidth(for width: CGFloat) -> CGFloat {
        if isDesktopChromePresented {
            return min(340, max(280, width * 0.28))
        }
        return min(224, max(168, width * 0.72))
    }

    var body: some View {
        Group {
            if isSettingsPresented {
                SettingsPanel(store: store, focusApiKeyRequest: settingsApiKeyFocusRequest) {
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
        .frame(minWidth: quietWindowMinimumSize.width, minHeight: quietWindowMinimumSize.height)
        .overlay {
            if isDropTargeted {
                FileDropTargetOverlay(text: store.copy.dropOverlay)
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .overlay {
            if showCredentialPrompt {
                CredentialPromptOverlay(store: store) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showCredentialPrompt = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(10)
            }
        }
        .background(Color(nsColor: quietWindowFill))
        .background(PasteboardShortcutCatcher {
            handleConversationPaste()
        })
        .ignoresSafeArea(.container, edges: .top)
        .onDrop(of: quietDropTypeIdentifiers, isTargeted: $isDropTargeted, perform: store.handleDrop)
        .onReceive(NotificationCenter.default.publisher(for: .quietFocusComposer)) { _ in
            guard !isSettingsPresented else { return }
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .quietWindowChromeModeDidChange)) { notification in
            isDesktopChromePresented = (notification.object as? Bool) == true
        }
        .onChange(of: store.inputText) { _, text in
            if text.isEmpty {
                store.inputContainsPastedResource = false
            }
        }
        .preferredColorScheme(store.appearanceMode.colorScheme)
    }

    private var chatPage: some View {
        GeometryReader { geometry in
            let sidebarWidth = sidebarWidth(for: geometry.size.width)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: quietHeaderHeight)

                    messageList

                    composer
                }

                if isSidebarPresented {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .frame(width: max(0, geometry.size.width - sidebarWidth), height: geometry.size.height)
                        .offset(x: sidebarWidth)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isSidebarPresented = false
                            }
                        }
                        .zIndex(1)
                }

                if isSidebarPresented {
                    SessionOverlayPanel(
                        sessions: store.sessions,
                        currentSessionPath: store.currentSessionPath,
                        topContentInset: quietHeaderHeight + 8,
                        onSelect: { session in
                            store.openSession(session)
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isSidebarPresented = false
                            }
                        },
                        onDelete: { session in
                            store.deleteSession(session)
                        }
                    )
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea()
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(2)
                }

                header
                    .zIndex(3)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.easeInOut(duration: 0.18), value: isSidebarPresented)
    }

    private var messageList: some View {
        GeometryReader { viewport in
            ZStack(alignment: .trailing) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        ZStack(alignment: .bottom) {
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ChatScrollMetricsReader(
                                        onChange: { offset, viewportHeight, contentHeight in
                                        updateScrollMetrics(
                                            offset: offset,
                                            viewportHeight: viewportHeight,
                                            contentHeight: contentHeight
                                        )
                                        },
                                        onUserScroll: {
                                            handleUserScrollInMessages()
                                        }
                                    )
                                    .frame(width: 0, height: 0)
                                    .allowsHitTesting(false)

                                    if store.isLoadingHistory {
                                        HStack {
                                            Spacer(minLength: 0)
                                            ProgressView()
                                                .controlSize(.small)
                                                .scaleEffect(0.72)
                                                .frame(width: 18, height: 18)
                                            Spacer(minLength: 0)
                                        }
                                        .frame(height: 24)
                                        .transition(.opacity)
                                    }

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
                                        .frame(height: 64)
                                        .id(messageBottomAnchorId)
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 2)
                                .padding(.bottom, 4)
                                .frame(width: viewport.size.width, alignment: .leading)
                            }
                            .coordinateSpace(name: "quietMessages")
                            .onChange(of: store.messages.last?.id) { _, id in
                                if isFollowingLatest, id != nil {
                                    pinLatestAfterLayout(proxy: proxy)
                                }
                            }
                            .onChange(of: store.messages.last?.text) { _, _ in
                                guard isFollowingLatest else { return }
                                pinLatestAfterLayout(proxy: proxy)
                            }
                            .onChange(of: store.messages) { _, _ in
                                guard isFollowingLatest else { return }
                                pinLatestAfterLayout(proxy: proxy)
                            }
                            .onChange(of: store.showTurnWaitIndicator) { _, isVisible in
                                guard isFollowingLatest, isVisible else { return }
                                pinLatestAfterLayout(proxy: proxy)
                            }
                            .onChange(of: store.sessionScrollRequest) { _, _ in
                                beginScrollbarStabilization()
                                isFollowPausedByUser = false
                                isFollowingLatest = true
                                showFollowButton = false
                                var transaction = Transaction(animation: nil)
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
                                }
                                DispatchQueue.main.async {
                                    var nextTransaction = Transaction(animation: nil)
                                    nextTransaction.disablesAnimations = true
                                    withTransaction(nextTransaction) {
                                        proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
                                    }
                                }
                            }
                            .onChange(of: store.historyAnchorScrollRequest) { _, _ in
                                guard let anchorId = store.historyAnchorMessageId else { return }
                                DispatchQueue.main.async {
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        proxy.scrollTo(anchorId, anchor: .top)
                                    }
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .quietRestoreFollowLatest)) { _ in
                                restoreFollowToLatest(proxy: proxy)
                            }

                            if store.messages.isEmpty && !store.isLoadingHistory && !store.showTurnWaitIndicator {
                                EmptyConversationHint()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.bottom, 28)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }

                            if showFollowButton {
                                HStack {
                                    Spacer(minLength: 0)
                                    Button {
                                        restoreFollowToLatest(proxy: proxy)
                                    } label: {
                                        LucideIcon(id: "arrow-down", fallbackSystemName: "arrow.down")
                                            .frame(width: 15, height: 15)
                                            .frame(width: 30, height: 30)
                                            .foregroundStyle(quietSecondaryButtonText)
                                            .background(quietSecondaryButtonFill, in: Circle())
                                            .overlay {
                                                Circle().stroke(quietSecondaryButtonBorder, lineWidth: 0.8)
                                            }
                                            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
                                    }
                                    .buttonStyle(.plain)
                                    .help("跟随到最新")
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 10)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .zIndex(2)
                            }
                        }

                    }
                }
            }
            .onAppear {
                scrollViewportHeight = viewport.size.height
                scrollbarContentHeight = scrollContentHeight
            }
            .onChange(of: viewport.size.height) { _, height in
                scrollViewportHeight = height
                if !isScrollbarStabilizing {
                    scrollbarContentHeight = scrollContentHeight
                }
                updateFollowState(offset: scrollOffset, contentHeight: scrollContentHeight, viewportHeight: height)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isDropTargeted)
    }

    private func updateScrollMetrics(offset: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat) {
        scrollOffset = offset
        scrollViewportHeight = viewportHeight

        let height = max(1, contentHeight)

        if abs(scrollContentHeight - height) > 0.5 {
            let previousHeight = scrollContentHeight
            scrollContentHeight = height
            if isScrollbarStabilizing {
                scheduleScrollbarStabilizationSettle()
            } else {
                scrollbarContentHeight = height
            }
            if isFollowingLatest, height >= previousHeight {
                showFollowButton = false
                return
            }
        }

        if updatePausedFollowState(offset: offset, contentHeight: height, viewportHeight: viewportHeight) {
            if offset < 90,
               height > viewportHeight + 8 {
                store.loadMoreHistoryIfNeeded()
            }
            return
        }

        updateFollowState(offset: offset, contentHeight: height, viewportHeight: viewportHeight)
        if offset < 90,
           height > viewportHeight + 8,
           !isFollowingLatest {
            store.loadMoreHistoryIfNeeded()
        }
    }

    private func beginScrollbarStabilization() {
        isScrollbarStabilizing = true
        scrollbarContentHeight = max(scrollViewportHeight, scrollContentHeight)
        scheduleScrollbarStabilizationSettle()
    }

    private func scheduleScrollbarStabilizationSettle() {
        scrollbarStabilizationToken += 1
        let token = scrollbarStabilizationToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard token == scrollbarStabilizationToken else { return }
            scrollbarContentHeight = scrollContentHeight
            isScrollbarStabilizing = false
        }
    }

    private func handleUserScrollInMessages() {
        guard scrollContentHeight > scrollViewportHeight + 8 else {
            return
        }
        stopFollowingForUserScroll()
    }

    private func stopFollowingForUserScroll() {
        followRestoreToken += 1
        latestScrollToken += 1
        isRestoringFollow = false
        isFollowPausedByUser = true
        isFollowingLatest = false
        showFollowButton = true
    }

    private func restoreFollowToLatest(proxy: ScrollViewProxy) {
        followRestoreToken += 1
        let token = followRestoreToken
        isRestoringFollow = true
        isFollowPausedByUser = false
        isFollowingLatest = true
        showFollowButton = false

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
        }

        DispatchQueue.main.async {
            guard token == followRestoreToken else { return }
            proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard token == followRestoreToken else { return }
            proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            guard token == followRestoreToken else { return }
            isRestoringFollow = false
            updateFollowState(
                offset: scrollOffset,
                contentHeight: scrollContentHeight,
                viewportHeight: scrollViewportHeight
            )
        }
    }

    private func pinLatestAfterLayout(proxy: ScrollViewProxy) {
        latestScrollToken += 1
        let token = latestScrollToken
        isRestoringFollow = true
        showFollowButton = false

        scrollToLatestWithoutAnimation(proxy: proxy)

        DispatchQueue.main.async {
            guard token == latestScrollToken else { return }
            scrollToLatestWithoutAnimation(proxy: proxy)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard token == latestScrollToken else { return }
            scrollToLatestWithoutAnimation(proxy: proxy)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard token == latestScrollToken else { return }
            isRestoringFollow = false
            updateFollowState(
                offset: scrollOffset,
                contentHeight: scrollContentHeight,
                viewportHeight: scrollViewportHeight
            )
        }
    }

    private func scrollToLatestWithoutAnimation(proxy: ScrollViewProxy) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
        }
    }

    private func updateFollowState(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let isScrollable = contentHeight > viewportHeight + 8
        guard isScrollable else {
            isFollowPausedByUser = false
            isFollowingLatest = true
            showFollowButton = false
            return
        }
        let distanceFromBottom = contentHeight - offset - viewportHeight
        let isAtLatest = distanceFromBottom < 28
        if isAtLatest {
            isFollowingLatest = true
            showFollowButton = false
        } else if isFollowingLatest {
            showFollowButton = false
        } else {
            isFollowingLatest = false
            showFollowButton = true
        }
    }

    private func updatePausedFollowState(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        guard isFollowPausedByUser else { return false }

        let isScrollable = contentHeight > viewportHeight + 8
        guard isScrollable else {
            isFollowPausedByUser = false
            isFollowingLatest = true
            showFollowButton = false
            return true
        }

        let distanceFromBottom = contentHeight - offset - viewportHeight
        if distanceFromBottom <= 2 {
            isFollowPausedByUser = false
            isFollowingLatest = true
            showFollowButton = false
        } else {
            isFollowingLatest = false
            showFollowButton = true
        }
        return true
    }

    private func scrollToProgress(_ progress: CGFloat, proxy: ScrollViewProxy) {
        let clampedProgress = min(max(progress, 0), 1)
        if clampedProgress >= 0.985 || store.messages.isEmpty {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(messageBottomAnchorId, anchor: .bottom)
            }
            return
        }

        let lastIndex = max(0, store.messages.count - 1)
        let index = min(lastIndex, max(0, Int((clampedProgress * CGFloat(lastIndex)).rounded())))
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(store.messages[index].id, anchor: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarPresented.toggle()
                }
                if isSidebarPresented {
                    store.requestSessionList()
                }
            } label: {
                GlassIconButtonLabel(iconId: "panel-left", fallbackSystemName: "sidebar.left", size: 30, iconSize: 14)
            }
            .buttonStyle(.plain)
            .help(isSidebarPresented ? "收起会话列表" : "展开会话列表")

            Text(quietAppName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(quietChatText)
                .shadow(color: .black.opacity(0.22), radius: 0.35, x: 0, y: 0.35)

            Spacer()

            Button {
                store.startNewSession()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .quietFocusComposer, object: nil)
                }
            } label: {
                GlassIconButtonLabel(iconId: "plus", fallbackSystemName: "plus", size: 30, iconSize: 15)
            }
            .buttonStyle(.plain)
            .help(store.copy.newSession)

            Menu {
                Button {
                    store.openFiles()
                } label: {
                    Label(store.copy.openFiles, systemImage: "folder")
                }

                Button {
                    NotificationCenter.default.post(name: .quietOpenDesktopClient, object: nil)
                } label: {
                    Label(store.copy.openDesktopClient, systemImage: "macwindow")
                }

                Button {
                    store.openMemoryFile()
                } label: {
                    Label(store.copy.editQuietRules, systemImage: "square.and.pencil")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSettingsPresented = true
                    }
                } label: {
                    Label(store.copy.settingsTitle, systemImage: "gearshape")
                }

                Divider()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(store.copy.quit, systemImage: "power")
                }
            } label: {
                GlassIconButtonLabel(iconId: "ellipsis", fallbackSystemName: "ellipsis", size: 30, iconSize: 15)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help(store.copy.moreActions)
        }
        .padding(.leading, 16 + headerLeadingInset)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(HeaderDragRegion())
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ComposerTextView(
                text: $store.inputText,
                placeholder: store.copy.composerPlaceholder,
                isFocused: $isInputFocused,
                measuredHeight: $composerInputHeight,
                onPaste: {
                    store.inputContainsPastedResource = true
                },
                onPasteCapturedContent: { paths, resources in
                    handleCapturedPaste(paths: paths, resources: resources)
                },
                onSubmit: {
                    submitCurrentMessage()
                }
            )
                .frame(height: composerInputHeight)
                .padding(.leading, 13)
                .padding(.vertical, 8)

            Button {
                submitCurrentMessage()
            } label: {
                LucideIcon(id: "arrow-up", fallbackSystemName: "arrow.up")
                    .foregroundStyle(quietPrimaryText)
                    .frame(width: 15, height: 15)
                    .frame(width: 30, height: 30)
                    .background(quietPrimaryFill, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
        }
        .frame(maxWidth: .infinity)
        .background(quietComposerFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(isInputFocused ? quietChatText.opacity(0.12) : quietHairline.opacity(0.62), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.045), radius: 1.2, x: 0, y: 0.45)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color(nsColor: quietWindowFill))
    }

    private func submitCurrentMessage() {
        guard store.hasUsableModelCredential else {
            withAnimation(.easeInOut(duration: 0.18)) {
                showCredentialPrompt = true
            }
            return
        }
        store.sendCurrentMessage()
    }

    private func handleCapturedPaste(paths: [String], resources: [CapturedResource]) {
        guard store.hasUsableModelCredential else {
            withAnimation(.easeInOut(duration: 0.18)) {
                showCredentialPrompt = true
            }
            return
        }
        store.sendCapturedContent(paths: paths, resources: resources)
    }

    private func handleConversationPaste() -> Bool {
        guard store.hasUsableModelCredential else {
            withAnimation(.easeInOut(duration: 0.18)) {
                showCredentialPrompt = true
            }
            return true
        }
        return store.sendCapturedPasteboardContent()
    }
}

struct EmptyConversationHint: View {
    var body: some View {
        VStack(spacing: 10) {
            LucideIcon(id: "keyboard", fallbackSystemName: "keyboard")
                .frame(width: 22, height: 22)
                .foregroundStyle(quietChatMutedText.opacity(0.72))

            Text("使用 `Alt` + `Space` 快捷唤出 `Quiet`")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(quietChatMutedText.opacity(0.86))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 260)
    }
}

struct FileDropTargetOverlay: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            LucideIcon(id: "upload-cloud", fallbackSystemName: "icloud.and.arrow.up")
                .foregroundStyle(quietNonUserMessageText.opacity(0.86))
                .frame(width: 24, height: 24)

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(quietNonUserMessageText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(quietSelectedFill.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    quietNonUserBubbleBorder,
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [7, 6])
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
        .allowsHitTesting(false)
    }
}

struct CredentialPromptOverlay: View {
    @ObservedObject var store: AgentStore
    let onSaved: () -> Void

    @State private var provider = "deepseek"
    @State private var model = "deepseek-v4-flash"
    @State private var apiKey = ""
    @State private var thinking = "off"
    @FocusState private var isApiKeyFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("需要 API Key")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(quietChatText)
                        Text("请选择模型并填入 API Key，保存后即可使用。")
                            .font(.system(size: 11))
                            .foregroundStyle(quietSubtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 42)

                    Button(action: onSaved) {
                        LucideIcon(id: "x", fallbackSystemName: "xmark")
                            .frame(width: 12, height: 12)
                            .foregroundStyle(quietChatText.opacity(0.84))
                            .frame(width: 28, height: 28)
                            .background(quietSelectedFill, in: Circle())
                            .overlay {
                                Circle().stroke(quietHairline, lineWidth: 0.6)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("关闭")
                }

                SettingsPickerField(
                    title: store.copy.provider,
                    selection: $provider,
                    options: providerOptions.map { (value: $0.id, label: $0.name) }
                )
                .onChange(of: provider) { _, nextProvider in
                    let nextModels = providerOptions.first(where: { $0.id == nextProvider })?.models ?? []
                    model = nextModels.first?.modelId ?? "deepseek-v4-flash"
                    thinking = closestThinkingLevel(to: thinking, in: nextModels.first?.thinkingLevels ?? ["off"])
                }

                SettingsPickerField(
                    title: store.copy.model,
                    selection: $model,
                    options: modelOptions.map { (value: $0.modelId, label: $0.label) }
                )
                .onChange(of: model) { _, nextModel in
                    let nextLevels = modelOptions.first(where: { $0.modelId == nextModel })?.thinkingLevels ?? ["off"]
                    thinking = closestThinkingLevel(to: thinking, in: nextLevels)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.copy.apiKey)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(quietSubtleText)
                    SecureField(store.copy.apiKeyPlaceholder, text: $apiKey)
                        .focused($isApiKeyFocused)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(quietSettingsControlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isApiKeyFocused ? quietChatText.opacity(0.32) : quietSettingsControlBorder, lineWidth: 0.8)
                        }
                }

                SettingsPickerField(title: store.copy.thinking, selection: $thinking, options: thinkingOptions)

                Button {
                    store.saveSettings(
                        language: store.language,
                        provider: provider,
                        model: model,
                        apiKey: apiKey,
                        thinking: thinking,
                        appearance: store.appearanceMode.rawValue
                    )
                    onSaved()
                } label: {
                    Text("保存")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(quietPrimaryText)
                        .background(quietPrimaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.48)
            }
            .padding(18)
            .frame(maxWidth: 360)
            .background(Color(nsColor: quietWindowFill), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(nsColor: quietBorder), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            normalizeInitialSelection()
            DispatchQueue.main.async {
                isApiKeyFocused = true
            }
        }
        .onChange(of: store.modelProviders) { _, _ in
            normalizeInitialSelection()
        }
    }

    private var canSave: Bool {
        !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var providerOptions: [ModelProviderOption] {
        let loaded = store.modelProviders.filter { !$0.models.isEmpty }
        guard !loaded.isEmpty else { return [fallbackProvider] }
        if loaded.contains(where: { $0.id == provider }) {
            return loaded
        }
        return [fallbackProvider] + loaded
    }

    private var modelOptions: [AvailableModel] {
        let models = providerOptions.first(where: { $0.id == provider })?.models ?? fallbackProvider.models
        return models.isEmpty ? fallbackProvider.models : models
    }

    private var thinkingOptions: [(value: String, label: String)] {
        let levels = modelOptions.first(where: { $0.modelId == model })?.thinkingLevels ?? ["off"]
        return levels.map { (value: $0, label: thinkingLevelLabel($0)) }
    }

    private var fallbackProvider: ModelProviderOption {
        ModelProviderOption(
            id: "deepseek",
            name: "DeepSeek",
            models: [
                AvailableModel(
                    id: "deepseek/deepseek-v4-flash",
                    provider: "deepseek",
                    modelId: "deepseek-v4-flash",
                    name: "DeepSeek V4 Flash",
                    label: "DeepSeek V4 Flash",
                    thinkingLevels: ["off", "minimal", "low", "medium", "high"]
                )
            ]
        )
    }

    private func normalizeInitialSelection() {
        if !providerOptions.contains(where: { $0.id == provider }) {
            provider = "deepseek"
        }
        if !modelOptions.contains(where: { $0.modelId == model }) {
            model = modelOptions.first?.modelId ?? "deepseek-v4-flash"
        }
        thinking = closestThinkingLevel(to: thinking, in: modelOptions.first(where: { $0.modelId == model })?.thinkingLevels ?? ["off"])
    }

    private func thinkingLevelLabel(_ level: String) -> String {
        switch level {
        case "off": "Off"
        case "minimal": "Minimal"
        case "low": "Low"
        case "medium": "Medium"
        case "high": "High"
        case "xhigh": "Extra High"
        default: level
        }
    }
}

struct SessionOverlayPanel: View {
    let sessions: [QuietSessionSummary]
    let currentSessionPath: String
    let topContentInset: CGFloat
    let onSelect: (QuietSessionSummary) -> Void
    let onDelete: (QuietSessionSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    if sessions.isEmpty {
                        Text("暂无会话")
                            .font(.system(size: 11))
                            .foregroundStyle(quietChatMutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(sessions) { session in
                            SessionSidebarRow(
                                session: session,
                                isSelected: session.path == currentSessionPath,
                                onSelect: {
                                    onSelect(session)
                                },
                                onDelete: {
                                    onDelete(session)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, topContentInset)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: quietSidebarFill), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(quietNonUserBubbleBorder, lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 4, y: 0)
    }
}

struct SessionSidebarRow: View {
    let session: QuietSessionSummary
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            LucideIcon(id: "message-square", fallbackSystemName: "bubble.left")
                .frame(width: 13, height: 13)
                .foregroundStyle(quietNonUserMessageText.opacity(isSelected ? 0.86 : 0.58))

            Text(session.title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: onDelete) {
                LucideIcon(id: "trash-2", fallbackSystemName: "trash")
                    .frame(width: 12, height: 12)
                    .foregroundStyle(quietChatText.opacity(0.72))
                    .frame(width: 23, height: 23)
                    .background(quietSelectedFill, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .foregroundStyle(quietNonUserMessageText.opacity(isSelected ? 0.95 : 0.78))
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var rowFill: Color {
        if isSelected {
            return quietSelectedFill
        }
        if isHovered {
            return quietHoverFill
        }
        return quietHoverFill.opacity(0.001)
    }
}

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat
    let onPaste: () -> Void
    let onPasteCapturedContent: ([String], [CapturedResource]) -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> ComposerInputContainer {
        let view = ComposerInputContainer()
        view.onTextChange = { nextText in
            text = nextText
        }
        view.onSubmit = onSubmit
        view.onPaste = onPaste
        view.onPasteCapturedContent = onPasteCapturedContent
        view.onFocusChange = { focused in
            isFocused = focused
        }
        view.onHeightChange = { height in
            DispatchQueue.main.async {
                measuredHeight = height
            }
        }
        return view
    }

    func updateNSView(_ view: ComposerInputContainer, context: Context) {
        view.placeholder = placeholder
        view.onSubmit = onSubmit
        view.onPaste = onPaste
        view.onPasteCapturedContent = onPasteCapturedContent
        view.onTextChange = { nextText in
            text = nextText
        }
        view.onFocusChange = { focused in
            isFocused = focused
        }
        view.onHeightChange = { height in
            DispatchQueue.main.async {
                measuredHeight = height
            }
        }
        if view.textView.string != text, !view.textView.hasMarkedText() {
            view.textView.string = text
        }
        view.updatePlaceholderVisibility()
        view.refreshColors()
        view.reportMeasuredHeight()
        if isFocused, view.window?.firstResponder !== view.textView {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view.textView)
            }
        }
    }
}

final class ComposerInputContainer: NSView, NSTextViewDelegate {
    let textView = ComposerInputTextView()
    private let placeholderLabel = NSTextField(labelWithString: "")

    var onTextChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?
    var onPaste: (() -> Void)?
    var onPasteCapturedContent: (([String], [CapturedResource]) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var placeholder: String = "" {
        didSet {
            placeholderLabel.stringValue = placeholder
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredTextHeight())
    }

    func reportMeasuredHeight() {
        invalidateIntrinsicContentSize()
        onHeightChange?(measuredTextHeight())
    }

    private func measuredTextHeight() -> CGFloat {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        let lineHeight = textView.font.map { ceil($0.ascender - $0.descender + $0.leading) } ?? 16
        let height = min(max(lineHeight + 3, ceil(usedRect.height) + 3), lineHeight * 4 + 6)
        return height
    }

    override func layout() {
        super.layout()
        textView.textContainer?.containerSize = NSSize(width: max(0, bounds.width), height: .greatestFiniteMagnitude)
        reportMeasuredHeight()
    }

    func textDidChange(_ notification: Notification) {
        onTextChange?(textView.string)
        updatePlaceholderVisibility()
        reportMeasuredHeight()
    }

    func textDidBeginEditing(_ notification: Notification) {
        onFocusChange?(true)
    }

    func textDidEndEditing(_ notification: Notification) {
        onFocusChange?(false)
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.string.isEmpty || textView.hasMarkedText()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        textView.delegate = self
        textView.container = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        placeholderLabel.stringValue = placeholder
        placeholderLabel.font = .systemFont(ofSize: 13)
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.isBezeled = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false

        [placeholderLabel, textView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
        ])

        updatePlaceholderVisibility()
        refreshColors()
    }

    func refreshColors() {
        textView.textColor = NSColor(quietChatText)
        textView.insertionPointColor = .labelColor
        placeholderLabel.textColor = NSColor(quietChatMutedText)
    }
}

final class ComposerInputTextView: NSTextView {
    weak var container: ComposerInputContainer?

    override func paste(_ sender: Any?) {
        let captured = capturedResources(from: .general)
        let hasDirectPasteContent = !captured.paths.isEmpty
            || captured.resources.contains(where: { $0.kind == "image" })
        if hasDirectPasteContent {
            container?.onPasteCapturedContent?(captured.paths, captured.resources)
            refreshComposerChrome()
            return
        }
        super.paste(sender)
        container?.onPaste?()
        refreshComposerChrome()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        refreshComposerChrome()
    }

    override func unmarkText() {
        super.unmarkText()
        refreshComposerChrome()
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn else {
            super.keyDown(with: event)
            refreshComposerChrome()
            return
        }

        if hasMarkedText() {
            super.keyDown(with: event)
            refreshComposerChrome()
            return
        }

        if event.modifierFlags.contains(.shift) {
            insertNewline(nil)
            refreshComposerChrome()
        } else {
            container?.onSubmit?()
        }
    }

    private func refreshComposerChrome() {
        DispatchQueue.main.async { [weak self] in
            self?.container?.updatePlaceholderVisibility()
            self?.container?.reportMeasuredHeight()
        }
    }
}

struct PasteboardShortcutCatcher: NSViewRepresentable {
    let onPaste: () -> Bool

    func makeNSView(context: Context) -> PasteboardShortcutView {
        let view = PasteboardShortcutView()
        view.onPaste = onPaste
        return view
    }

    func updateNSView(_ nsView: PasteboardShortcutView, context: Context) {
        nsView.onPaste = onPaste
        nsView.attachMonitorIfNeeded()
    }
}

@MainActor
final class PasteboardShortcutView: NSView {
    var onPaste: (() -> Bool)?
    private var monitor: EventMonitor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachMonitorIfNeeded()
    }

    deinit {
        monitor = nil
    }

    func attachMonitorIfNeeded() {
        guard monitor == nil else { return }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }) {
            monitor = EventMonitor(token)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window === window,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              !isTextInputFocused(in: window) else {
            return event
        }
        return onPaste?() == true ? nil : event
    }

    private func isTextInputFocused(in window: NSWindow) -> Bool {
        var responder = window.firstResponder
        while let current = responder {
            if current is NSTextView || current is NSTextField {
                return true
            }
            responder = current.nextResponder
        }
        return false
    }
}

final class WindowMoveHotZoneNSView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct HeaderDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowMoveHotZoneNSView {
        let view = WindowMoveHotZoneNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: WindowMoveHotZoneNSView, context: Context) {}
}

@MainActor
private func addWindowMoveHotZones(to contentView: NSView) {
    let topZone = WindowMoveHotZoneNSView()
    let bottomZone = WindowMoveHotZoneNSView()
    let zones = [topZone, bottomZone]

    zones.forEach { zone in
        zone.translatesAutoresizingMaskIntoConstraints = false
        zone.wantsLayer = true
        zone.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.addSubview(zone)
    }

    NSLayoutConstraint.activate([
        topZone.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        topZone.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        topZone.topAnchor.constraint(equalTo: contentView.topAnchor),
        topZone.heightAnchor.constraint(equalToConstant: 10),

        bottomZone.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        bottomZone.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        bottomZone.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        bottomZone.heightAnchor.constraint(equalToConstant: 10),
    ])
}

private enum SettingsFocusTarget: Hashable {
    case apiKey
}

private let settingsBottomAnchorId = "settings-bottom-anchor"

struct SettingsPanel: View {
    @ObservedObject var store: AgentStore
    let focusApiKeyRequest: Int
    let onClose: () -> Void

    @State private var language: String
    @State private var provider: String
    @State private var model: String
    @State private var apiKey: String
    @State private var thinking: String
    @State private var appearance: String
    @FocusState private var focusedField: SettingsFocusTarget?

    init(store: AgentStore, focusApiKeyRequest: Int = 0, onClose: @escaping () -> Void) {
        self.store = store
        self.focusApiKeyRequest = focusApiKeyRequest
        self.onClose = onClose
        _language = State(initialValue: store.language)
        _provider = State(initialValue: store.modelProvider)
        _model = State(initialValue: store.modelId)
        _apiKey = State(initialValue: store.modelApiKey)
        _thinking = State(initialValue: store.thinkingLevel)
        _appearance = State(initialValue: store.appearanceMode.rawValue)
    }

    var body: some View {
        let copy = quietCopy(QuietLanguage.normalized(language))
        let providerOptions = resolvedProviderOptions
        let selectedProvider = providerOptions.first(where: { $0.id == provider })
        let modelOptions = selectedProvider?.models ?? fallbackProvider.models
        let selectedModel = modelOptions.first(where: { $0.modelId == model }) ?? modelOptions.first
        let thinkingOptions = (selectedModel?.thinkingLevels ?? ["off", "minimal", "low", "medium", "high"])
            .map { (value: $0, label: thinkingLevelLabel($0)) }

        VStack(spacing: 0) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(copy.settingsTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(copy.settingsSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(quietSubtleText)
                }
                Spacer()
                Button(action: onClose) {
                    GlassIconButtonLabel(iconId: "x", fallbackSystemName: "xmark", size: 30, iconSize: 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsPickerField(title: copy.language, selection: $language, options: QuietLanguage.allCases.map { (value: $0.rawValue, label: $0.label) })
                            .onChange(of: language) { _, nextLanguage in
                                store.applyLanguage(QuietLanguage.normalized(nextLanguage))
                            }

                        SettingsPickerField(title: copy.appearance, selection: $appearance, options: appearanceOptions(copy: copy))
                            .onChange(of: appearance) { _, nextAppearance in
                                store.applyAppearanceMode(QuietAppearanceMode.normalized(nextAppearance))
                            }

                        modelSectionDivider

                        SettingsPickerField(
                            title: copy.provider,
                            selection: $provider,
                            options: providerOptions.map { (value: $0.id, label: $0.name) }
                        )
                        .onChange(of: provider) { _, nextProvider in
                            let nextModels = providerOptions.first(where: { $0.id == nextProvider })?.models ?? []
                            model = nextModels.first?.modelId ?? model
                            thinking = closestThinkingLevel(to: thinking, in: nextModels.first?.thinkingLevels ?? ["off"])
                        }

                        SettingsPickerField(
                            title: copy.model,
                            selection: $model,
                            options: modelOptions.isEmpty ? [(value: model, label: model)] : modelOptions.map { (value: $0.modelId, label: $0.label) }
                        )
                        .onChange(of: model) { _, nextModel in
                            let nextLevels = modelOptions.first(where: { $0.modelId == nextModel })?.thinkingLevels ?? ["off"]
                            thinking = closestThinkingLevel(to: thinking, in: nextLevels)
                        }

                        apiKeyField(copy: copy)
                        SettingsPickerField(title: copy.thinking, selection: $thinking, options: thinkingOptions)

                        Button {
                            store.saveSettings(language: language, provider: provider, model: model, apiKey: apiKey, thinking: thinking, appearance: appearance)
                            onClose()
                        } label: {
                            Text(copy.saveAndRestart)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .foregroundStyle(quietPrimaryText)
                                .background(quietPrimaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Color.clear
                            .frame(height: 1)
                            .id(settingsBottomAnchorId)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .onAppear {
                    focusApiKeyIfRequested(proxy: proxy)
                }
                .onChange(of: focusApiKeyRequest) { _, _ in
                    focusApiKeyIfRequested(proxy: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            thinking = closestThinkingLevel(to: thinking, in: selectedModel?.thinkingLevels ?? ["off"])
        }
        .onChange(of: store.modelProviders) { _, _ in
            let refreshedProviderOptions = resolvedProviderOptions
            if !refreshedProviderOptions.contains(where: { $0.id == provider }),
               let firstProvider = refreshedProviderOptions.first {
                provider = firstProvider.id
            }
            let refreshedModels = refreshedProviderOptions.first(where: { $0.id == provider })?.models ?? fallbackProvider.models
            if !refreshedModels.contains(where: { $0.modelId == model }),
               let firstModel = refreshedModels.first {
                model = firstModel.modelId
            }
            let refreshedLevels = refreshedModels.first(where: { $0.modelId == model })?.thinkingLevels ?? ["off"]
            thinking = closestThinkingLevel(to: thinking, in: refreshedLevels)
        }
    }

    private func focusApiKeyIfRequested(proxy: ScrollViewProxy) {
        guard focusApiKeyRequest > 0 else { return }
        DispatchQueue.main.async {
            focusedField = .apiKey
            scrollSettingsToBottom(proxy: proxy)
        }
        DispatchQueue.main.async {
            scrollSettingsToBottom(proxy: proxy)
        }
    }

    private func scrollSettingsToBottom(proxy: ScrollViewProxy) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(settingsBottomAnchorId, anchor: .bottom)
        }
    }

    private func apiKeyField(copy: QuietCopy) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(copy.apiKey)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(quietSubtleText)
            SecureField(copy.apiKeyPlaceholder, text: $apiKey)
                .focused($focusedField, equals: .apiKey)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(quietSettingsControlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(focusedField == .apiKey ? quietChatText.opacity(0.32) : quietSettingsControlBorder, lineWidth: 0.8)
                }
        }
    }

    private var modelSectionDivider: some View {
        Rectangle()
            .fill(quietHairline)
            .frame(height: 0.8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func appearanceOptions(copy: QuietCopy) -> [(value: String, label: String)] {
        [
            (value: QuietAppearanceMode.system.rawValue, label: copy.appearanceSystem),
            (value: QuietAppearanceMode.light.rawValue, label: copy.appearanceLight),
            (value: QuietAppearanceMode.dark.rawValue, label: copy.appearanceDark),
        ]
    }

    private var fallbackProvider: ModelProviderOption {
        ModelProviderOption(
            id: provider.isEmpty ? "deepseek" : provider,
            name: provider.isEmpty ? "DeepSeek" : provider,
            models: [
                AvailableModel(
                    id: "\(provider.isEmpty ? "deepseek" : provider)/\(model.isEmpty ? "deepseek-v4-flash" : model)",
                    provider: provider.isEmpty ? "deepseek" : provider,
                    modelId: model.isEmpty ? "deepseek-v4-flash" : model,
                    name: model.isEmpty ? "deepseek-v4-flash" : model,
                    label: model.isEmpty ? "deepseek-v4-flash" : model,
                    thinkingLevels: ["off", "minimal", "low", "medium", "high"]
                )
            ]
        )
    }

    private var resolvedProviderOptions: [ModelProviderOption] {
        let options = store.modelProviders.filter { !$0.models.isEmpty }
        if options.isEmpty {
            return [fallbackProvider]
        }
        if options.contains(where: { $0.id == provider }) {
            return options
        }
        return [fallbackProvider] + options
    }

    private func thinkingLevelLabel(_ level: String) -> String {
        switch level {
        case "off":
            "Off"
        case "minimal":
            "Minimal"
        case "low":
            "Low"
        case "medium":
            "Medium"
        case "high":
            "High"
        case "xhigh":
            "Extra High"
        default:
            level
        }
    }
}

struct SettingsField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(quietSubtleText)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 12))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(quietSettingsControlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(quietSettingsControlBorder, lineWidth: 0.6)
            }
        }
    }
}

struct SettingsPickerField: View {
    let title: String
    @Binding var selection: String
    let options: [(value: String, label: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(quietSubtleText)
            Menu {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection = option.value
                    } label: {
                        if option.value == selection {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selectedLabel)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(quietNonUserMessageText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    LucideIcon(id: "chevrons-up-down", fallbackSystemName: "chevron.up.chevron.down")
                        .frame(width: 14, height: 14)
                        .foregroundStyle(quietChatText.opacity(0.72))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(quietSettingsControlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(quietSettingsControlBorder, lineWidth: 0.6)
            }
            .menuIndicator(.hidden)
            .accessibilityLabel(title)
        }
    }

    private var selectedLabel: String {
        options.first(where: { $0.value == selection })?.label ?? selection
    }
}

private struct ChatScrollMetricsReader: NSViewRepresentable {
    let onChange: (CGFloat, CGFloat, CGFloat) -> Void
    let onUserScroll: () -> Void

    func makeNSView(context: Context) -> ChatScrollMetricsView {
        let view = ChatScrollMetricsView()
        view.onChange = onChange
        view.onUserScroll = onUserScroll
        return view
    }

    func updateNSView(_ nsView: ChatScrollMetricsView, context: Context) {
        nsView.onChange = onChange
        nsView.onUserScroll = onUserScroll
        DispatchQueue.main.async {
            nsView.attachToScrollViewIfNeeded()
            nsView.reportMetrics()
        }
    }
}

@MainActor
private final class ChatScrollMetricsView: NSView {
    var onChange: ((CGFloat, CGFloat, CGFloat) -> Void)?
    var onUserScroll: (() -> Void)?

    private weak var scrollView: NSScrollView?
    private var boundsObserver: NotificationObserver?
    private var contentFrameObserver: NotificationObserver?
    private var clipFrameObserver: NotificationObserver?
    private var liveScrollObserver: NotificationObserver?
    private var scrollWheelMonitor: EventMonitor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.attachToScrollViewIfNeeded()
            self?.reportMetrics()
        }
    }

    deinit {
        [boundsObserver, contentFrameObserver, clipFrameObserver, liveScrollObserver].forEach { observer in
            if let observer {
                NotificationCenter.default.removeObserver(observer.token)
            }
        }
    }

    func attachToScrollViewIfNeeded() {
        guard scrollView == nil else { return }
        guard let scrollView = nearestScrollView() else { return }

        self.scrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.documentView?.postsFrameChangedNotifications = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.verticalScroller?.knobStyle = .default

        boundsObserver = NotificationObserver(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reportMetrics()
            }
        })

        clipFrameObserver = NotificationObserver(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reportMetrics()
            }
        })

        if let documentView = scrollView.documentView {
            contentFrameObserver = NotificationObserver(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.reportMetrics()
                }
            })
        }

        liveScrollObserver = NotificationObserver(NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onUserScroll?()
                self?.scheduleMetricsReports()
            }
        })

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.handleScrollWheel(event)
            return event
        }) {
            scrollWheelMonitor = EventMonitor(monitor)
        }
    }

    func reportMetrics() {
        guard let scrollView else { return }
        let offset = max(0, scrollView.contentView.bounds.origin.y)
        let viewportHeight = max(1, scrollView.contentView.bounds.height)
        let contentHeight = max(1, scrollView.documentView?.frame.height ?? scrollView.contentSize.height)
        onChange?(offset, viewportHeight, contentHeight)
    }

    private func handleScrollWheel(_ event: NSEvent) {
        guard let scrollView,
              event.window === scrollView.window else {
            return
        }
        let location = scrollView.convert(event.locationInWindow, from: nil)
        guard scrollView.bounds.contains(location),
              abs(event.scrollingDeltaY) > 0.1 || abs(event.scrollingDeltaX) > 0.1 else {
            return
        }
        onUserScroll?()
        scheduleMetricsReports()
    }

    private func scheduleMetricsReports() {
        reportMetrics()
        DispatchQueue.main.async { [weak self] in
            self?.reportMetrics()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.reportMetrics()
        }
    }

    private func nearestScrollView() -> NSScrollView? {
        var view: NSView? = self
        while let current = view {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}

private final class NotificationObserver: @unchecked Sendable {
    let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }
}

private final class EventMonitor: @unchecked Sendable {
    private let token: Any

    init(_ token: Any) {
        self.token = token
    }

    deinit {
        NSEvent.removeMonitor(token)
    }
}

struct SwiftUIChatScrollbar: View {
    let offset: CGFloat
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let onScrollToProgress: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geometry in
            if isScrollable(geometry.size.height) {
                let metrics = scrollbarMetrics(trackHeight: geometry.size.height)
                Capsule()
                    .fill(quietChatText.opacity(0.28))
                    .frame(width: 5, height: metrics.thumbHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(y: metrics.thumbOffset)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let targetY = min(max(0, value.location.y - metrics.thumbHeight / 2), metrics.availableTravel)
                                onScrollToProgress(targetY / max(1, metrics.availableTravel))
                            }
                    )
                    .animation(.easeOut(duration: 0.08), value: offset)
            }
        }
        .contentShape(Rectangle())
        .opacity(isScrollable(viewportHeight) ? 1 : 0)
    }

    private func isScrollable(_ trackHeight: CGFloat) -> Bool {
        contentHeight > viewportHeight + 8 && trackHeight > 40
    }

    private func scrollbarMetrics(trackHeight: CGFloat) -> (thumbHeight: CGFloat, thumbOffset: CGFloat, availableTravel: CGFloat) {
        let usableTrackHeight = max(1, trackHeight - 16)
        let thumbHeight = max(32, min(usableTrackHeight, (viewportHeight / max(contentHeight, 1)) * usableTrackHeight))
        let availableTravel = max(1, usableTrackHeight - thumbHeight)
        let maxOffset = max(1, contentHeight - viewportHeight)
        let progress = min(max(offset / maxOffset, 0), 1)
        return (thumbHeight, 8 + progress * availableTravel, availableTravel)
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
                .fill(quietChatText.opacity(0.16))
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
                    .fill(quietChatMutedText)
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
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: message.role == .user ? nil : .infinity, alignment: .leading)
                .background(bubbleFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(border, lineWidth: 0.6)
                }
                .contextMenu {
                    Button("Copy Message") {
                        copyMessageToPasteboard()
                    }
                }

            if message.role != .user {
                Spacer(minLength: 0)
            }
        }
    }

    private func copyMessageToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }

    private var foreground: Color {
        switch message.role {
        case .user:
            quietPrimaryText
        case .assistant:
            quietNonUserMessageText
        case .system:
            quietNonUserMessageText
        case .tool:
            quietNonUserMessageText
        }
    }

    private var bubbleFill: Color {
        switch message.role {
        case .user:
            quietPrimaryFill.opacity(0.82)
        case .assistant:
            quietNonUserBubbleFill
        case .system:
            quietNonUserBubbleFill
        case .tool:
            quietNonUserBubbleFill
        }
    }

    private var border: Color {
        switch message.role {
        case .user:
            .clear
        case .assistant:
            quietNonUserBubbleBorder
        case .system:
            quietNonUserBubbleBorder
        case .tool:
            quietNonUserBubbleBorder
        }
    }
}

struct MessageContentView: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .assistant && !message.usesPlainTextRendering {
            AssistantMarkdownView(text: message.text.isEmpty ? "..." : message.text)
        } else {
            Text(message.text.isEmpty ? "..." : message.text)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(message.role == .user ? quietPrimaryText : quietNonUserMessageText)
        }
    }
}

struct AssistantMarkdownView: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.basic)
            .markdownTextStyle {
                FontSize(12.5)
                ForegroundColor(quietNonUserMessageText)
            }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(12)
                ForegroundColor(quietNonUserMessageText)
                BackgroundColor(quietMarkdownCodeFill)
            }
            .markdownTextStyle(\.strong) {
                FontWeight(.semibold)
            }
            .markdownBlockStyle(\.heading1) { configuration in
                compactHeading(configuration.label, scale: 1.12)
            }
            .markdownBlockStyle(\.heading2) { configuration in
                compactHeading(configuration.label, scale: 1.08)
            }
            .markdownBlockStyle(\.heading3) { configuration in
                compactHeading(configuration.label, scale: 1.04)
            }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.18))
                    .markdownMargin(top: .zero, bottom: .em(0.72))
            }
            .markdownBlockStyle(\.table) { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: true)
                }
                .markdownMargin(top: .em(0.2), bottom: .em(0.8))
            }
            .markdownBlockStyle(\.tableCell) { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                    }
                    .relativeLineSpacing(.em(0.12))
                    .relativePadding(.horizontal, length: .em(0.62))
                    .relativePadding(.vertical, length: .em(0.32))
            }
    }

    private func compactHeading(_ label: some View, scale: CGFloat) -> some View {
        label
            .markdownTextStyle {
                FontWeight(.semibold)
                FontSize(12.5 * scale)
            }
            .markdownMargin(top: .em(0.45), bottom: .em(0.55))
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
                        .foregroundStyle(quietChatText.opacity(0.84))
                        .frame(width: 14, height: 14)
                        .frame(width: 18, height: 18)

                    Text(displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(quietChatText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(compactSummary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(quietChatMutedText)
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
                        ToolPayloadLine(
                            title: "输入",
                            text: message.toolSummary,
                            lineLimit: message.toolStatus == .running ? 14 : 6,
                            autoFollow: message.toolStatus == .running
                        )
                    }
                    if !message.toolResult.isEmpty {
                        ToolPayloadLine(
                            title: message.toolStatus == .failed ? "错误" : "结果",
                            text: message.toolResult,
                            lineLimit: message.toolStatus == .running ? 14 : 6,
                            autoFollow: message.toolStatus == .running
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .background(quietNonUserBubbleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(quietNonUserBubbleBorder, lineWidth: 0.6)
        }
        .animation(.easeInOut(duration: 0.18), value: message.toolExpanded)
    }

    private var compactSummary: String {
        if let pathSummary = compactPathSummary {
            return truncate(pathSummary, maxLength: 34)
        }
        let raw = message.toolSummary.isEmpty ? message.toolResult : message.toolSummary
        return truncate(raw, maxLength: 34)
    }

    private var compactPathSummary: String? {
        let normalizedName = message.toolName.lowercased()
        guard normalizedName.contains("write") || normalizedName.contains("edit") else {
            return nil
        }
        let raw = message.toolSummary.isEmpty ? message.toolResult : message.toolSummary
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any] else {
            return nil
        }
        let path = (dict["path"] as? String)
            ?? (dict["file_path"] as? String)
            ?? (dict["filePath"] as? String)
        guard let path, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
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
                    .controlSize(.small)
                    .frame(width: 12, height: 12)
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
            quietNonUserMessageText.opacity(0.72)
        case .finished:
            quietNonUserMessageText.opacity(0.82)
        case .failed:
            quietNonUserMessageText.opacity(0.58)
        }
    }
}

struct ToolPayloadLine: View {
    let title: String
    let text: String
    var lineLimit = 6
    var autoFollow = false
    private let bottomId = "tool-payload-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(quietSubtleText.opacity(0.76))
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(text)
                            .font(.system(size: 11))
                            .foregroundStyle(quietChatText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        Color.clear
                            .frame(height: 1)
                            .id(bottomId)
                    }
                }
                .frame(maxHeight: CGFloat(lineLimit) * 16 + 4, alignment: .topLeading)
                .onAppear {
                    guard autoFollow else { return }
                    proxy.scrollTo(bottomId, anchor: .bottom)
                }
                .onChange(of: text) { _, _ in
                    guard autoFollow else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(bottomId, anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(quietHoverFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension NSView {
    func clearTextSelectionsRecursively(excluding excludedTextView: NSTextView? = nil) {
        if let textView = self as? NSTextView {
            guard textView !== excludedTextView else { return }
            let selectedRange = textView.selectedRange()
            let insertionPoint = selectedRange.location == NSNotFound ? textView.string.count : selectedRange.location
            textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
        }

        subviews.forEach { $0.clearTextSelectionsRecursively(excluding: excludedTextView) }
    }
}

final class QuietWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        clearTextSelectionsAfterFocusLoss()
    }

    override func resignMain() {
        super.resignMain()
        clearTextSelectionsAfterFocusLoss()
    }

    private func clearTextSelectionsAfterFocusLoss() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let textView = self.firstResponder as? NSTextView {
                let selectedRange = textView.selectedRange()
                let insertionPoint = selectedRange.location == NSNotFound ? textView.string.count : selectedRange.location
                textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
            }
            self.makeFirstResponder(nil)
            self.contentView?.clearTextSelectionsRecursively()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum WindowMode {
        case menuBar
        case desktop
    }

    private enum MenuBarPresentationSource {
        case statusItem
        case keyboardShortcut
    }

    private static let menuBarWindowFrameKey = "quiet.window.frame"
    private static let desktopWindowFrameKey = "quiet.desktop.window.frame"
    private static let shortcutHotKeySignature: OSType = 0x51756974
    private static let shortcutHotKeyID: UInt32 = 1
    private static weak var sharedDelegate: AppDelegate?

    private var window: NSWindow?
    private var frameKeeper: WindowFrameKeeper?
    private var statusItem: NSStatusItem?
    private weak var chromeRootView: NSView?
    private weak var hostingView: NSView?
    private var appearanceObserver: NSObjectProtocol?
    private var desktopClientObserver: NSObjectProtocol?
    private var windowMode: WindowMode = .menuBar
    private var menuBarPresentationSource: MenuBarPresentationSource = .statusItem
    private var shortcutHotKeyRef: EventHotKeyRef?
    private var shortcutHotKeyEventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.sharedDelegate = self
        applyApplicationIcon()
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupStatusItem()
        setupGlobalShortcut()

        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let blackChromeView = NSView()
        blackChromeView.translatesAutoresizingMaskIntoConstraints = false
        blackChromeView.wantsLayer = true
        blackChromeView.layer?.cornerRadius = 24
        blackChromeView.layer?.cornerCurve = .continuous
        blackChromeView.layer?.masksToBounds = true
        blackChromeView.layer?.backgroundColor = quietResolvedCGColor(quietWindowFill, appearance: nil)
        blackChromeView.layer?.borderWidth = 0.8
        blackChromeView.layer?.borderColor = quietResolvedCGColor(quietBorder, appearance: nil)
        rootView.addSubview(blackChromeView)
        blackChromeView.addSubview(contentView)
        chromeRootView = blackChromeView

        let hostingView = NSHostingView(rootView: QuietView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.layer?.backgroundColor = quietResolvedCGColor(quietWindowFill, appearance: nil)
        contentView.addSubview(hostingView)
        self.hostingView = hostingView

        NSLayoutConstraint.activate([
            blackChromeView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            blackChromeView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            blackChromeView.topAnchor.constraint(equalTo: rootView.topAnchor),
            blackChromeView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: blackChromeView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: blackChromeView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: blackChromeView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: blackChromeView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        addWindowMoveHotZones(to: contentView)

        let defaultFrame = NSRect(
            x: 96,
            y: 420,
            width: quietWindowDefaultSize.width,
            height: quietWindowDefaultSize.height
        )
        let window = QuietWindow(
            contentRect: Self.savedFrame(
                key: Self.menuBarWindowFrameKey,
                minimumSize: quietWindowMinimumSize
            ) ?? defaultFrame,
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = rootView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.invalidateShadow()
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.minSize = quietWindowMinimumSize
        window.contentMinSize = quietWindowMinimumSize
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        setStandardWindowButtonsHidden(true, for: window)
        window.orderOut(nil)

        let frameKeeper = WindowFrameKeeper()
        frameKeeper.frameStorageKey = Self.menuBarWindowFrameKey
        window.delegate = frameKeeper
        frameKeeper.onFrameChange = { [weak self] in
            self?.alignDesktopTrafficLights()
        }
        self.frameKeeper = frameKeeper
        self.window = window
        applyAppearance(QuietAppearanceMode.normalized(UserDefaults.standard.string(forKey: quietAppearanceModeKey)))

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .quietAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.object as? String
            Task { @MainActor in
                self?.applyAppearance(QuietAppearanceMode.normalized(raw))
            }
        }

        desktopClientObserver = NotificationCenter.default.addObserver(
            forName: .quietOpenDesktopClient,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openDesktopClient()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if windowMode == .desktop, !flag {
            openDesktopClient()
            return false
        }
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: quietAppName)
        appMenu.addItem(
            withTitle: "退出 \(quietAppName)",
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
            let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: quietAppName)
                ?? NSImage(systemSymbolName: "tray.fill", accessibilityDescription: quietAppName)
                ?? NSImage.image(lucideId: "inbox")
                ?? NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: quietAppName)
                ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: quietAppName)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = quietCopy(.en).statusTooltip
            button.target = self
            button.action = #selector(toggleWindowFromStatusItem)
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        }
        self.statusItem = statusItem
    }

    private func setupGlobalShortcut() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == AppDelegate.shortcutHotKeySignature,
                      hotKeyID.id == AppDelegate.shortcutHotKeyID else {
                    return noErr
                }
                Task { @MainActor in
                    AppDelegate.sharedDelegate?.toggleWindowFromKeyboardShortcut()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &shortcutHotKeyEventHandler
        )
        if handlerStatus != noErr {
            NSLog("Quiet failed to install global shortcut handler: \(handlerStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.shortcutHotKeySignature,
            id: Self.shortcutHotKeyID
        )
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &shortcutHotKeyRef
        )
        if hotKeyStatus != noErr {
            NSLog("Quiet failed to register Option-Space shortcut: \(hotKeyStatus)")
        }
    }

    private func applyAppearance(_ mode: QuietAppearanceMode) {
        let appearance = mode.nsAppearance
        NSApp.appearance = appearance
        window?.appearance = appearance
        chromeRootView?.appearance = appearance
        updateChromeBorder()
    }

    private func updateChromeBorder() {
        guard let chromeRootView else { return }
        let appearance = chromeRootView.effectiveAppearance
        chromeRootView.layer?.backgroundColor = quietResolvedCGColor(quietWindowFill, appearance: appearance)
        chromeRootView.layer?.borderColor = quietResolvedCGColor(quietBorder, appearance: appearance)
        chromeRootView.subviews.forEach { subview in
            subview.layer?.backgroundColor = quietResolvedCGColor(quietWindowFill, appearance: appearance)
        }
        hostingView?.layer?.backgroundColor = quietResolvedCGColor(quietWindowFill, appearance: appearance)
    }

    private func setStandardWindowButtonsHidden(_ isHidden: Bool, for window: NSWindow? = nil) {
        let targetWindow = window ?? self.window
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ].forEach { buttonType in
            targetWindow?.standardWindowButton(buttonType)?.isHidden = isHidden
        }
    }

    private func applyApplicationIcon() {
        guard let iconURL = quietBundledResourceURL(path: quietAppIconResourcePath),
              let image = NSImage(contentsOf: iconURL) else {
            return
        }
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }

    @objc private func toggleWindowFromStatusItem() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusItemMenu()
            return
        }

        toggleWindowVisibility()
    }

    @objc private func toggleWindowFromStatusMenu() {
        toggleWindowVisibility()
    }

    private func toggleWindowVisibility() {
        guard let window else { return }

        if window.isVisible {
            window.orderOut(nil)
            return
        }

        presentMenuBarWindow(window, source: .statusItem)
    }

    private func toggleWindowFromKeyboardShortcut() {
        guard let window else { return }

        if windowMode == .menuBar, window.isVisible {
            window.orderOut(nil)
            return
        }

        presentMenuBarWindow(window, source: .keyboardShortcut)
    }

    private func presentMenuBarWindow(_ window: NSWindow, source: MenuBarPresentationSource) {
        configureWindowForMenuBarIfNeeded()
        menuBarPresentationSource = source
        positionMenuBarWindow(window, source: source)
        window.level = menuBarWindowLevel(for: source)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        alignDesktopTrafficLights()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.positionMenuBarWindow(window, source: source)
            window.level = self.menuBarWindowLevel(for: source)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            self.alignDesktopTrafficLights()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .quietFocusComposer, object: nil)
        }
    }

    private func openDesktopClient() {
        guard let window else { return }

        configureWindowForDesktopIfNeeded()
        window.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        alignDesktopTrafficLights()
        DispatchQueue.main.async { [weak self] in
            self?.alignDesktopTrafficLights()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .quietFocusComposer, object: nil)
        }
    }

    private func configureWindowForMenuBarIfNeeded() {
        guard windowMode != .menuBar, let window else { return }

        window.orderOut(nil)
        windowMode = .menuBar
        menuBarPresentationSource = .statusItem
        frameKeeper?.frameStorageKey = Self.menuBarWindowFrameKey
        NSApp.setActivationPolicy(.accessory)
        window.styleMask = [.titled, .fullSizeContentView, .resizable]
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        setStandardWindowButtonsHidden(true, for: window)
        window.minSize = quietWindowMinimumSize
        window.contentMinSize = quietWindowMinimumSize
        window.isOpaque = false
        window.backgroundColor = .clear
        chromeRootView?.layer?.cornerRadius = 24
        chromeRootView?.layer?.borderWidth = 0.8

        if let savedFrame = Self.savedFrame(key: Self.menuBarWindowFrameKey, minimumSize: quietWindowMinimumSize) {
            window.setFrame(savedFrame, display: false)
        } else {
            window.setContentSize(quietWindowDefaultSize)
        }
        updateChromeBorder()
        notifyWindowChromeModeDidChange()
    }

    private func configureWindowForDesktopIfNeeded() {
        guard windowMode != .desktop, let window else { return }

        window.orderOut(nil)
        windowMode = .desktop
        frameKeeper?.frameStorageKey = Self.desktopWindowFrameKey
        NSApp.setActivationPolicy(.regular)
        applyApplicationIcon()
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.level = .normal
        window.collectionBehavior = [.fullScreenPrimary]
        window.isMovableByWindowBackground = true
        window.title = quietAppName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        setStandardWindowButtonsHidden(false, for: window)
        window.minSize = quietDesktopWindowMinimumSize
        window.contentMinSize = quietDesktopWindowMinimumSize
        window.isOpaque = false
        window.backgroundColor = .clear
        chromeRootView?.layer?.cornerRadius = 24
        chromeRootView?.layer?.borderWidth = 0.8

        if let savedFrame = Self.savedFrame(key: Self.desktopWindowFrameKey, minimumSize: quietDesktopWindowMinimumSize) {
            window.setFrame(savedFrame, display: false)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let size = quietDesktopWindowDefaultSize
            let origin = NSPoint(
                x: screen.midX - size.width / 2,
                y: screen.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: false)
        }
        updateChromeBorder()
        notifyWindowChromeModeDidChange()
        alignDesktopTrafficLights()
    }

    private func notifyWindowChromeModeDidChange() {
        NotificationCenter.default.post(
            name: .quietWindowChromeModeDidChange,
            object: windowMode == .desktop
        )
    }

    private func alignDesktopTrafficLights() {
        guard windowMode == .desktop,
              let window,
              let contentView = window.contentView,
              let closeButton = window.standardWindowButton(.closeButton),
              let buttonSuperview = closeButton.superview else {
            return
        }

        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap { $0 }

        let headerCenterInContent = NSPoint(
            x: 0,
            y: contentView.bounds.maxY - quietHeaderHeight / 2
        )
        let headerCenterInButtonSuperview = buttonSuperview.convert(headerCenterInContent, from: contentView)
        let deltaY = headerCenterInButtonSuperview.y - closeButton.frame.midY
        let proposedCloseY = closeButton.frame.minY + deltaY
        let topInset = buttonSuperview.bounds.maxY - (proposedCloseY + closeButton.frame.height)
        let targetLeadingInset = topInset.isFinite && topInset > 0
            ? topInset
            : quietDesktopTrafficLightFallbackInset
        let deltaX = targetLeadingInset - closeButton.frame.minX

        guard abs(deltaY) > 0.5 || abs(deltaX) > 0.5 else { return }
        for button in buttons {
            button.setFrameOrigin(NSPoint(
                x: button.frame.minX + deltaX,
                y: button.frame.minY + deltaY
            ))
        }
    }

    private func showStatusItemMenu() {
        let language = QuietLanguage.normalized(UserDefaults.standard.string(forKey: "quiet.language"))
        let isWindowVisible = window?.isVisible == true
        let toggleTitle: String
        switch language {
        case .en:
            toggleTitle = isWindowVisible ? "Hide \(quietAppName)" : "Open \(quietAppName)"
        case .zh:
            toggleTitle = isWindowVisible ? "隐藏 \(quietAppName)" : "打开 \(quietAppName)"
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: toggleTitle,
            action: #selector(toggleWindowFromStatusMenu),
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: quietCopy(language).quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    private func positionMenuBarWindow(_ window: NSWindow, source: MenuBarPresentationSource) {
        switch source {
        case .statusItem:
            positionWindowUnderStatusItem(window)
        case .keyboardShortcut:
            positionWindowAtTopRight(window)
        }
    }

    private func menuBarWindowLevel(for source: MenuBarPresentationSource) -> NSWindow.Level {
        switch source {
        case .statusItem:
            .floating
        case .keyboardShortcut:
            .floating
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

    private func positionWindowAtTopRight(_ window: NSWindow) {
        let screen = NSScreen.main ?? window.screen
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let margin: CGFloat = 18
        let windowSize = window.frame.size
        let x = visibleFrame.maxX - windowSize.width - margin
        let y = visibleFrame.maxY - windowSize.height - margin
        window.setFrameOrigin(NSPoint(
            x: max(visibleFrame.minX + margin, x),
            y: max(visibleFrame.minY + margin, y)
        ))
    }

    private static func savedFrame(key: String, minimumSize: NSSize) -> NSRect? {
        let raw = UserDefaults.standard.string(forKey: key)
        guard let raw, !raw.isEmpty else { return nil }
        var frame = NSRectFromString(raw)
        if frame.width < minimumSize.width {
            frame.size.width = minimumSize.width
        }
        if frame.height < minimumSize.height {
            frame.size.height = minimumSize.height
        }
        return frame
    }

}

@MainActor
final class WindowFrameKeeper: NSObject, NSWindowDelegate {
    var frameStorageKey = "quiet.window.frame"
    var onFrameChange: (() -> Void)?

    func windowDidMove(_ notification: Notification) {
        save(notification)
    }

    func windowDidResize(_ notification: Notification) {
        save(notification)
        onFrameChange?()
    }

    private func save(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameStorageKey)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
