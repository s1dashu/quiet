import readline from "node:readline";
import { createHash, randomUUID } from "node:crypto";
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

const neatHome = resolve(process.env.NEAT_HOME?.trim() || join(homedir(), ".neat"));
const inboxDir = join(neatHome, "inbox");
const filesDir = join(neatHome, "files");
const outputDir = join(neatHome, "output");
const undoDir = join(neatHome, "undo");
const logDir = join(neatHome, "logs");
const agentDir = join(neatHome, "pi-agent");
const workspaceDir = join(neatHome, "workspace");
const memoryPath = join(neatHome, "memory.md");
const promptPath = new URL("./neat-prompt.md", import.meta.url);

mkdirSync(inboxDir, { recursive: true });
mkdirSync(filesDir, { recursive: true });
mkdirSync(outputDir, { recursive: true });
mkdirSync(undoDir, { recursive: true });
mkdirSync(logDir, { recursive: true });
mkdirSync(agentDir, { recursive: true });
mkdirSync(workspaceDir, { recursive: true });

const defaultMemory = `
# Neat Memory

These are user-editable file organizing rules for Neat.

## Learning User Preferences

- When the user expresses a stable preference for how files should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
- Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
- Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
- This file is located at \`NEAT_HOME/memory.md\`; you may edit it with bash when updating remembered organizing preferences.

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

\`NEAT_HOME/files/<category>/<YYYY-MM>/<original-name>\`

## Conversation Style

- Be concise.
- Tell the user what was moved and where.
- When a problem occurs, name the failed file and continue with the rest.
- Do not mention internal logs, manifests, or implementation files unless the user asks.
`.trim();

