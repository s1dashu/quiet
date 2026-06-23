import readline from "node:readline";
import { randomUUID } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  cpSync,
  readdirSync,
  readFileSync,
  renameSync,
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

function migrateDefaultDirectory(legacyDir, currentDir) {
  if (legacyDir === currentDir || !existsSync(legacyDir)) return currentDir;
  if (!existsSync(currentDir)) {
    try {
      renameSync(legacyDir, currentDir);
      return currentDir;
    } catch {
      mkdirSync(currentDir, { recursive: true });
    }
  } else {
    mkdirSync(currentDir, { recursive: true });
  }

  for (const entry of readdirSync(legacyDir, { withFileTypes: true })) {
    const source = join(legacyDir, entry.name);
    const destination = uniqueDestination(currentDir, safeName(entry.name));
    try {
      renameSync(source, destination);
    } catch {
      cpSync(source, destination, { recursive: true, preserveTimestamps: true, force: false, errorOnExist: true });
      rmSync(source, { recursive: true, force: true });
    }
  }
  rmSync(legacyDir, { recursive: true, force: true });
  return currentDir;
}

const defaultQuietHome = migrateDefaultDirectory(join(homedir(), ".blackhole"), join(homedir(), ".quiet"));
const defaultQuietContentHome = migrateDefaultDirectory(join(homedir(), "Documents", "Blackhole"), join(homedir(), "Documents", "Quiet"));
const quietHome = resolve(process.env.QUIET_HOME?.trim() || defaultQuietHome);
const quietContentHome = resolve(process.env.QUIET_CONTENT_HOME?.trim() || defaultQuietContentHome);
const systemAreaDir = join(quietContentHome, "00-09 System-management area");
const systemManagementDir = join(systemAreaDir, "00 System-management category");
const indexDir = join(systemManagementDir, "00.00 JDex for the system");
const inboxDir = join(systemManagementDir, "00.01 Inbox for the system");
const archiveDir = join(systemManagementDir, "00.09 Archive for the system");
const filesDir = quietContentHome;
const logDir = join(quietHome, "logs");
const agentDir = join(quietHome, "pi-agent");
const workspaceDir = join(quietHome, "workspace");
const memoryPath = join(quietHome, "memory.md");
const sessionsDir = join(agentDir, "sessions");
const promptPath = new URL("./agent-prompt.md", import.meta.url);
const language = process.env.QUIET_LANGUAGE?.trim() === "zh" ? "zh" : "en";
const initialSessionMessageLimit = 20;
const sessionHistoryBatchSize = 10;
const areaCategorySpecs = [
  {
    area: "10-19 Personal 个人",
    categories: [
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
    ],
  },
  {
    area: "20-29 Money 财务",
    categories: [
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
    ],
  },
  {
    area: "30-39 Work 工作",
    categories: [
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
    ],
  },
  {
    area: "40-49 Legal & Admin 法务行政",
    categories: [
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
    ],
  },
  {
    area: "50-59 Assets & Property 资产",
    categories: [
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
    ],
  },
  {
    area: "90-99 Archive 归档",
    categories: [
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
    ],
  },
];
const copy = language === "zh"
  ? {
      startupFailed: "agent 启动失败，请检查模型 API Key 或 node_modules",
      organizeFallback: "请处理这些内容。",
      organizeInstruction: "你现在是 Quiet 的 pi-coding-agent。请真实使用可用的 pi 工具理解并整理文件、链接、Snippet 和其他资源。",
      organizeDoneRule: "整理完成后，用中文简短总结你做了什么；不要提内部运行日志、manifest 或实现文件。",
      explainFallback: "请说明你会如何处理丢进 Quiet 的文件、链接和文本片段。",
      noStagedResources: "没有资源进入 00.01 Inbox",
      taskTitle: "agent 资源整理任务",
    }
  : {
      startupFailed: "Agent failed to start. Check the model API key or node_modules.",
      organizeFallback: "Please handle this content.",
      organizeInstruction: "You are Quiet's pi-coding-agent. Use the available pi tools to understand and organize files, links, snippets, and other resources.",
      organizeDoneRule: "When finished, briefly summarize what you moved and where in English; do not mention internal runtime logs, manifests, or implementation files.",
      explainFallback: "Explain how you would handle files, links, and snippets dropped into Quiet.",
      noStagedResources: "No resources entered 00.01 Inbox",
      taskTitle: "Agent resource organization task",
    };

