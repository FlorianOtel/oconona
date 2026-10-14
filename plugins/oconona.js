// oconona.js — OpenCode v2 plugin that publishes orchestra session state onto the
// harness (top-level) OpenCode session, as `metadata.orchestra`, so the OC client can
// show a badge for an active /brain or /duo run.
//
// Contract (ACKed; see the session dir RESEARCH.md "Orchestra v2 contract"):
//   metadata.orchestra = {
//     version: 1,
//     mode: "brain" | "duo",
//     title: string,                       // badge text, truncated to 48 characters
//     active: boolean,
//     updatedAt: number,                   // epoch milliseconds
//     parserWarnings?: [{code, message}],  // from telemetry.json parser_warnings
//     outcome?: "pass" | "fix-loop" | "block" | "abandoned"
//   }
//
// How it finds the run: every orchestra session dir lives under
// ~/.config/opencode/orchestra/sessions/<dir>/. The dir whose .oc-session-id sidecar
// equals the harness session id is the one this plugin reads.
//
// Hard rules (this code runs inside the OpenCode server process, on every shell call):
//   - never throw out of the hook; every failure is logged and swallowed
//   - only bounded, read-mostly filesystem work
//   - only ever write to the session whose id matched a .oc-session-id sidecar
//   - no secrets in logs
//
// Only node: builtins are imported; the plugin needs no npm packages.

import { readFile, readdir, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

// Version of the metadata.orchestra contract written by this plugin.
const CONTRACT_VERSION = 1;

// Badge text limit from the contract.
const TITLE_MAX_CHARS = 48;

// While a run is active, refresh updatedAt at most once an hour.
const REFRESH_INTERVAL_MS = 60 * 60 * 1000;

// Values the cleanup script may write to .outcome. Anything else is ignored.
const OUTCOMES = new Set(["pass", "fix-loop", "block", "abandoned"]);

// Inflight marker files, checked in order. Each marker's file content is the run title.
const MODE_MARKERS = [
  [".brain-inflight", "brain"],
  [".duo-inflight", "duo"],
];

// Read a small text file. Returns undefined when it is missing or unreadable.
async function readText(file) {
  try {
    return await readFile(file, "utf8");
  } catch {
    return undefined;
  }
}

// Truncate to TITLE_MAX_CHARS characters (not UTF-16 code units, so emoji are not split).
function truncateTitle(text) {
  return Array.from(text).slice(0, TITLE_MAX_CHARS).join("");
}

// Find the most recently modified orchestra dir whose .oc-session-id matches sessionID.
// Returns the dir path, or undefined when nothing matches (the plugin is then inert).
async function findSessionDir(sessionsRoot, sessionID) {
  let names;
  try {
    names = await readdir(sessionsRoot);
  } catch {
    // No orchestra sessions directory on this host: nothing to publish.
    return undefined;
  }

  let best;
  for (const name of names) {
    const dir = path.join(sessionsRoot, name);
    const sidecar = await readText(path.join(dir, ".oc-session-id"));
    // The sidecar is trimmed before comparing; an empty sidecar never matches.
    if (!sidecar || sidecar.trim() !== sessionID) continue;

    const info = await stat(dir).catch(() => undefined);
    if (!info || !info.isDirectory()) continue;
    if (!best || info.mtimeMs > best.mtimeMs) best = { dir, mtimeMs: info.mtimeMs };
  }
  return best?.dir;
}

// Read telemetry.json parser_warnings, keeping only well-formed {code, message} string pairs.
// Returns undefined when telemetry.json is absent or unparseable, so the key is omitted.
async function readParserWarnings(dir) {
  const text = await readText(path.join(dir, "telemetry.json"));
  if (text === undefined) return undefined;

  let telemetry;
  try {
    telemetry = JSON.parse(text);
  } catch {
    return undefined;
  }

  const warnings = Array.isArray(telemetry?.parser_warnings) ? telemetry.parser_warnings : [];
  return warnings
    .filter((w) => w && typeof w.code === "string" && typeof w.message === "string")
    .map((w) => ({ code: w.code, message: w.message }));
}

// Derive the published state for one run from its sidecar files.
//   last: the state published earlier for this harness session (undefined if none).
// Returns undefined when there is nothing to say: no marker now and no earlier publish.
async function deriveState(dir, last) {
  // An inflight marker means the run is active; its content is the title.
  let mode;
  let title;
  for (const [marker, markerMode] of MODE_MARKERS) {
    const text = await readText(path.join(dir, marker));
    if (text !== undefined) {
      mode = markerMode;
      title = truncateTitle(text.trim());
      break;
    }
  }

  const active = mode !== undefined;
  if (!active) {
    // Marker gone: the run has ended. Keep the mode and title we last published.
    if (!last) return undefined;
    mode = last.mode;
    title = last.title;
  }

  const state = { mode, title, active };

  // A finished run carries its outcome in .outcome.
  if (!active) {
    const outcome = (await readText(path.join(dir, ".outcome")))?.trim();
    if (OUTCOMES.has(outcome)) state.outcome = outcome;
  }

  // telemetry.json is written by the summariser at the end of a run.
  const parserWarnings = await readParserWarnings(dir);
  if (parserWarnings !== undefined) state.parserWarnings = parserWarnings;

  return state;
}

// Write metadata.orchestra onto the harness session.
// Read-modify-write: other metadata keys on the session are preserved.
async function publish(ctx, sessionID, state, now) {
  const session = await ctx.session.get({ sessionID });
  const existing = session?.metadata;
  const metadata =
    existing && typeof existing === "object" && !Array.isArray(existing) ? { ...existing } : {};

  metadata.orchestra = { version: CONTRACT_VERSION, ...state, updatedAt: now };
  await ctx.session.update({ sessionID, metadata });
}

// Turn an unknown thrown value into a short message for the log.
function errorText(err) {
  return err instanceof Error ? err.message : String(err);
}

export default {
  id: "oconona",

  async setup(ctx) {
    // Last state published per harness session id. Kept in memory only, so a server
    // restart forgets it; a finished run is then not re-published until a marker appears again.
    const published = new Map();

    const sessionsRoot = path.join(os.homedir(), ".config", "opencode", "orchestra", "sessions");

    await ctx.tool.hook("execute.after", async (event) => {
      try {
        // Only completed shell calls can carry a run's state change; ignore everything else.
        if (event.tool !== "shell" || event.status !== "completed") return;

        const sessionID = event.sessionID;
        const dir = await findSessionDir(sessionsRoot, sessionID);
        if (!dir) return;

        const last = published.get(sessionID);
        const state = await deriveState(dir, last?.state);
        if (!state) return;

        // Publish when the state changed, or when an active run's updatedAt is due a refresh.
        const now = Date.now();
        const key = JSON.stringify(state);
        const refreshDue = state.active && last !== undefined && now - last.publishedAt > REFRESH_INTERVAL_MS;
        if (last !== undefined && last.key === key && !refreshDue) return;

        await publish(ctx, sessionID, state, now);
        published.set(sessionID, { state, key, publishedAt: now });
      } catch (err) {
        // Never let the hook throw into the server; log a short message and move on.
        console.error("[oconona plugin] orchestra metadata publish failed:", errorText(err));
      }
    });
  },
};
