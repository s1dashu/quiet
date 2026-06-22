import readline from "node:readline";
import { randomUUID } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  cpSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { rename } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { homedir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, "../../../..");
const require = createRequire(import.meta.url);

const quietHome = resolve(process.env.QUIET_HOME?.trim() || join(homedir(), ".blackhole"));
const quietContentHome = resolve(process.env.QUIET_CONTENT_HOME?.trim() || join(homedir(), "Documents", "Blackhole"));
const inboxDir = join(quietContentHome, "00 Inbox 待整理");
const needsReviewDir = join(quietContentHome, "01 Needs Review 需确认");
const systemArchiveDir = join(quietContentHome, "09 System Archive 系统归档");
const filesDir = quietContentHome;
const logDir = join(quietHome, "logs");
const agentDir = join(quietHome, "pi-agent");
const workspaceDir = join(quietHome, "workspace");
const memoryPath = join(quietHome, "memory.md");
const sessionsDir = join(agentDir, "sessions");
const promptPath = new URL("./quiet-prompt.md", import.meta.url);
const language = process.env.QUIET_LANGUAGE?.trim() === "zh" ? "zh" : "en";
const initialSessionMessageLimit = 20;
const sessionHistoryBatchSize = 10;
const copy = language === "zh"
  ? {
      startupFailed: "agent 启动失败，请检查模型 API Key 或 node_modules",
      organizeFallback: "请整理这些资源。",
      organizeInstruction: "你现在是 Blackhole 的 pi-coding-agent。请真实使用可用的 pi 工具理解并整理文件、链接、Snippet 和其他资源。",
      organizeDoneRule: "整理完成后，用中文简短总结你做了什么；不要提内部运行日志、manifest 或实现文件。",
      explainFallback: "请说明你会如何处理丢进 Blackhole 的文件、链接和文本片段。",
      noStagedResources: "没有资源进入 00 Inbox",
      taskTitle: "agent 资源整理任务",
    }
  : {
      startupFailed: "Agent failed to start. Check the model API key or node_modules.",
      organizeFallback: "Please organize these resources.",
      organizeInstruction: "You are Blackhole's pi-coding-agent. Use the available pi tools to understand and organize files, links, snippets, and other resources.",
      organizeDoneRule: "When finished, briefly summarize what you moved and where in English; do not mention internal runtime logs, manifests, or implementation files.",
      explainFallback: "Explain how you would handle files, links, and snippets dropped into Blackhole.",
      noStagedResources: "No resources entered 00 Inbox",
      taskTitle: "Agent resource organization task",
    };

mkdirSync(filesDir, { recursive: true });
mkdirSync(logDir, { recursive: true });
mkdirSync(agentDir, { recursive: true });
mkdirSync(workspaceDir, { recursive: true });

function ensureQuietDecimalStructure() {
  const dirs = [
    inboxDir,
    needsReviewDir,
    systemArchiveDir,
    join(quietContentHome, "10-19 Personal 个人"),
    join(quietContentHome, "20-29 Money 财务"),
    join(quietContentHome, "30-39 Work 工作"),
    join(quietContentHome, "40-49 Legal & Admin 法务行政"),
    join(quietContentHome, "50-59 Assets & Property 资产"),
    join(quietContentHome, "90-99 Archive 归档"),
  ];
  for (const dir of dirs) {
    mkdirSync(dir, { recursive: true });
  }

  const indexPath = join(systemArchiveDir, "quiet-decimal-index.md");
  if (!existsSync(indexPath)) {
    writeFileSync(indexPath, `# Quiet Decimal Index

Quiet uses a Johnny.Decimal-inspired structure. The number is the stable address; the text is for humans.

## System

- 00 Inbox 待整理: newly dropped resources and in-progress batches.
- 01 Needs Review 需确认: resources Blackhole inspected but should not decide alone.
- 09 System Archive 系统归档: user-readable Quiet Decimal records and archived system notes. Do not store original user resources here.

## Default Areas

- 10-19 Personal 个人
- 20-29 Money 财务
- 30-39 Work 工作
- 40-49 Legal & Admin 法务行政
- 50-59 Assets & Property 资产
- 90-99 Archive 归档
`, "utf8");
  }
}

ensureQuietDecimalStructure();

