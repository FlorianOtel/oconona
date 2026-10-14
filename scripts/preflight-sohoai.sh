#!/usr/bin/env bash
# Preflight: can the opencode runtime (Bun) actually reach the SoHoAI proxy?
#
# Why not curl: /usr/bin/curl is Apple-signed and exempt from macOS Local Network
# privacy, so it returns 200 even when opencode's own Bun fetch is blocked with
# EHOSTUNREACH (reported by opencode as "FailedToOpenSocket: Was there a typo in
# the url or port?"). The privacy grant follows the *responsible process*, so a
# server launched over ssh or from inside tmux has no grant. This probe uses Bun
# in the caller's context to mirror what the server would see.
#
# Usage: scripts/preflight-sohoai.sh [baseURL]
#   baseURL defaults to provider.sohoai.options.baseURL in ~/.config/opencode/opencode.json
# Exit: 0 reachable | 1 unreachable (advisory — callers must not hard-block) | 2 cannot probe

set -uo pipefail

CFG="${HOME}/.config/opencode/opencode.json"
BUN="$(command -v bun || true)"
[ -z "$BUN" ] && [ -x "${HOME}/.bun/bin/bun" ] && BUN="${HOME}/.bun/bin/bun"
if [ -z "$BUN" ]; then
    echo "preflight-sohoai: bun not found — cannot probe (skipping)" >&2
    exit 2
fi

BASE_URL="${1:-}"
if [ -z "$BASE_URL" ]; then
    # opencode.json is JSONC (// comments); strip them inside Bun before parsing.
    BASE_URL="$("$BUN" -e '
      const t = require("fs").readFileSync(process.argv[1], "utf8").replace(/^\s*\/\/.*$/gm, "");
      try { console.log(JSON.parse(t).provider?.sohoai?.options?.baseURL ?? ""); } catch { console.log(""); }
    ' "$CFG" 2>/dev/null)"
fi
if [ -z "$BASE_URL" ]; then
    echo "preflight-sohoai: no sohoai baseURL in ${CFG} (skipping)" >&2
    exit 2
fi

"$BUN" -e '
  const url = process.argv[1].replace(/\/$/, "") + "/models";
  const t0 = Date.now();
  try {
    const r = await fetch(url, { headers: { Authorization: "Bearer sohoai-local" }, signal: AbortSignal.timeout(5000) });
    console.log(`preflight-sohoai: OK ${r.status} ${url} (${Date.now() - t0}ms)`);
    process.exit(r.ok ? 0 : 1);
  } catch (e) {
    const code = e.code ?? e.name;
    console.error(`preflight-sohoai: FAIL ${code} ${url} (${Date.now() - t0}ms)`);
    if (code === "EHOSTUNREACH" || code === "ConnectionRefused" || code === "FailedToOpenSocket") {
      console.error("  Instant failure while curl works => macOS Local Network privacy for this launch context.");
      console.error("  Check: the opencode server must NOT be started over ssh or from inside tmux;");
      console.error("  launch it from iTerm2 / OpenCode.app, or route via a loopback relay (see docs/design.md).");
    }
    process.exit(1);
  }
' "$BASE_URL"