const memoryPreferenceGuidance = `
## Learning User Preferences

- When the user expresses a stable preference for how files should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
- Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
- Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
- This file is located at \`NEAT_HOME/memory.md\`; you may edit it with bash when updating remembered organizing preferences.
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
let messageQueue = Promise.resolve();
let currentAssistantId = "";
let currentThinkingId = "";
const toolIdsByProviderId = new Map();
let fallbackNoticeSent = false;

function emit(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
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

function safeName(name) {
  const cleaned = String(name)
    .normalize("NFC")
    .replace(/[/:]/g, "-")
    .replace(/\s+/g, " ")
    .trim();
  return cleaned || "Untitled";
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

function writeUndoRecord(record) {
  mkdirSync(undoDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const hash = createHash("sha1").update(JSON.stringify(record.moves)).digest("hex").slice(0, 8);
  const path = join(undoDir, `${stamp}-${hash}.json`);
  writeFileSync(path, `${JSON.stringify(record, null, 2)}\n`, "utf8");
  writeFileSync(join(undoDir, "latest.json"), `${JSON.stringify({ path }, null, 2)}\n`, "utf8");
  return path;
}

function readLatestUndoPath() {
  const latestPath = join(undoDir, "latest.json");
  if (!existsSync(latestPath)) return undefined;
  try {
    const parsed = JSON.parse(readFileSync(latestPath, "utf8"));
    return typeof parsed.path === "string" ? parsed.path : undefined;
  } catch {
    return undefined;
  }
}

function snapshotForUndo(path) {
  const stats = statSync(path);
  return {
    source: path,
    inboxPath: path,
    originalName: safeName(path.split(sep).at(-1)),
    dev: stats.dev,
    ino: stats.ino,
    size: stats.size,
    mtimeMs: stats.mtimeMs,
  };
}

function walkPaths(root) {
  if (!existsSync(root)) return [];
  const paths = [];
  const entries = readdirSync(root, { withFileTypes: true });
  for (const entry of entries) {
    const path = join(root, entry.name);
    paths.push(path);
    if (entry.isDirectory()) {
      paths.push(...walkPaths(path));
    }
  }
  return paths;
}

function findMovedDestination(snapshot, candidates) {
  for (const candidate of candidates) {
    try {
      const stats = statSync(candidate);
      if (stats.dev === snapshot.dev && stats.ino === snapshot.ino) {
        return candidate;
      }
    } catch {
      // Candidate disappeared while scanning; continue.
    }
  }

  return candidates.find((candidate) => {
    try {
      const stats = statSync(candidate);
      return candidate.split(sep).at(-1) === snapshot.originalName &&
        stats.size === snapshot.size &&
        stats.mtimeMs === snapshot.mtimeMs;
    } catch {
      return false;
    }
  });
}

function writeUndoRecordForMovedSnapshots(snapshots) {
  const candidates = walkPaths(filesDir);
  const moves = [];
  for (const snapshot of snapshots) {
    if (existsSync(snapshot.source)) continue;
    const destination = findMovedDestination(snapshot, candidates);
    if (!destination || !isInside(filesDir, destination)) continue;
    moves.push({
      source: snapshot.source,
      destination,
      inboxPath: snapshot.inboxPath,
      originalName: snapshot.originalName,
    });
  }
  if (!moves.length) return;
  const undoPath = writeUndoRecord({
    version: 1,
    id: randomUUID(),
    createdAt: new Date().toISOString(),
    filesRoot: filesDir,
    moves,
  });
  emit({
    type: "organized",
    filesRoot: filesDir,
    moved: moves,
    failed: [],
    undoPath,
  });
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
      if (isInside(neatHome, source)) {
        throw new Error("文件已经在 ~/.neat 内");
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

async function undoLatestMove() {
  const undoPath = readLatestUndoPath();
  if (!undoPath || !existsSync(undoPath)) {
    return { restored: [], failed: [{ reason: "没有可撤回的整理记录" }] };
  }

  const record = JSON.parse(readFileSync(undoPath, "utf8"));
  const restored = [];
  const failed = [];
  for (const move of [...record.moves].reverse()) {
    try {
      if (!isInside(filesDir, move.destination)) {
        throw new Error("撤回来源不在 ~/.neat/files 内");
      }
      if (!existsSync(move.destination)) {
        throw new Error("目标文件已经不存在");
      }
      const preferredRestore = typeof move.inboxPath === "string" ? move.inboxPath : move.source;
      const restoreDestination = existsSync(preferredRestore)
        ? uniqueDestination(dirname(preferredRestore), safeName(move.originalName || preferredRestore.split(sep).at(-1)))
        : preferredRestore;
      await movePath(move.destination, restoreDestination);
      restored.push({ ...move, restoredTo: restoreDestination });
    } catch (error) {
      failed.push({ ...move, reason: error?.message ?? String(error) });
    }
  }

  rmSync(join(undoDir, "latest.json"), { force: true });
  return { restored, failed };
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
    throw new Error("找不到 @earendil-works/pi-coding-agent。请先运行 npm install，或重新打包 Neat.app。");
  }
  return import(pathToFileURL(entry).href);
}

function selectModel(modelRegistry) {
  const provider = process.env.NEAT_MODEL_PROVIDER?.trim() || "deepseek";
  const modelId = process.env.NEAT_MODEL_ID?.trim() || "deepseek-v4-flash";
  return modelRegistry.find(provider, modelId) || undefined;
}

async function createPiSession() {
  const {
    AuthStorage,
    createAgentSession,
    DefaultResourceLoader,
    ModelRegistry,
    SessionManager,
    SettingsManager,
  } = await loadPi();

  const authStorage = AuthStorage.create(join(agentDir, "auth.json"));
  const modelRegistry = ModelRegistry.create(authStorage, join(agentDir, "models.json"));
  const settingsManager = SettingsManager.create(workspaceDir, agentDir, { projectTrusted: true });
  settingsManager.applyOverrides({
    defaultProvider: process.env.NEAT_MODEL_PROVIDER?.trim() || "deepseek",
    defaultModel: process.env.NEAT_MODEL_ID?.trim() || "deepseek-v4-flash",
    defaultThinkingLevel: process.env.NEAT_THINKING_LEVEL?.trim() || "medium",
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
    sessionManager: SessionManager.continueRecent(workspaceDir, join(agentDir, "sessions")),
    settingsManager,
    model: selectedModel,
    thinkingLevel: process.env.NEAT_THINKING_LEVEL?.trim() || "medium",
    tools: ["read", "bash", "grep", "find", "ls"],
  });

  session.setAutoCompactionEnabled?.(true);
  session.subscribe(translateAgentEvent);
  if (modelFallbackMessage) {
    emit({ type: "status", value: modelFallbackMessage });
  }
  return session;
}

function getPiSession() {
  sessionPromise ??= createPiSession();
  return sessionPromise;
}

function translateAgentEvent(event) {
  const timestamp = new Date().toISOString();

  if (event.type === "agent_start") {
    emit({ type: "status", value: "agent 工作中", timestamp });
    return;
  }
  if (event.type === "turn_start") {
    emit({ type: "status", value: "agent 工作中", timestamp });
    return;
  }
  if (event.type === "agent_end") {
    emit({ type: "status", value: "agent 工作完成", timestamp });
    currentAssistantId = "";
    currentThinkingId = "";
    toolIdsByProviderId.clear();
    return;
  }
  if (event.type === "tool_execution_start") {
    const id = event.toolCallId || randomUUID();
    toolIdsByProviderId.set(event.toolCallId, id);
    emit({
      type: "tool_start",
      id,
      name: event.toolName || "tool",
      args: event.args,
      timestamp,
    });
    return;
  }
  if (event.type === "tool_execution_update") {
    emit({
      type: "tool_update",
      id: toolIdsByProviderId.get(event.toolCallId) || event.toolCallId || randomUUID(),
      name: event.toolName || "tool",
      value: event.partialResult,
      timestamp,
    });
    return;
  }
  if (event.type === "tool_execution_end") {
    emit({
      type: "tool_end",
      id: toolIdsByProviderId.get(event.toolCallId) || event.toolCallId || randomUUID(),
      name: event.toolName || "tool",
      result: event.result,
      isError: Boolean(event.isError),
      timestamp,
    });
    return;
  }
  if (event.type !== "message_update") return;

  const messageEvent = event.assistantMessageEvent;
  if (!messageEvent) return;

  if (messageEvent.type === "text_start") {
    currentAssistantId = randomUUID();
    emit({ type: "assistant_start", id: currentAssistantId, timestamp });
    return;
  }
  if (messageEvent.type === "text_delta") {
    currentAssistantId ||= randomUUID();
    emit({ type: "assistant_delta", id: currentAssistantId, text: messageEvent.delta || "", timestamp });
    return;
  }
  if (messageEvent.type === "text_end") {
    currentAssistantId ||= randomUUID();
    emit({ type: "assistant_done", id: currentAssistantId, timestamp });
    currentAssistantId = "";
    return;
  }
  if (messageEvent.type === "thinking_start") {
    currentThinkingId = randomUUID();
    emit({ type: "thinking_start", id: currentThinkingId, timestamp });
    return;
  }
  if (messageEvent.type === "thinking_delta") {
    currentThinkingId ||= randomUUID();
    emit({ type: "thinking_delta", id: currentThinkingId, text: messageEvent.delta || "", timestamp });
    return;
  }
  if (messageEvent.type === "thinking_end") {
    emit({ type: "thinking_end", id: currentThinkingId, text: messageEvent.content || "", timestamp });
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
  const fileList = paths.map(shortStat);
  return `