const defaultMemory = `
# Blackhole Memory

These are user-editable resource organizing rules for Blackhole.

## Learning User Preferences

- When the user expresses a stable preference for how resources should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
- Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
- Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
- This file is located at \`QUIET_HOME/memory.md\`; you may edit it with bash when updating remembered organizing preferences.

## Quiet Decimal Taxonomy

- Use Blackhole's Johnny.Decimal-inspired default structure.
- New drops enter \`00 Inbox 待整理\`.
- Put resources that need user confirmation in \`01 Needs Review 需确认\`.
- Put user-readable system records in \`09 System Archive 系统归档\`; do not put original user resources there.
- Prefer existing numbered areas over creating new top-level folders.
- Use \`90-99 Archive 归档\` for old/completed user resources, not \`09 System Archive 系统归档\`.

## Default Numbered Areas

- \`10-19 Personal 个人\`: identity, health, family, education, travel.
- \`20-29 Money 财务\`: banking, tax, reimbursements, payroll, invoices, budgets, investments, accounting.
- \`30-39 Work 工作\`: meetings, projects, vendors, reports, operations.
- \`40-49 Legal & Admin 法务行政\`: legal documents, government forms, insurance, certificates.
- \`50-59 Assets & Property 资产\`: real estate, vehicles, devices, warranties.
- \`90-99 Archive 归档\`: old, completed, or inactive user resources.

## Destination Pattern

\`QUIET_CONTENT_HOME/<numbered-area>/<numbered-category-or-topic>/<original-name>\`

## Conversation Style

- Be concise.
- Tell the user what was captured, moved, and where.
- When a problem occurs, name the failed file and continue with the rest.
- Do not mention internal logs, manifests, or implementation files unless the user asks.
`.trim();

const memoryPreferenceGuidance = `
## Learning User Preferences

- When the user expresses a stable preference for how resources should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
- Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
- Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
- This file is located at \`QUIET_HOME/memory.md\`; you may edit it with bash when updating remembered organizing preferences.
`.trim();

function ensureMemoryFile() {
  if (!existsSync(memoryPath)) {
    writeFileSync(memoryPath, `${defaultMemory}\n`, "utf8");
    return;
  }
  const memory = readFileSync(memoryPath, "utf8");
  if (!memory.includes("## Learning User Preferences")) {
    writeFileSync(memoryPath, `${memory.trim()}\n\n${memoryPreferenceGuidance}\n`, "utf8");
  }
}

function buildSystemPrompt() {
  const basePrompt = existsSync(promptPath) ? readFileSync(promptPath, "utf8") : "";
  ensureMemoryFile();
  const memory = readFileSync(memoryPath, "utf8").trim();
  if (!memory) return basePrompt;
  return `${basePrompt.trim()}\n\n# User Memory\n\n${memory}\n`;
}

const systemPrompt = buildSystemPrompt();

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

let sessionPromise;
let currentSession;
let currentHistoryLoadedFromIndex = 0;
let currentHistoryPath = "";
let messageQueue = Promise.resolve();
let currentAssistantId = "";
let currentThinkingId = "";
let currentAssistantMessageId = "";
const toolIdsByProviderId = new Map();
const toolIdsByContentIndex = new Map();
const startedToolIds = new Set();
let fallbackNoticeSent = false;
let sessionListRefreshTimer;

