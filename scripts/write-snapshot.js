#!/usr/bin/env node
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const home = os.homedir();
const codexHome = path.join(home, ".codex");
const stateDb = path.join(codexHome, "sqlite", "state_5.sqlite");
const historyPath = path.join(codexHome, "history.jsonl");
const widgetDir = path.join(home, ".codex-widget");
const configPath = path.join(widgetDir, "config.json");
const snapshotPath = path.join(widgetDir, "codex-activity-snapshot.json");

const start = new Date();
start.setHours(0, 0, 0, 0);
const startSeconds = Math.floor(start.getTime() / 1000);

function sqlite(sql) {
  if (!fs.existsSync(stateDb)) return "";
  return execFileSync("sqlite3", [stateDb, sql], { encoding: "utf8" }).trim();
}

const statsRaw = sqlite(
  `SELECT COUNT(*), COALESCE(SUM(tokens_used),0), COALESCE(MAX(updated_at),0) FROM threads WHERE updated_at >= ${startSeconds};`
);
const [threadCount = "0", tokensUsed = "0", lastActive = "0"] = statsRaw.split("|");

const latestRaw = sqlite(
  `SELECT title, COALESCE(model,'') FROM threads WHERE updated_at >= ${startSeconds} ORDER BY updated_at DESC LIMIT 1;`
);
const [latestTitle = null, latestModel = null] = latestRaw ? latestRaw.split("|") : [];

let messageCount = 0;
const sessions = new Set();
if (fs.existsSync(historyPath)) {
  const lines = fs.readFileSync(historyPath, "utf8").split(/\n/);
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const item = JSON.parse(line);
      if ((item.ts || 0) * 1000 >= start.getTime()) {
        messageCount += 1;
        if (item.session_id) sessions.add(item.session_id);
      }
    } catch {}
  }
}

let config = {};
if (fs.existsSync(configPath)) {
  try {
    config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch {}
}

const snapshot = {
  generatedAt: new Date().toISOString(),
  todayThreadCount: Number(threadCount),
  todayMessageCount: messageCount,
  activeSessionCount: sessions.size,
  todayTokensUsed: Number(tokensUsed),
  lastActiveAt: Number(lastActive) > 0 ? new Date(Number(lastActive) * 1000).toISOString() : null,
  latestTitle,
  latestModel,
  rateLimitLabel: config.rateLimitLabel || latestModel || "Codex",
  rateLimitUsed: config.rateLimitUsed ?? Number(tokensUsed),
  rateLimitLimit: config.rateLimitLimit ?? null,
  rateLimitResetAt: config.rateLimitResetAt ?? null
};

fs.mkdirSync(widgetDir, { recursive: true });
fs.writeFileSync(snapshotPath, JSON.stringify(snapshot, null, 2));
console.log(snapshotPath);