function categoryMapText() {
  return areaCategorySpecs
    .map((spec) => [
      `- \`${spec.area}\``,
      ...spec.categories.map((category) => `  - \`${category}\``),
    ].join("\n"))
    .join("\n");
}

mkdirSync(filesDir, { recursive: true });
mkdirSync(logDir, { recursive: true });
mkdirSync(agentDir, { recursive: true });
mkdirSync(workspaceDir, { recursive: true });

function ensureQuietDecimalStructure() {
  const dirs = [
    systemAreaDir,
    systemManagementDir,
    indexDir,
    inboxDir,
    archiveDir,
    ...areaCategorySpecs.flatMap((spec) => [
      join(quietContentHome, spec.area),
      ...spec.categories.map((category) => join(quietContentHome, spec.area, category)),
    ]),
  ];
  for (const dir of dirs) {
    mkdirSync(dir, { recursive: true });
  }
  cleanupEmptyAutoCreatedStandardZeroDirs();
  migrateLegacyTopLevelDirectories();

  const indexPath = join(indexDir, "00.00 JDex for the system.md");
  if (!existsSync(indexPath)) {
    writeFileSync(indexPath, `# 00.00 JDex for the system

Quiet uses a Johnny.Decimal system. The JDex is the master record for the system's IDs: create or update JDex entries before creating new IDs elsewhere.

## 00-09 System-management area

- 00.00 JDex for the system
- 00.01 Inbox for the system
- 00.09 Archive for the system

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

function cleanupEmptyAutoCreatedStandardZeroDirs() {
  const standardZeroNames = new Set([
    "JDex",
    "Inbox",
    "Task & project management",
    "Templates",
    "Links",
    "Archive",
  ]);
  const systemStandardZeroDirs = [
    "00.02 Task & project management for the system",
    "00.03 Templates for the system",
    "00.04 Links for the system",
  ].map((name) => join(systemManagementDir, name));

  const categoryStandardZeroDirs = areaCategorySpecs.flatMap((spec) => (
    spec.categories.flatMap((category) => {
      const categoryNumber = category.slice(0, 2);
      const categoryDir = join(quietContentHome, spec.area, category);
      return readdirIfDirectory(categoryDir)
        .filter((entry) => {
          if (!entry.isDirectory()) return false;
          if (!entry.name.startsWith(`${categoryNumber}.`)) return false;
          return [...standardZeroNames].some((name) => entry.name.includes(name));
        })
        .map((entry) => join(categoryDir, entry.name));
    })
  ));

  for (const dir of [...systemStandardZeroDirs, ...categoryStandardZeroDirs]) {
    removeDirectoryIfEmpty(dir);
  }
}

function readdirIfDirectory(dir) {
  try {
    if (!existsSync(dir) || !statSync(dir).isDirectory()) return [];
    return readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
}

function removeDirectoryIfEmpty(dir) {
  try {
    if (!existsSync(dir) || !statSync(dir).isDirectory()) return;
    if (readdirSync(dir).length > 0) return;
    rmSync(dir, { recursive: true, force: false });
  } catch {
    // Preserve anything we cannot prove is an empty auto-created directory.
  }
}

function migrateLegacyTopLevelDirectories() {
  const migrations = [
    ["00 Inbox 待整理", inboxDir],
    ["Inbox", inboxDir],
    ["Files", inboxDir],
    ["Output", archiveDir],
    ["01 Needs Review 需确认", inboxDir],
    ["09 System Archive 系统归档", archiveDir],
    [".inbox", inboxDir],
    ["00-09 System management/00 System management/00.00 Index for Blackhole", indexDir],
    ["00-09 System management/00 System management/00.01 Inbox for Blackhole", inboxDir],
    ["00-09 System management/00 System management/00.08 Someday for Blackhole", archiveDir],
    ["00-09 System management/00 System management/00.09 Archive for Blackhole", archiveDir],
    ["00-09 System management/00 System management/00.00 Index for Quiet", indexDir],
    ["00-09 System management/00 System management/00.01 Inbox for Quiet", inboxDir],
    ["00-09 System management/00 System management/00.08 Someday for Quiet", archiveDir],
    ["00-09 System management/00 System management/00.09 Archive for Quiet", archiveDir],
  ];
  for (const [legacyName, destinationDir] of migrations) {
    const legacyDir = join(quietContentHome, legacyName);
    if (!existsSync(legacyDir) || !statSync(legacyDir).isDirectory()) continue;
    mkdirSync(destinationDir, { recursive: true });
    for (const entry of readdirSync(legacyDir, { withFileTypes: true })) {
      const source = join(legacyDir, entry.name);
      const destination = uniqueDestination(destinationDir, safeName(entry.name));
      cpSync(source, destination, { recursive: true, preserveTimestamps: true, force: false, errorOnExist: true });
      rmSync(source, { recursive: true, force: false });
    }
    rmSync(legacyDir, { recursive: true, force: true });
  }
  rmSync(join(quietContentHome, "00-09 System management"), { recursive: true, force: true });
}

ensureQuietDecimalStructure();

const defaultMemory = `
# Quiet Memory

These are user-editable resource organizing rules for Quiet.

## Method Initialization

Status: uninitialized

Quiet has not chosen the user's final file organizing method yet.

- Until this status is changed, do not assume Johnny.Decimal, PARA, or any other final method.
- At the start of a chat or before organizing files, ask the user to choose one organizing preference:
  1. PARA: best for most people; simple, action-oriented, and organized around Projects, Areas, Resources, and Archives.
  2. Johnny.Decimal: best for highly structured users who want stable numeric addresses and do not mind maintaining a stricter system.
  3. Custom: the user can describe their own preferred filing rules.
- After the user clearly chooses a method, edit this memory file immediately.
- When editing after a choice, remove this uninitialized onboarding section and remove all non-selected candidate methods. Keep only one final organizing method.
- The final method section must be titled exactly \`## Final Organizing Method: PARA\`, \`## Final Organizing Method: Johnny.Decimal\`, or \`## Final Organizing Method: Custom\`.
- If the user chooses PARA or Johnny.Decimal, write the corresponding final method from the candidate below. If the user chooses Custom, summarize their custom rules as the only final method.

## Learning User Preferences

- When the user expresses a stable preference for how resources should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
- Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
- Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
- This file is located at \`QUIET_HOME/memory.md\`; you may edit it with bash when updating remembered organizing preferences.

## Candidate Method: PARA

Use this only if the user chooses PARA. PARA is a light, general-purpose method for most people.

- Organize by current usefulness and action context, not by a rigid taxonomy.
- Use four top-level folders:
  - \`1 Projects\`: active outcomes with a finish line.
  - \`2 Areas\`: ongoing parts of the user's life/work that they maintain or revisit.
  - \`3 Resources\`: reference material, community/third-party material, topics, learning, inspiration, and reusable knowledge.
  - \`4 Archives\`: inactive projects, old areas, stale resources, and completed material.
- Prefer simple names and shallow nesting.
- When unsure whether something is an Area or Resource, ask whether it is part of the user's own ongoing life/work system or merely reference material.
- Inbox material may stay in Quiet's system inbox until the user confirms where it belongs.

## Candidate Method: Johnny.Decimal

Use this only if the user chooses Johnny.Decimal. Johnny.Decimal is stricter and fits users who want a stable numeric address system.

- Use Quiet's Johnny.Decimal area/category structure directly.
- Quiet pre-creates only the area/category skeleton plus the system-level \`00.00 JDex\`, \`00.01 Inbox\`, and \`00.09 Archive\`.
- Do not automatically create \`AC.00\`, \`AC.01\`, \`AC.02\`, \`AC.03\`, \`AC.04\`, or \`AC.09\` inside every category.
- Create specific \`AC.ID\` folders only when there is real content or the user asks.
- New drops enter \`00-09 System-management area/00 System-management category/00.01 Inbox for the system\` until organized.
- The JDex lives in \`00-09 System-management area/00 System-management category/00.00 JDex for the system\`.
- Prefer a specific content ID such as \`15.52 Trip to NYC\` over a category-level standard-zero folder.
- Use category-level Inbox/Archive/Tasks/Templates/Links only when the user explicitly wants that bucket for that category.
- Prefer existing numbered areas over creating new top-level folders.
- Do not create or use \`.05\`, \`.06\`, \`.07\`, or \`.08\`; these are reserved.

## Default Areas and Categories

${categoryMapText()}

## Johnny.Decimal Destination Pattern

\`QUIET_CONTENT_HOME/<area>/<category>/<AC.ID specific-content-folder>/<original-name>\`

## Candidate Method: Custom

Use this only if the user describes a custom filing preference.

- Ask concise follow-up questions until the rules are concrete enough to organize files.
- Then rewrite this memory file so only the user's custom method remains.
- Preserve exact naming, grouping, and destination preferences the user gives.

## Conversation Style

- Be concise.
- Tell the user what was captured, moved, and where.
- When a problem occurs, name the failed file and continue with the rest.
- Always respond in user's language.
`.trim();

const memoryPreferenceGuidance = `
## Learning User Preferences

- When the user expresses a stable preference for how resources should be categorized, named, or arranged, update this memory file so future organizing tasks follow it.
- Only record durable preferences. Do not record one-off instructions unless the user asks you to remember them.
- Keep memory edits concise and user-facing. Do not record internal logs, manifests, or implementation details.
- This file is located at \`QUIET_HOME/memory.md\`; you may edit it with bash when updating remembered organizing preferences.
`.trim();

const methodOnboardingGuidance = `
## Method Initialization

Status: uninitialized

Quiet has not chosen the user's final file organizing method yet.

- Until this status is changed, do not assume Johnny.Decimal, PARA, or any other final method.
- At the start of a chat or before organizing files, ask the user to choose one organizing preference:
  1. PARA: best for most people; simple, action-oriented, and organized around Projects, Areas, Resources, and Archives.
  2. Johnny.Decimal: best for highly structured users who want stable numeric addresses and do not mind maintaining a stricter system.
  3. Custom: the user can describe their own preferred filing rules.
- After the user clearly chooses a method, edit this memory file immediately.
- When editing after a choice, remove this uninitialized onboarding section and remove all non-selected candidate methods. Keep only one final organizing method.
- The final method section must be titled exactly \`## Final Organizing Method: PARA\`, \`## Final Organizing Method: Johnny.Decimal\`, or \`## Final Organizing Method: Custom\`.
`.trim();

const candidateMethodGuidance = `
## Candidate Method: PARA

Use this only if the user chooses PARA. PARA is a light, general-purpose method for most people.

- Use four top-level folders: \`1 Projects\`, \`2 Areas\`, \`3 Resources\`, and \`4 Archives\`.
- Projects are active outcomes with a finish line.
- Areas are ongoing parts of the user's life/work that they maintain or revisit.
- Resources are reference material, community/third-party material, topics, learning, inspiration, and reusable knowledge.
- Archives are inactive projects, old areas, stale resources, and completed material.

## Candidate Method: Johnny.Decimal

Use this only if the user chooses Johnny.Decimal. Johnny.Decimal is stricter and fits users who want a stable numeric address system.

- Use Quiet's Johnny.Decimal area/category structure directly.
- Quiet pre-creates only the area/category skeleton plus the system-level \`00.00 JDex\`, \`00.01 Inbox\`, and \`00.09 Archive\`.
- Do not automatically create \`AC.00\`, \`AC.01\`, \`AC.02\`, \`AC.03\`, \`AC.04\`, or \`AC.09\` inside every category.
- Create specific \`AC.ID\` folders only when there is real content or the user asks.
- New drops enter \`00-09 System-management area/00 System-management category/00.01 Inbox for the system\` until organized.
- The JDex lives in \`00-09 System-management area/00 System-management category/00.00 JDex for the system\`.
- Prefer a specific content ID such as \`15.52 Trip to NYC\` over a category-level standard-zero folder.
- Use category-level Inbox/Archive/Tasks/Templates/Links only when the user explicitly wants that bucket for that category.

## Default Areas and Categories

${categoryMapText()}

## Johnny.Decimal Destination Pattern

\`QUIET_CONTENT_HOME/<area>/<category>/<AC.ID specific-content-folder>/<original-name>\`

## Candidate Method: Custom

Use this only if the user describes a custom filing preference.

- Ask concise follow-up questions until the rules are concrete enough to organize files.
- Then rewrite this memory file so only the user's custom method remains.
- Preserve exact naming, grouping, and destination preferences the user gives.
`.trim();

function migrateMemoryText(memory) {
  let next = memory.trim();
  const legacyDefaultJohnnyPattern = /\n## (?:Default Method: Johnny\.Decimal System|Johnny\.Decimal System)\n[\s\S]*?(?=\n## Conversation Style|\n## Learning User Preferences|$)/;
  const hasFinalMethod = /## Final Organizing Method:/i.test(next);
  const hasOnboarding = next.includes("Status: uninitialized") || next.includes("## Method Initialization");

  if (!hasFinalMethod && !hasOnboarding && legacyDefaultJohnnyPattern.test(next)) {
    next = next.replace(legacyDefaultJohnnyPattern, `\n${methodOnboardingGuidance}\n\n${candidateMethodGuidance}\n`);
  }

  if (!next.includes("## Learning User Preferences")) {
    next = `${next}\n\n${memoryPreferenceGuidance}`;
  }

  if (!hasFinalMethod && !next.includes("## Method Initialization")) {
    const conversationIndex = next.indexOf("\n## Conversation Style");
    if (conversationIndex >= 0) {
      next = `${next.slice(0, conversationIndex).trim()}\n\n${methodOnboardingGuidance}\n\n${candidateMethodGuidance}\n${next.slice(conversationIndex)}`;
    } else {
      next = `${next}\n\n${methodOnboardingGuidance}\n\n${candidateMethodGuidance}`;
    }
  }

  next = next
    .replace(/`QUIET_CONTENT_HOME\/<subject>\/<original-name>`/g, "`QUIET_CONTENT_HOME/<final-method-destination>/<original-name>`")
    .replace(/`QUIET_CONTENT_HOME\/<numbered-area>\/<numbered-category-or-topic>\/<original-name>`/g, "`QUIET_CONTENT_HOME/<final-method-destination>/<original-name>`")
    .replace(/<AC\.ID standard-zero-or-specific-ID>/g, "<AC.ID specific-content-folder>")
    .replace(/Blackhole/g, "Quiet")
    .replace(/blackhole/g, "quiet");
  next = next.replace(/\n- Do not mention internal logs, manifests, or implementation files unless the user asks\./g, "");
  if (next.includes("## Conversation Style") && !next.includes("Always respond in user's language.")) {
    next = `${next}\n- Always respond in user's language.`;
  }
  return `${next.trim()}\n`;
}

function ensureMemoryFile() {
  if (!existsSync(memoryPath)) {
    writeFileSync(memoryPath, `${defaultMemory}\n`, "utf8");
    return;
  }
  const memory = readFileSync(memoryPath, "utf8");
  const migrated = migrateMemoryText(memory);
  if (migrated !== memory) {
    writeFileSync(memoryPath, migrated, "utf8");
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
        throw new Error("文件已经在 Quiet 目录内");
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

function imageExtension(resource) {
  const name = safeName(String(resource?.name || ""));
  const mimeType = String(resource?.mimeType || "").toLowerCase();
  if (name.toLowerCase().endsWith(".jpg") || name.toLowerCase().endsWith(".jpeg")) return "jpg";
  if (name.toLowerCase().endsWith(".gif")) return "gif";
  if (name.toLowerCase().endsWith(".webp")) return "webp";
  if (name.toLowerCase().endsWith(".tif") || name.toLowerCase().endsWith(".tiff")) return "tiff";
  if (mimeType.includes("jpeg")) return "jpg";
  if (mimeType.includes("gif")) return "gif";
  if (mimeType.includes("webp")) return "webp";
  if (mimeType.includes("tiff")) return "tiff";
  return "png";
}

async function ingestResourcesToInbox(resources) {
  const batchId = new Date().toISOString().replace(/[:.]/g, "-");
  const batchDir = join(inboxDir, batchId);
  mkdirSync(batchDir, { recursive: true });
  const capturedAt = new Date().toISOString();
  const ingested = [];
  const failed = [];

  for (const resource of resources) {
    const rawKind = String(resource?.kind || "text").trim().toLowerCase();
    const kind = rawKind === "link" || rawKind === "image" ? rawKind : "text";
    const value = String(resource?.value || "").trim();
    try {
      if (!value) {
        throw new Error("资源内容为空");
      }
      if (kind === "image") {
        const imageName = safeName(String(resource?.name || ""));
        const extension = imageExtension(resource);
        const stem = safeResourceStem(imageName.replace(/\.[^.]+$/, ""), "Pasted image");
        const destination = uniqueDestination(batchDir, `${stem}.${extension}`);
        writeFileSync(destination, Buffer.from(value, "base64"));
        ingested.push({
          originalSource: kind,
          inboxPath: destination,
          originalName: imageName || `Pasted image.${extension}`,
        });
      } else {
        const stem = safeResourceStem(value, kind === "link" ? "Link" : "Snippet");
        const destination = uniqueDestination(batchDir, `${stem}.${kind === "link" ? "url" : "snippet"}.md`);
        writeFileSync(destination, resourceMarkdown({ kind, value }, capturedAt), "utf8");
        ingested.push({
          originalSource: kind,
          inboxPath: destination,
          originalName: safeName(kind === "link" ? `Link: ${value}` : `Snippet: ${value.slice(0, 60)}`),
        });
      }
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
    status: existsSync(item.inboxPath) ? "still_in_inbox" : "moved_from_inbox",
  }));
  const record = {
    batchId: safeBatchId,
    startedAt,
    finishedAt,
    contentRoot: quietContentHome,
    inbox: inboxDir,
    index: indexDir,
    archive: archiveDir,
    items,
    failed,
  };
  const jsonPath = uniqueDestination(archiveDir, `${safeBatchId}.json`);
  writeFileSync(jsonPath, `${JSON.stringify(record, null, 2)}\n`, "utf8");

  const moved = items.filter((item) => item.status === "moved_from_inbox").length;
  const waiting = items.length - moved;
  const mdPath = uniqueDestination(archiveDir, `${safeBatchId}.md`);
  writeFileSync(mdPath, `# Quiet Batch ${safeBatchId}

- Started: ${startedAt}
- Finished: ${finishedAt}
- Content root: ${quietContentHome}
- Entered 00.01 Inbox: ${items.length}
- Moved from 00.01 Inbox: ${moved}
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
    throw new Error("找不到 @earendil-works/pi-coding-agent。请先运行 npm install，或重新打包 Quiet.app。");
  }
  return import(pathToFileURL(entry).href);
}

async function loadPiAi() {
  const entry = findPackageEntry("@earendil-works/pi-ai");
  if (!entry) {
    throw new Error("找不到 @earendil-works/pi-ai。请先运行 npm install，或重新打包 Quiet.app。");
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
    throw new Error("Refusing to delete a file outside the Quiet sessions directory.");
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
  const memoryText = existsSync(memoryPath) ? readFileSync(memoryPath, "utf8") : "";
  const methodIsUninitialized = memoryText.includes("Status: uninitialized");
  const rules = language === "zh"
    ? `硬性规则：
1. 只处理本次列出的 00.01 Inbox 资源：${inboxDir}
2. 请按 ~/.quiet/memory.md 的规则理解用户的偏好并整理。
3. 必须用 mv 移动，不要复制，不要删除用户文件或资源；成功后 00.01 Inbox 源路径不应继续存在，除非它仍处于未归档状态。
4. 整理后的文件只能放到 Quiet 根目录：${filesDir}
5. 如果 memory 仍是 \`Status: uninitialized\`，不要整理这些资源；把它们留在 00.01 Inbox，并先向用户介绍 PARA、Johnny.Decimal 和自定义三种选择，询问最终偏好。
6. 如果用户已经选定方法，只遵循 memory 中唯一的最终整理方法；不要把未选择的 PARA/JD 候选规则混入结果。
7. 如果最终方法是 Johnny.Decimal，Quiet 只预创建 area/category 骨架和系统级 00.00 JDex、00.01 Inbox、00.09 Archive；不要自动创建每个 category 下的 00/01/02/03/04/09 标准零位。
8. 如果最终方法是 Johnny.Decimal，优先创建或使用具体内容 ID，例如 \`15.52 Trip to NYC\`；只有用户明确想要某个 category 的 Inbox/Archive/Tasks/Templates/Links 时，才创建该 category 的标准零位。
9. Quiet 生成的批次归档记录放在 ${archiveDir}；原始用户资源不要放进系统管理区，除非它们仍在 00.01 Inbox 等待处理。
10. 不要新建摘要、索引、报告或说明文档；如需说明，只在对用户的最终回复里简短总结。
11. 按文件名、扩展名和必要内容判断用途；链接和 snippet 已保存为 Markdown 资源文件，不要只按扩展名机械分类。
12. ${copy.organizeDoneRule}`
    : `Hard rules:
1. Only process the 00.01 Inbox resources listed in this task: ${inboxDir}
2. Follow ~/.quiet/memory.md to understand the user's preferences and organize accordingly.
3. Move with mv; do not copy or delete user files or resources. After a successful move, the 00.01 Inbox source path should no longer exist unless it remains unfiled or needs confirmation.
4. Organized files must stay directly under the Quiet root: ${filesDir}
5. If memory still says \`Status: uninitialized\`, do not organize these resources; leave them in 00.01 Inbox and first ask the user to choose PARA, Johnny.Decimal, or a custom method.
6. If the user has selected a method, follow only the single final method in memory; do not mix in unselected PARA/JD candidate rules.
7. If the final method is Johnny.Decimal, Quiet pre-creates only the area/category skeleton and system-level 00.00 JDex, 00.01 Inbox, and 00.09 Archive; do not auto-create each category's 00/01/02/03/04/09 standard-zero folders.
8. If the final method is Johnny.Decimal, prefer a concrete content ID such as \`15.52 Trip to NYC\`; create category-level Inbox/Archive/Tasks/Templates/Links only when the user explicitly wants that bucket.
9. Quiet-created batch archive records go in ${archiveDir}. Do not put original user resources in system management unless they are still waiting in 00.01 Inbox.
10. Do not create summaries, indexes, reports, or notes as files. Summarize only in the final user-facing reply.
11. Understand purpose from filenames, extensions, and content when needed. Links and snippets are saved as Markdown resource files; do not classify mechanically by extension only.
12. ${copy.organizeDoneRule}`;
  const onboardingReminder = methodIsUninitialized
    ? language === "zh"
      ? "\n\n重要：memory 仍未初始化。请先询问用户偏好，不要整理本批资源。"
      : "\n\nImportant: memory is still uninitialized. Ask for the user's organizing preference first; do not organize this batch yet."
    : "";
  const pendingLabel = language === "zh" ? "待整理资源" : "Resources to organize";
  return `
${userText || copy.organizeFallback}

${copy.organizeInstruction}

${rules}${onboardingReminder}

Quiet dirs:
- content root: ${quietContentHome}
- 00.00 JDex: ${indexDir}
- 00.01 Inbox: ${inboxDir}
- 00.09 Archive: ${archiveDir}

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
    emit({ type: "status", value: `正在移入 00.01 Inbox：${paths.length + resources.length} 项` });
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
        message: `有 ${failed.length} 项未能进入 00.01 Inbox：${failed[0].reason}`,
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
      items: ingested.map((item) => `${item.originalName} -> ~/Documents/Quiet/<area>/<category>/<AC.ID>`),
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
  await session.prompt(text || `${copy.explainFallback} Quiet root=${filesDir}.`, {
    source: "interactive",
  });
}

emit({
  type: "ready",
  pid: process.pid,
  protocol: "quiet-pi-jsonl-v1",
  app: "quiet",
  filesRoot: filesDir,
  index: indexDir,
  inbox: inboxDir,
  archive: archiveDir,
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