function emit(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

function displayToolId(providerToolCallId, fallbackId) {
  if (providerToolCallId && toolIdsByProviderId.has(providerToolCallId)) {
    return toolIdsByProviderId.get(providerToolCallId);
  }
  return providerToolCallId || fallbackId || randomUUID();
}

function stringifyUnknown(value) {
  if (value === undefined) return undefined;
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function isInside(parent, child) {
  const rel = relative(resolve(parent), resolve(child));
  return rel === "" || (!rel.startsWith("..") && !rel.startsWith(`${sep}`) && rel !== "..");
}

function removeEmptyDirectories(root, { includeRoot = false } = {}) {
  if (!existsSync(root)) return false;
  let entries;
  try {
    entries = readdirSync(root, { withFileTypes: true });
  } catch {
    return false;
  }

  for (const entry of entries) {
    if (entry.isDirectory()) {
      removeEmptyDirectories(join(root, entry.name), { includeRoot: true });
    }
  }

  try {
    entries = readdirSync(root, { withFileTypes: true });
    if (includeRoot && entries.length === 0) {
      rmSync(root, { recursive: false, force: false });
      return true;
    }
  } catch {
    return false;
  }
  return false;
}

function cleanupInboxDirectories() {
  removeEmptyDirectories(inboxDir);
}

function safeName(name) {
  const cleaned = String(name)
    .normalize("NFC")
    .replace(/[/:]/g, "-")
    .replace(/\s+/g, " ")
    .trim();
  return cleaned || "Untitled";
}

function safeResourceStem(value, fallback) {
  const text = String(value || "")
    .replace(/^https?:\/\//i, "")
    .replace(/^www\./i, "")
    .replace(/[?#].*$/g, "")
    .replace(/[/:\\|<>*"']/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return safeName((text || fallback).slice(0, 80));
}

function uniqueDestination(dir, originalName) {
  mkdirSync(dir, { recursive: true });
  const ext = originalName.includes(".") ? originalName.slice(originalName.lastIndexOf(".")) : "";
  const stem = ext ? originalName.slice(0, -ext.length) : originalName;
  let candidate = join(dir, originalName);
  let index = 2;
  while (existsSync(candidate)) {
    candidate = join(dir, `${stem} ${index}${ext}`);
    index += 1;
  }
  return candidate;
}

async function movePath(source, destination) {
  mkdirSync(dirname(destination), { recursive: true });
  try {
    await rename(source, destination);
  } catch (error) {
    if (error?.code !== "EXDEV") {
      throw error;
    }
    cpSync(source, destination, { recursive: true, preserveTimestamps: true, force: false, errorOnExist: true });
    rmSync(source, { recursive: true, force: false });
  }
}

async function ingestToInbox(paths) {
  const batchId = new Date().toISOString().replace(/[:.]/g, "-");
  const batchDir = join(inboxDir, batchId);
  mkdirSync(batchDir, { recursive: true });
  const ingested = [];
  const failed = [];

  for (const path of paths) {
    const source = resolve(path);
    try {
      if (!existsSync(source)) {
        throw new Error("源文件不存在");
      }
      if (isInside(quietHome, source) || isInside(quietContentHome, source)) {
        throw new Error("文件已经在 Blackhole 目录内");
      }
      const destination = uniqueDestination(batchDir, safeName(source.split(sep).at(-1)));
      await movePath(source, destination);
      ingested.push({
        originalSource: source,
        inboxPath: destination,
        originalName: safeName(source.split(sep).at(-1)),
      });
    } catch (error) {
      failed.push({ source, reason: error?.message ?? String(error) });
    }
  }

  return { batchId, batchDir, ingested, failed };
}

function resourceMarkdown(resource, capturedAt) {
  const kind = String(resource?.kind || "text").trim().toLowerCase();
  const value = String(resource?.value || "").trim();
  if (kind === "link") {
    return `# Link\n\n- URL: ${value}\n- Captured: ${capturedAt}\n\n## Notes\n\n`;
  }
  return `# Snippet\n\n- Captured: ${capturedAt}\n\n## Content\n\n\`\`\`text\n${value}\n\`\`\`\n`;
}

async function ingestResourcesToInbox(resources) {
  const batchId = new Date().toISOString().replace(/[:.]/g, "-");
  const batchDir = join(inboxDir, batchId);
  mkdirSync(batchDir, { recursive: true });
  const capturedAt = new Date().toISOString();
  const ingested = [];
  const failed = [];

  for (const resource of resources) {
    const kind = String(resource?.kind || "text").trim().toLowerCase() === "link" ? "link" : "text";
    const value = String(resource?.value || "").trim();
    try {
      if (!value) {
        throw new Error("资源内容为空");
      }
      const stem = safeResourceStem(value, kind === "link" ? "Link" : "Snippet");
      const destination = uniqueDestination(batchDir, `${stem}.${kind === "link" ? "url" : "snippet"}.md`);
      writeFileSync(destination, resourceMarkdown({ kind, value }, capturedAt), "utf8");
      ingested.push({
        originalSource: kind,
        inboxPath: destination,
        originalName: safeName(kind === "link" ? `Link: ${value}` : `Snippet: ${value.slice(0, 60)}`),
      });
    } catch (error) {
      failed.push({ source: kind, reason: error?.message ?? String(error) });
    }
  }

  return { batchId, batchDir, ingested, failed };
}

function writeSystemArchiveRecord({ batchId, startedAt, finishedAt, ingested, failed }) {
  ensureQuietDecimalStructure();
  const safeBatchId = safeName(batchId || new Date().toISOString().replace(/[:.]/g, "-"));
  const items = ingested.map((item) => ({
    originalName: item.originalName,
    originalSource: item.originalSource,
    inboxPath: item.inboxPath,
    status: existsSync(item.inboxPath) ? "still_in_inbox_or_needs_review" : "moved_from_inbox",
  }));
  const record = {
    batchId: safeBatchId,
    startedAt,
    finishedAt,
    contentRoot: quietContentHome,
    inbox: inboxDir,
    needsReview: needsReviewDir,
    systemArchive: systemArchiveDir,
    items,
    failed,
  };
  const jsonPath = uniqueDestination(systemArchiveDir, `${safeBatchId}.json`);
  writeFileSync(jsonPath, `${JSON.stringify(record, null, 2)}\n`, "utf8");

  const moved = items.filter((item) => item.status === "moved_from_inbox").length;
  const waiting = items.length - moved;
  const mdPath = uniqueDestination(systemArchiveDir, `${safeBatchId}.md`);
  writeFileSync(mdPath, `# Quiet Decimal Batch ${safeBatchId}

- Started: ${startedAt}
- Finished: ${finishedAt}
- Content root: ${quietContentHome}
- Entered 00 Inbox: ${items.length}
- Moved from 00 Inbox: ${moved}
- Still awaiting review or retry: ${waiting}
- Failed before inbox: ${failed.length}

## Items

${items.map((item) => `- ${item.originalName}: ${item.status}`).join("\n") || "- None"}

## Failed Before Inbox

${failed.map((item) => `- ${item.source}: ${item.reason}`).join("\n") || "- None"}
`, "utf8");
  return { jsonPath, mdPath };
}

function findPackageEntry(packageName) {
  try {
    return require.resolve(packageName);
  } catch {
    // Continue to explicit search paths below.
  }

  const candidates = [
    join(projectRoot, "node_modules", packageName, "dist", "index.js"),
    join(__dirname, "..", "node_modules", packageName, "dist", "index.js"),
    join(__dirname, "..", "..", "node_modules", packageName, "dist", "index.js"),
    join(process.cwd(), "node_modules", packageName, "dist", "index.js"),
  ];
  return candidates.find((candidate) => existsSync(candidate));
}

async function loadPi() {
  const entry = findPackageEntry("@earendil-works/pi-coding-agent");
  if (!entry) {
    throw new Error("找不到 @earendil-works/pi-coding-agent。请先运行 npm install，或重新打包 Blackhole.app。");
  }
  return import(pathToFileURL(entry).href);
}

async function loadPiAi() {
  const entry = findPackageEntry("@earendil-works/pi-ai");
  if (!entry) {
    throw new Error("找不到 @earendil-works/pi-ai。请先运行 npm install，或重新打包 Blackhole.app。");
  }
  return import(pathToFileURL(entry).href);
}

function selectModel(modelRegistry) {
  const provider = process.env.QUIET_MODEL_PROVIDER?.trim() || "deepseek";
  const modelId = process.env.QUIET_MODEL_ID?.trim() || "deepseek-v4-flash";
  return modelRegistry.find(provider, modelId) || undefined;
}

function modelRegistryPayload(modelRegistry, getSupportedThinkingLevels) {
  const providerModels = new Map();
  for (const model of modelRegistry.getAll()) {
    const provider = model.provider?.trim();
    const modelId = model.id?.trim();
    if (!provider || !modelId || (Array.isArray(model.input) && !model.input.includes("text"))) {
      continue;
    }
    const providerName = modelRegistry.getProviderDisplayName?.(provider) || provider;
    const entry = providerModels.get(provider) ?? {
      id: provider,
      name: providerName,
      models: [],
    };
    entry.models.push({
      provider,
      providerName,
      modelId,
      name: model.name || modelId,
      label: model.name || modelId,
      input: model.input || [],
      thinkingLevels: getSupportedThinkingLevels?.(model) || ["off"],
    });
    providerModels.set(provider, entry);
  }
  return [...providerModels.values()]
    .map((provider) => ({
      ...provider,
      models: provider.models.sort((a, b) => a.label.localeCompare(b.label, undefined, { sensitivity: "base" })),
    }))
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }));
}

async function createPiSession({ fresh = false, sessionPath } = {}) {
  const {
    AuthStorage,
    createAgentSession,
    DefaultResourceLoader,
    ModelRegistry,
    SessionManager,
    SettingsManager,
  } = await loadPi();
  const { getSupportedThinkingLevels } = await loadPiAi();

  const authStorage = AuthStorage.create(join(agentDir, "auth.json"));
  const provider = process.env.QUIET_MODEL_PROVIDER?.trim() || "deepseek";
  const apiKey = process.env.QUIET_MODEL_API_KEY?.trim();
  if (apiKey) {
    authStorage.setRuntimeApiKey(provider, apiKey);
  }
  const modelRegistry = ModelRegistry.create(authStorage, join(agentDir, "models.json"));
  emit({ type: "model_registry", providers: modelRegistryPayload(modelRegistry, getSupportedThinkingLevels), error: modelRegistry.getError?.() });
  const settingsManager = SettingsManager.create(workspaceDir, agentDir, { projectTrusted: true });
  settingsManager.applyOverrides({
    defaultProvider: process.env.QUIET_MODEL_PROVIDER?.trim() || "deepseek",
    defaultModel: process.env.QUIET_MODEL_ID?.trim() || "deepseek-v4-flash",
    defaultThinkingLevel: process.env.QUIET_THINKING_LEVEL?.trim() || "medium",
    defaultProjectTrust: "always",
  });

  const resourceLoader = new DefaultResourceLoader({
    cwd: workspaceDir,
    agentDir,
    settingsManager,
    noExtensions: true,
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    systemPrompt,
  });
  await resourceLoader.reload();

  const selectedModel = selectModel(modelRegistry);
  const { session, modelFallbackMessage } = await createAgentSession({
    authStorage,
    cwd: workspaceDir,
    agentDir,
    modelRegistry,
    resourceLoader,
    sessionManager: sessionPath
      ? SessionManager.open(sessionPath)
      : fresh
        ? SessionManager.create(workspaceDir, sessionsDir)
        : SessionManager.continueRecent(workspaceDir, sessionsDir),
    settingsManager,
    model: selectedModel,
    thinkingLevel: process.env.QUIET_THINKING_LEVEL?.trim() || "medium",
  });

  session.setAutoCompactionEnabled?.(true);
  session.subscribe((event) => translateAgentEvent(event, {
    sessionPath: session.sessionFile,
    sessionId: session.sessionId,
  }));
  currentSession = session;
  emit({ type: "session_current", path: session.sessionFile, id: session.sessionId });
  if (modelFallbackMessage) {
    emit({ type: "status", value: modelFallbackMessage });
  }
  return session;
}

function getPiSession() {
  sessionPromise ??= createPiSession();
  return sessionPromise;
}

async function resetPiSession() {
  const previousSession = currentSession || (sessionPromise ? await sessionPromise.catch(() => undefined) : undefined);
  previousSession?.dispose?.();
  sessionPromise = createPiSession({ fresh: true });
  const session = await sessionPromise;
  currentAssistantId = "";
  currentThinkingId = "";
  currentAssistantMessageId = "";
  toolIdsByProviderId.clear();
  toolIdsByContentIndex.clear();
  startedToolIds.clear();
  emit({ type: "session_reset", path: session.sessionFile, id: session.sessionId });
  await emitSessionList();
}

function textFromContent(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((part) => part?.type === "text" && typeof part.text === "string")
    .map((part) => part.text)
    .join("\n")
    .trim();
}

function readSessionMessages(sessionPath) {
  if (!sessionPath || !existsSync(sessionPath)) return [];
  const lines = readFileSync(sessionPath, "utf8").split("\n");
  const messages = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const entry = JSON.parse(line);
      if (entry.type !== "message") continue;
      const role = entry.message?.role;
      if (role !== "user" && role !== "assistant") continue;
      const text = textFromContent(entry.message?.content);
      if (!text) continue;
      messages.push({
        id: entry.id || randomUUID(),
        role,
        text,
      });
    } catch {
      // Ignore malformed session entries.
    }
  }
  return messages;
}

function sliceSessionMessages(messages, start, end) {
  return messages.slice(start, end).map((message) => ({ ...message }));
}

async function listSessions() {
  const { SessionManager } = await loadPi();
  const sessions = await SessionManager.list(workspaceDir, sessionsDir);
  return sessions.map((session) => ({
    id: session.id,
    path: session.path,
    title: session.name || session.firstMessage || copy.taskTitle,
    created: session.created?.toISOString?.() || String(session.created || ""),
    modified: session.modified?.toISOString?.() || String(session.modified || ""),
    messageCount: session.messageCount || 0,
  }));
}

async function emitSessionList() {
  emit({
    type: "session_list",
    currentPath: currentSession?.sessionFile,
    sessions: await listSessions(),
  });
}

function scheduleSessionListRefresh(delayMs = 0) {
  if (sessionListRefreshTimer) {
    clearTimeout(sessionListRefreshTimer);
  }
  sessionListRefreshTimer = setTimeout(() => {
    sessionListRefreshTimer = undefined;
    void emitSessionList().catch((error) => {
      emit({ type: "error", message: error?.message ?? String(error) });
    });
  }, delayMs);
}

async function openSession(sessionPath) {
  if (!sessionPath || !isInside(sessionsDir, sessionPath) || !existsSync(sessionPath)) {
    throw new Error("Session file not found.");
  }
  const allMessages = readSessionMessages(sessionPath);
  const initialStart = Math.max(0, allMessages.length - initialSessionMessageLimit);
  currentHistoryPath = sessionPath;
  currentHistoryLoadedFromIndex = initialStart;
  emit({
    type: "session_opened",
    path: sessionPath,
    id: "",
    messages: sliceSessionMessages(allMessages, initialStart, allMessages.length),
    hasMore: initialStart > 0,
    pending: true,
  });
  const previousSession = currentSession || (sessionPromise ? await sessionPromise.catch(() => undefined) : undefined);
  previousSession?.dispose?.();
  sessionPromise = createPiSession({ sessionPath });
  const session = await sessionPromise;
  currentAssistantId = "";
  currentThinkingId = "";
  currentAssistantMessageId = "";
  toolIdsByProviderId.clear();
  toolIdsByContentIndex.clear();
  startedToolIds.clear();
  emit({
    type: "session_ready",
    path: session.sessionFile,
    id: session.sessionId,
  });
  await emitSessionList();
}

async function loadSessionHistory(sessionPath) {
  if (!sessionPath || !isInside(sessionsDir, sessionPath) || !existsSync(sessionPath)) {
    throw new Error("Session file not found.");
  }
  if (currentSession?.sessionFile !== sessionPath) return;
  if (currentHistoryPath !== sessionPath) {
    currentHistoryPath = sessionPath;
    currentHistoryLoadedFromIndex = Math.max(0, readSessionMessages(sessionPath).length - initialSessionMessageLimit);
  }
  if (currentHistoryLoadedFromIndex <= 0) {
    emit({
      type: "session_history_batch",
      path: sessionPath,
      messages: [],
      prepend: true,
      hasMore: false,
    });
    return;
  }
  const allMessages = readSessionMessages(sessionPath);
  const end = Math.min(currentHistoryLoadedFromIndex, allMessages.length);
  const start = Math.max(0, end - sessionHistoryBatchSize);
  currentHistoryLoadedFromIndex = start;
  emit({
    type: "session_history_batch",
    path: sessionPath,
    messages: sliceSessionMessages(allMessages, start, end),
    prepend: true,
    hasMore: start > 0,
  });
}

async function deleteSession(sessionPath) {
  if (!sessionPath) return;
  if (!isInside(sessionsDir, sessionPath)) {
    throw new Error("Refusing to delete a file outside the Blackhole sessions directory.");
  }
  const currentPath = currentSession?.sessionFile;
  const isCurrent = currentPath && resolve(currentPath) === resolve(sessionPath);
  if (isCurrent) {
    currentSession?.dispose?.();
    currentSession = undefined;
    sessionPromise = undefined;
  }
  rmSync(sessionPath, { force: true });
  emit({ type: "session_deleted", path: sessionPath });
  if (isCurrent) {
    await resetPiSession();
  } else {
    await emitSessionList();
  }
}

function translateAgentEvent(event, sessionContext = {}) {
  const timestamp = new Date().toISOString();
  const emitSessionEvent = (payload) => emit({ ...payload, ...sessionContext });

  if (event.type === "agent_start") {
    emitSessionEvent({ type: "status", value: "agent 工作中", timestamp });
    return;
  }
  if (event.type === "turn_start") {
    emitSessionEvent({ type: "status", value: "agent 工作中", timestamp });
    return;
  }
  if (event.type === "agent_end") {
    emitSessionEvent({ type: "status", value: "agent 工作完成", timestamp });
    currentAssistantId = "";
    currentThinkingId = "";
    currentAssistantMessageId = "";
    toolIdsByProviderId.clear();
    toolIdsByContentIndex.clear();
    startedToolIds.clear();
    return;
  }
  if (event.type === "message_start") {
    if (event.message?.role === "assistant") {
      currentAssistantMessageId = event.message.id || "";
      toolIdsByProviderId.clear();
      toolIdsByContentIndex.clear();
      startedToolIds.clear();
    }
    return;
  }
  if (event.type === "tool_execution_start") {
    const id = displayToolId(event.toolCallId);
    if (event.toolCallId) toolIdsByProviderId.set(event.toolCallId, id);
    if (startedToolIds.has(id)) {
      emitSessionEvent({
        type: "tool_update",
        id,
        name: event.toolName || "tool",
        value: event.args,
        phase: "input",
        timestamp,
      });
    } else {
      startedToolIds.add(id);
      emitSessionEvent({
        type: "tool_start",
        id,
        name: event.toolName || "tool",
        args: event.args,
        timestamp,
      });
    }
    return;
  }
  if (event.type === "tool_execution_update") {
    emitSessionEvent({
      type: "tool_update",
      id: displayToolId(event.toolCallId),
      name: event.toolName || "tool",
      value: event.partialResult,
      timestamp,
    });
    return;
  }
  if (event.type === "tool_execution_end") {
    const id = displayToolId(event.toolCallId);
    emitSessionEvent({
      type: "tool_end",
      id,
      name: event.toolName || "tool",
      result: event.result,
      isError: Boolean(event.isError),
      timestamp,
    });
    return;
  }
  if (event.type === "message_end") {
    if (event.message?.role === "assistant") {
      scheduleSessionListRefresh();
    }
    return;
  }
  if (event.type !== "message_update") return;

  const messageEvent = event.assistantMessageEvent;
  if (!messageEvent) return;

  if (event.message?.role === "assistant" && Array.isArray(event.message.content)) {
    event.message.content.forEach((part, index) => {
      if (!part || typeof part !== "object" || part.type !== "toolCall") return;
      const providerToolCallId = typeof part.id === "string" && part.id ? part.id : undefined;
      const existingId = toolIdsByContentIndex.get(index);
      const id = existingId || providerToolCallId || `${currentAssistantMessageId || event.message.id || "tool"}-${index}`;
      toolIdsByContentIndex.set(index, id);
      if (providerToolCallId) toolIdsByProviderId.set(providerToolCallId, id);

      const name = typeof part.name === "string" ? part.name : "tool";
      if (!startedToolIds.has(id)) {
        startedToolIds.add(id);
        emitSessionEvent({
          type: "tool_start",
          id,
          name,
          args: part.arguments,
          timestamp,
        });
        return;
      }
      emitSessionEvent({
        type: "tool_update",
        id,
        name,
        value: part.arguments,
        phase: "input",
        timestamp,
      });
    });
  }

  if (messageEvent.type === "text_start") {
    currentAssistantId = randomUUID();
    emitSessionEvent({ type: "assistant_start", id: currentAssistantId, timestamp });
    return;
  }
  if (messageEvent.type === "text_delta") {
    currentAssistantId ||= randomUUID();
    emitSessionEvent({ type: "assistant_delta", id: currentAssistantId, text: messageEvent.delta || "", timestamp });
    return;
  }
  if (messageEvent.type === "text_end") {
    currentAssistantId ||= randomUUID();
    emitSessionEvent({ type: "assistant_done", id: currentAssistantId, timestamp });
    currentAssistantId = "";
    return;
  }
  if (messageEvent.type === "thinking_start") {
    currentThinkingId = randomUUID();
    emitSessionEvent({ type: "thinking_start", id: currentThinkingId, timestamp });
    return;
  }
  if (messageEvent.type === "thinking_delta") {
    currentThinkingId ||= randomUUID();
    emitSessionEvent({ type: "thinking_delta", id: currentThinkingId, text: messageEvent.delta || "", timestamp });
    return;
  }
  if (messageEvent.type === "thinking_end") {
    emitSessionEvent({ type: "thinking_end", id: currentThinkingId, text: messageEvent.content || "", timestamp });
    currentThinkingId = "";
  }
}

function shortStat(path) {
  try {
    const stats = statSync(path);
    return {
      path,
      name: path.split(sep).at(-1),
      kind: stats.isDirectory() ? "directory" : "file",
      size: stats.size,
      mtime: stats.mtime.toISOString(),
    };
  } catch (error) {
    return {
      path,
      missing: true,
      error: error?.message ?? String(error),
    };
  }
}

function buildOrganizePrompt(paths, userText) {
  const resourceList = paths.map(shortStat);
  const rules = language === "zh"
    ? `硬性规则：
1. 只处理本次列出的 00 Inbox 资源：${inboxDir}
2. 请按 ~/.blackhole/memory.md 的规则理解用户的偏好并整理。
3. 必须用 mv 移动，不要复制，不要删除用户文件或资源；成功后 00 Inbox 源路径不应继续存在。
4. 整理后的文件只能放到 Blackhole 根目录：${filesDir}
5. 默认使用 Quiet Decimal 编号结构；优先放进已有编号区域，不要回到旧的纯 subject 一级目录。
6. 常用区域：10-19 Personal 个人、20-29 Money 财务、30-39 Work 工作、40-49 Legal & Admin 法务行政、50-59 Assets & Property 资产、90-99 Archive 归档。
7. 低置信度、敏感冲突、重复冲突、文件名与内容矛盾、或需要用户确认的资源，移动到 ${needsReviewDir}。
8. ${systemArchiveDir} 只放 Blackhole 自己生成的用户可读系统归档记录；不要把原始用户资源放进去。旧的已完成用户资源应放入 90-99 Archive 归档。
9. 目标路径使用 ${filesDir}/<numbered-area>/<numbered-category-or-topic>/<original-name>。
10. 不要新建摘要、索引、报告或说明文档；如需说明，只在对用户的最终回复里简短总结。
11. 按文件名、扩展名和必要内容判断用途；链接和 snippet 已保存为 Markdown 资源文件，不要只按扩展名机械分类。
12. ${copy.organizeDoneRule}`
    : `Hard rules:
1. Only process the 00 Inbox resources listed in this task: ${inboxDir}
2. Follow ~/.blackhole/memory.md to understand the user's preferences and organize accordingly.
3. Move with mv; do not copy or delete user files or resources. After a successful move, the 00 Inbox source path should no longer exist.
4. Organized files must stay directly under the Blackhole root: ${filesDir}
5. Use the Quiet Decimal numbered structure by default. Prefer existing numbered areas; do not fall back to old plain subject top-level folders.
6. Common areas: 10-19 Personal, 20-29 Money, 30-39 Work, 40-49 Legal & Admin, 50-59 Assets & Property, 90-99 Archive.
7. Move low-confidence, sensitive/conflicting, duplicate-conflicting, filename/content mismatch, or user-confirmation-needed resources to ${needsReviewDir}.
8. ${systemArchiveDir} is only for Blackhole-created user-readable system archive records. Do not put original user resources there. Old/completed user resources belong in 90-99 Archive.
9. Use ${filesDir}/<numbered-area>/<numbered-category-or-topic>/<original-name> as the destination pattern.
10. Do not create summaries, indexes, reports, or notes as files. Summarize only in the final user-facing reply.
11. Understand purpose from filenames, extensions, and content when needed. Links and snippets are saved as Markdown resource files; do not classify mechanically by extension only.
12. ${copy.organizeDoneRule}`;
  const pendingLabel = language === "zh" ? "待整理资源" : "Resources to organize";
  return `
${userText || copy.organizeFallback}

${copy.organizeInstruction}

${rules}

Blackhole dirs:
- content root: ${quietContentHome}
- 00 Inbox: ${inboxDir}
- 01 Needs Review: ${needsReviewDir}
- 09 System Archive: ${systemArchiveDir}

${pendingLabel}:
${JSON.stringify(resourceList, null, 2)}
`.trim();
}

async function handleUserMessage(message) {
  const text = String(message.text ?? "").trim();
  const paths = Array.isArray(message.paths) ? message.paths.map((path) => resolve(String(path))) : [];
  const resources = Array.isArray(message.resources)
    ? message.resources
        .map((resource) => ({
          kind: String(resource?.kind || "text"),
          value: String(resource?.value || ""),
        }))
        .filter((resource) => resource.value.trim())
    : [];

  if (paths.length > 0 || resources.length > 0) {
    emit({ type: "status", value: `正在移入 00 Inbox：${paths.length + resources.length} 项` });
    const startedAt = new Date().toISOString();
    const fileIngestion = paths.length > 0
      ? await ingestToInbox(paths)
      : { ingested: [], failed: [] };
    const resourceIngestion = resources.length > 0
      ? await ingestResourcesToInbox(resources)
      : { ingested: [], failed: [] };
    const ingested = [...fileIngestion.ingested, ...resourceIngestion.ingested];
    const failed = [...fileIngestion.failed, ...resourceIngestion.failed];
    if (failed.length > 0) {
      emit({
        type: "error",
        message: `有 ${failed.length} 项未能进入 00 Inbox：${failed[0].reason}`,
      });
    }
    if (ingested.length === 0) {
      emit({ type: "status", value: copy.noStagedResources });
      cleanupInboxDirectories();
      return;
    }
    const batchId = fileIngestion.batchId || resourceIngestion.batchId || startedAt.replace(/[:.]/g, "-");
    const inboxPaths = ingested.map((item) => item.inboxPath);
    emit({ type: "status", value: "agent 工作中" });
    emit({
      type: "plan",
      title: copy.taskTitle,
      items: ingested.map((item) => `${item.originalName} -> ~/Documents/Blackhole/<numbered-area>`),
    });
    const session = await getPiSession();
    try {
      await session.prompt(buildOrganizePrompt(inboxPaths, text), { source: "interactive" });
    } finally {
      writeSystemArchiveRecord({
        batchId,
        startedAt,
        finishedAt: new Date().toISOString(),
        ingested,
        failed,
      });
      cleanupInboxDirectories();
    }
    return;
  }

  const session = await getPiSession();
  await session.prompt(text || `${copy.explainFallback} Blackhole root=${filesDir}.`, {
    source: "interactive",
  });
}

emit({
  type: "ready",
  pid: process.pid,
  protocol: "blackhole-pi-jsonl-v1",
  app: "blackhole",
  filesRoot: filesDir,
  inbox: inboxDir,
  needsReview: needsReviewDir,
  systemArchive: systemArchiveDir,
});

void getPiSession().catch((error) => {
  emit({ type: "error", message: error?.message ?? String(error) });
  if (!fallbackNoticeSent) {
    fallbackNoticeSent = true;
    emit({ type: "status", value: copy.startupFailed });
  }
});

rl.on("line", (line) => {
  if (!line.trim()) return;
  messageQueue = messageQueue
    .then(async () => {
      const message = JSON.parse(line);
      if (message.type === "user_message") {
        await handleUserMessage(message);
        return;
      }
      if (message.type === "new_session") {
        await resetPiSession();
        return;
      }
      if (message.type === "list_sessions") {
        await emitSessionList();
        return;
      }
      if (message.type === "open_session") {
        await openSession(String(message.path || ""));
        return;
      }
      if (message.type === "load_session_history") {
        await loadSessionHistory(String(message.path || ""));
        return;
      }
      if (message.type === "delete_session") {
        await deleteSession(String(message.path || ""));
        return;
      }
      emit({ type: "error", message: `Unknown message type: ${message.type}` });
    })
    .catch((error) => {
      emit({ type: "error", message: error?.message ?? String(error) });
    });
});

process.on("SIGTERM", () => {
  emit({ type: "status", value: "agent stopping" });
  process.exit(0);
});