${userText || "请整理这些文件。"}

你现在是 Neat 的 pi-coding-agent。请真实使用 read/ls/grep/find/bash 工具理解并整理文件。

硬性规则：
1. 用户拖入的文件已经进入 inbox：${inboxDir}
2. 你只能整理这次任务列出的 inbox 文件。
3. 整理完成的文件必须放在 files：${filesDir}
4. 禁止把整理后的文件移动到 ${filesDir} 之外。
5. 如果你需要创作新内容、摘要、报告、索引、说明文档，统一写到 output：${outputDir}
6. 禁止删除用户文件。
7. 可以用 bash 创建目录、读取文件摘要、移动文件。
8. 按文件名、扩展名、必要时按内容理解用途，不要只按扩展名机械分类。
9. 目录结构由你决定，但必须清晰、可解释、稳定。
10. 整理必须是移动，不是复制：请使用 mv，不要使用 cp。成功后 inbox 源路径不应该继续存在。
11. 按 system prompt 中追加的 memory.md 整理规则选择目录和命名。
12. 整理完成后，用中文简短总结你做了什么；不要提内部日志、manifest 或实现文件。

Neat dirs:
- inbox: ${inboxDir}
- files: ${filesDir}
- output: ${outputDir}

待整理文件：
${JSON.stringify(fileList, null, 2)}
`.trim();
}

function emitObservedMoves() {
  const latest = join(undoDir, "latest-agent.json");
  if (!existsSync(latest)) return false;
  try {
    const parsed = JSON.parse(readFileSync(latest, "utf8"));
    const moves = Array.isArray(parsed.moves) ? parsed.moves : [];
    const validMoves = moves.filter((move) =>
      typeof move?.source === "string" &&
      typeof move?.destination === "string" &&
      isInside(filesDir, move.destination)
    );
    if (!validMoves.length) return false;
    const finalizedMoves = [];
    const failed = [];
    for (const move of validMoves) {
      const source = resolve(move.source);
      const destination = resolve(move.destination);
      try {
        if (!existsSync(destination)) {
          throw new Error("目标文件不存在，无法确认已整理");
        }
        if (existsSync(source)) {
          rmSync(source, { recursive: true, force: false });
        }
        finalizedMoves.push({ ...move, source, destination });
      } catch (error) {
        failed.push({ ...move, reason: error?.message ?? String(error) });
      }
    }
    if (!finalizedMoves.length && failed.length) {
      emit({ type: "error", message: `pi 整理结果校验失败：${failed[0].reason}` });
      return false;
    }
    const undoPath = writeUndoRecord({
      version: 1,
      id: randomUUID(),
      createdAt: new Date().toISOString(),
      filesRoot: filesDir,
      moves: finalizedMoves.map((move) => ({
        source: move.source,
        destination: move.destination,
        inboxPath: move.source,
        originalName: safeName(move.originalName || move.source.split(sep).at(-1)),
      })),
    });
    emit({
      type: "organized",
      filesRoot: filesDir,
      moved: finalizedMoves,
      failed,
      undoPath,
    });
    return true;
  } catch (error) {
    emit({ type: "error", message: `读取整理记录失败：${error?.message ?? String(error)}` });
    return false;
  } finally {
    rmSync(latest, { force: true });
  }
}

function isUndoCommand(text) {
  return /^(?:undo|撤回|撤销)$/iu.test(text.trim());
}

async function handleUserMessage(message) {
  const text = String(message.text ?? "").trim();
  const paths = Array.isArray(message.paths) ? message.paths.map((path) => resolve(String(path))) : [];

  if (isUndoCommand(text) && paths.length === 0) {
    emit({ type: "status", value: "正在撤回上一批整理" });
    const result = await undoLatestMove();
    const id = randomUUID();
    emit({ type: "assistant_start", id });
    emit({
      type: "assistant_delta",
      id,
      text:
        result.restored.length > 0
          ? `已撤回 ${result.restored.length} 项。`
          : `没有完成撤回。${result.failed[0]?.reason ?? "没有找到最近的 undo 记录。"}`,
    });
    emit({ type: "assistant_done", id });
    emit({ type: "status", value: result.restored.length > 0 ? "撤回完成" : "撤回失败" });
    return;
  }

  if (paths.length > 0) {
    emit({ type: "status", value: `正在移入 inbox：${paths.length} 项` });
    const ingestion = await ingestToInbox(paths);
    if (ingestion.failed.length > 0) {
      emit({
        type: "error",
        message: `有 ${ingestion.failed.length} 项未能进入 inbox：${ingestion.failed[0].reason}`,
      });
    }
    if (ingestion.ingested.length === 0) {
      emit({ type: "status", value: "没有文件进入 inbox" });
      return;
    }
    const inboxPaths = ingestion.ingested.map((item) => item.inboxPath);
    const undoSnapshots = inboxPaths.map(snapshotForUndo);
    emit({ type: "status", value: "agent 工作中" });
    emit({
      type: "plan",
      title: "agent 整理任务",
      items: ingestion.ingested.map((item) => `${item.originalName} -> ~/.neat/inbox -> ~/.neat/files`),
    });
    const session = await getPiSession();
    await session.prompt(buildOrganizePrompt(inboxPaths, text), { source: "interactive" });
    if (!emitObservedMoves()) {
      writeUndoRecordForMovedSnapshots(undoSnapshots);
    }
    return;
  }

  const session = await getPiSession();
  await session.prompt(text || `请说明你会如何整理拖入 Neat 的文件。inbox=${inboxDir} files=${filesDir} output=${outputDir}。`, {
    source: "interactive",
  });
}

emit({
  type: "ready",
  pid: process.pid,
  protocol: "neat-pi-jsonl-v1",
  app: "neat",
  filesRoot: filesDir,
  inbox: inboxDir,
  output: outputDir,
});

void getPiSession().catch((error) => {
  emit({ type: "error", message: error?.message ?? String(error) });
  if (!fallbackNoticeSent) {
    fallbackNoticeSent = true;
    emit({ type: "status", value: "agent 启动失败，请检查模型 API Key 或 node_modules" });
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
