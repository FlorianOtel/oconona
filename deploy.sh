#!/usr/bin/env bash
# deploy.sh — install or update OpenCode Orchestra into ~/.config/opencode/
#
# Usage:
#   ./deploy.sh             — deploy to ~/.config/opencode/ (system-wide, all machines via NFS)
#   ./deploy.sh --dry-run   — preview what would change without writing anything
#   ./deploy.sh --diff      — show unified diff of every file that would change
#
# Idempotent: safe to re-run after any change in the repo.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OC_HOME="${HOME}/.config/opencode"
DRY_RUN=false
SHOW_DIFF=false
NO_RESTART=false

# v2 user unit name for the OpenCode server. Single source of truth for §11/§12.
OC_SERVICE="opencode-v2-server.service"
# Platform. Linux runs the server as a systemd user unit; macOS runs the
# OpenCode desktop app, which has no systemd unit (restart it by hand).
OS_NAME="$(uname -s)"

info()  { printf "\033[36m  •\033[0m %s\n" "$*"; }
ok()    { printf "\033[32m  ✓\033[0m %s\n" "$*"; }
warn()  { printf "\033[33m  !\033[0m %s\n" "$*"; }
die()   { printf "\033[31m  ✗\033[0m %s\n" "$*"; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN=true    ;;
        --diff)       SHOW_DIFF=true  ;;
        --no-restart) NO_RESTART=true ;;
        *) die "Unknown argument: $arg. Usage: ./deploy.sh [--dry-run] [--diff] [--no-restart]" ;;
    esac
done

# ── 0. Tier-config audit ─────────────────────────────────────────────────────
# Hard-fail blocks deploy on agent/model-rates/context-windows drift.
# Soft-warn lines are advisory only; deploy continues.
echo "Tier audit:"
# Python venv location differs per platform: Linux keeps it under ~/Gin-AI,
# macOS under ~/.python-3.12. Keep this block identical across all files that use it.
case "$(uname -s)" in
    Darwin) PYVENV="$HOME/.python-3.12" ;;
    *)      PYVENV="$HOME/Gin-AI/.Gin-AI-python-3.12" ;;
esac
PYTHON_BIN="$PYVENV/bin/python"
if $DRY_RUN; then
    info "would run: $PYTHON_BIN scripts/check-tiers.py --repo-root $REPO"
else
    "$PYTHON_BIN" "$REPO/scripts/check-tiers.py" --repo-root "$REPO" \
        || die "Tier audit failed — fix drift before deploying"
fi

# ── 0b. Agent frontmatter YAML lint ────────────────────────────────────────────
echo ""
echo "Agent YAML frontmatter:"
for f in "$REPO"/agents/*.md; do
    "$PYTHON_BIN" -c "
import yaml, sys
text = open(sys.argv[1]).read()
parts = text.split('---', 2)
if len(parts) < 3:
    sys.exit('no frontmatter found')
fm = yaml.safe_load(parts[1])
missing = [k for k in ('description','model','mode','permissions') if fm is None or fm.get(k) is None]
if missing:
    sys.exit('null fields: ' + ', '.join(missing))
if fm.get('mode') != 'subagent':
    sys.exit('mode must be subagent (got ' + repr(fm.get('mode')) + ')')
" "$f" || { rc=$?; die "Agent YAML lint failed for $(basename "$f") (exit $rc)"; }
    if $DRY_RUN; then
        info "valid: $(basename "$f")"
    else
        ok "valid: $(basename "$f")"
    fi
done

copy_file() {
    local src="$1" dst="$2"
    if $SHOW_DIFF && [ -f "$dst" ]; then
        diff -u "$dst" "$src" && true
        return
    fi
    if $DRY_RUN; then
        if [ -f "$dst" ]; then
            diff -q "$src" "$dst" >/dev/null 2>&1 && info "unchanged: $dst" || info "would update: $dst"
        else
            info "would create: $dst"
        fi
        return
    fi
    if [ -f "$dst" ] && diff -q "$src" "$dst" >/dev/null 2>&1; then
        ok "unchanged: $(basename "$dst")"
    else
        cp -f "$src" "$dst"
        ok "deployed: $(basename "$dst")"
    fi
}

echo ""
echo "OpenCode Orchestra — deploy"
echo "  repo:   $REPO"
echo "  target: $OC_HOME"
$DRY_RUN  && echo "  mode:   DRY RUN (no writes)"
$SHOW_DIFF && echo "  mode:   DIFF (no writes)"
echo ""

# ── 1. Prerequisite checks ────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || die "jq is required (sudo apt install jq)"
[ -d "$OC_HOME" ] || die "~/.config/opencode does not exist — is OpenCode installed?"

# ── 2. Create target directories ─────────────────────────────────────────────
for dir in agents commands scripts orchestra plugins; do
    $DRY_RUN || mkdir -p "$OC_HOME/$dir"
done
$DRY_RUN || mkdir -p "$OC_HOME/orchestra/logs"

# ── 3. Subagent definitions ───────────────────────────────────────────────────
echo "Agents:"
for f in "$REPO"/agents/*.md; do
    copy_file "$f" "$OC_HOME/agents/$(basename "$f")"
done
# Structural invariant: variant bodies must not drift from their base.
# Frontmatter and Role preamble differ by design; everything from
# "You are the **<Tier>**" onward must be byte-identical.
if ! $DRY_RUN && ! $SHOW_DIFF; then
    for pair in "actor:actor-heavy" "researcher:researcher-deep"; do
        base="${pair%:*}"; var="${pair#*:}"
        diff <(awk '/^You are the/,0' "$REPO/agents/$base.md") \
             <(awk '/^You are the/,0' "$REPO/agents/$var.md") \
          > /dev/null 2>&1 \
          || die "agent variant drift: $var.md body diverges from $base.md — mirror changes before deploying"
    done
fi

# ── 4. Slash commands ─────────────────────────────────────────────────────────
echo "Commands:"
for f in "$REPO"/commands/*.md; do
    copy_file "$f" "$OC_HOME/commands/$(basename "$f")"
done

# ── 5. Hook scripts + telemetry tools ────────────────────────────────────────
# Convention: shell wrappers (.sh) are +x and invoke the Python implementation
# via the venv; Python files (.py) are NOT +x — they're called through the wrapper.
#   telemetry-summarize.sh    — telemetry.json writer wrapper (calls .py)
#   telemetry-report.sh       — orchestra session cost report (shell-only)
#   session-report.sh         — orchestra session unified report wrapper (calls .py)
#   native-session-report.sh  — non-orchestra OC session report wrapper (calls .py)
#   smoke-test.sh             — 4-check end-of-/brain validation (shell-only)
#   ctx-segment.sh            — status-line context-window bar renderer
#   orchestra-cleanup.sh      — end-of-session cleanup: .outcome + snapshot + inflight removal + telemetry
echo "Scripts:"
for s in \
    telemetry-summarize.sh telemetry-report.sh \
    session-report.sh native-session-report.sh smoke-test.sh \
    ctx-segment.sh orchestra-cleanup.sh; do
    if [ -f "$REPO/scripts/$s" ]; then
        copy_file "$REPO/scripts/$s" "$OC_HOME/scripts/$s"
        $DRY_RUN || chmod +x "$OC_HOME/scripts/$s"
    fi
done
# Python implementations — no chmod (always called through the .sh wrapper or
# via importlib from another Python module).
for p in telemetry-summarize.py session-report.py native-session-report.py oc-db.py verify-cost-rates.py check-tiers.py oc-snapshot.py; do
    if [ -f "$REPO/scripts/$p" ]; then
        copy_file "$REPO/scripts/$p" "$OC_HOME/scripts/$p"
    fi
done

# Data files (YAML, JSON, etc.) — deployed to scripts/ alongside the tools that use them.
for d in model-rates.yaml; do
    if [ -f "$REPO/scripts/$d" ]; then
        copy_file "$REPO/scripts/$d" "$OC_HOME/scripts/$d"
    fi
done

# Plugins — OpenCode server-side plugin modules (JS) deployed to $OC_HOME/plugins/.
# The glob is guarded: if no plugins/*.js exists in the repo the literal pattern
# would otherwise be passed to copy_file, so skip non-files explicitly.
echo "Plugins:"
for f in "$REPO"/plugins/*.js; do
    [ -f "$f" ] || continue
    copy_file "$f" "$OC_HOME/plugins/$(basename "$f")"
done

# Clean up artifacts deleted in the headless→subagents revert (idempotent).
# Per-category orphan removal — only delete specific known-deleted files,
# not "anything not in repo" (operator may have personal commands/agents).
if ! $DRY_RUN; then
    # 7a. Headless scripts (Step 7 of the revert plan).
    for orphan in run-tier.sh format-stream.sh runs-registry.sh start-research.sh; do
        if [ -f "$OC_HOME/scripts/$orphan" ]; then
            rm -f "$OC_HOME/scripts/$orphan"
            ok "cleaned orphan: $OC_HOME/scripts/$orphan"
        fi
    done

    # 7b. Stripped agent variants (consumed by run-tier.sh; gone with it).
    if [ -d "$OC_HOME/agent/.stripped" ]; then
        rm -rf "$OC_HOME/agent/.stripped"
        ok "cleaned orphan: $OC_HOME/agent/.stripped/"
    fi

    # 7b-ii. Planner-long agent variant (removed in non-Anthropic pipeline transition).
    if [ -f "$OC_HOME/agent/planner-long.md" ]; then
        echo "  Removing orphaned planner-long.md"
        rm "$OC_HOME/agent/planner-long.md"
        ok "cleaned orphan: $OC_HOME/agent/planner-long.md"
    fi

    # 7c. Obsolete commands (Step 6 of the revert plan, plus the duo session-bracketing redesign).
    # duo.md was replaced by duo-start.md / duo-end.md / duo-abandon.md (2026-05-05).
    # duo-stop.md was renamed to duo-end.md (2026-05-05).
    # duo-start.md was renamed to duo-plan.md, duo-end.md to duo-act.md (2026-05-06).
    # brain-abandon.md was previously deferred but is now shipped as the explicit
    # /brain cancel command (paired with the new .brain-inflight marker).
    for orphan in explore.md brain-resume.md brain-status.md orchestra-mode.md duo.md duo-stop.md duo-start.md duo-end.md; do
        if [ -f "$OC_HOME/command/$orphan" ]; then
            rm -f "$OC_HOME/command/$orphan"
            ok "cleaned orphan: $OC_HOME/command/$orphan"
        fi
    done

    # 7e. v7.3 dead scripts + config.
    # NB: native-session-report.{sh,py} were deleted in v7.3 but RESTORED in
    # hotfix #7 (commit 7fabdaa) as OC-SQLite-sourced replacements. Do NOT
    # add them to this orphan list — doing so deletes them on every deploy
    # immediately after the Scripts: loop has just copied them.
    # orchestra-hook.sh (v8.7.0): the settings.json hook mechanism it served was
    # dead code (OpenCode never reads settings.json hooks), so the script is removed.
    # Listed here so a stale copy from before this release is deleted on re-deploy.
    for orphan in bash-session-init.sh native-session-finalize.py \
                  native-subagent-cost.sh sohoai-live-cost.sh \
                  otel-headers-helper.sh orchestra-hook.sh; do
        if [ -f "$OC_HOME/scripts/$orphan" ]; then
            rm -f "$OC_HOME/scripts/$orphan"
            ok "cleaned orphan: $OC_HOME/scripts/$orphan"
        fi
    done
    if [ -f "$OC_HOME/orchestra/pricing.yaml" ]; then
        rm -f "$OC_HOME/orchestra/pricing.yaml"
        ok "cleaned orphan: $OC_HOME/orchestra/pricing.yaml"
    fi
fi

# ── 6. Orchestra config ───────────────────────────────────────────────────────
echo "Config:"
copy_file "$REPO/config/oconona-config.yaml" "$OC_HOME/orchestra/oconona-config.yaml"
copy_file "$REPO/config/context-windows.yaml" "$OC_HOME/orchestra/context-windows.yaml"

# ── 7. Strip dead orchestra hooks from settings.json ─────────────────────────
# History: earlier deploys merged config/settings-hooks.json into settings.json.
# OpenCode never reads settings.json hooks (v1 or v2), so those entries were dead
# code, and the fragment file was removed in v8.7.0. This step removes ONLY the
# entries whose command contains "orchestra-hook.sh" (left by earlier deploys).
# Every other key in settings.json is left untouched. Idempotent: a second run
# finds no orchestra entries and changes nothing.
#
# Filter (jq): drop hook objects whose .command contains "orchestra-hook.sh";
# drop matcher-groups emptied by that removal; drop event keys emptied by that
# removal; drop .hooks only if it ends up empty after a real removal.
ORCH_STRIP_FILTER='
def is_orch: ((.command // "") | type == "string" and contains("orchestra-hook.sh"));
def group_has_orch: ((.hooks // []) | any(is_orch));
def strip_group:
    if group_has_orch
    then (.hooks |= map(select(is_orch | not))
          | if (.hooks | length) == 0 then empty else . end)
    else . end;
if (((.hooks // {}) | [.. | objects | .command? | strings | select(contains("orchestra-hook.sh"))] | length) == 0)
then .
else
    .hooks |= with_entries(
        if (.value | map(group_has_orch) | any)
        then (.value |= map(strip_group)) | select(.value | length > 0)
        else . end
    )
    | if (.hooks | length) == 0 then del(.hooks) else . end
end
'

echo "Settings:"
SETTINGS="$OC_HOME/settings.json"
if [ ! -f "$SETTINGS" ]; then
    info "settings.json absent; nothing to strip"
else
    # Count orchestra-origin command strings first. Also fails loudly on invalid JSON.
    ORCH_COUNT="$(jq -r '((.hooks // {}) | [.. | objects | .command? | strings | select(contains("orchestra-hook.sh"))] | length)' "$SETTINGS")" \
        || die "settings.json is not valid JSON: $SETTINGS"
    if [ "$ORCH_COUNT" = "0" ]; then
        ok "unchanged: settings.json (no orchestra-hook.sh entries)"
    elif $DRY_RUN; then
        info "would strip $ORCH_COUNT orchestra-hook.sh entr(y/ies) from settings.json"
    else
        TMPFILE="$SETTINGS.orchestra-deploy.tmp"
        if ! jq "$ORCH_STRIP_FILTER" "$SETTINGS" > "$TMPFILE"; then
            rm -f "$TMPFILE"
            die "failed to strip orchestra hooks from settings.json (file left unchanged)"
        fi
        mv -f "$TMPFILE" "$SETTINGS"
        ok "stripped: $ORCH_COUNT orchestra-hook.sh entr(y/ies) from settings.json"
    fi
fi

# ── 8. Patch status-line.sh ───────────────────────────────────────────────────
echo "Status line:"
STATUS_LINE="$OC_HOME/scripts/status-line.sh"
if [ ! -f "$STATUS_LINE" ]; then
    info "status-line.sh not present — skipping patch (orchestra block not needed)"
else
    # Idempotent re-deploy: if the block is already present, compare to the source.
    # If different, strip the old block and re-append. (Old logic was append-once-only,
    # which left the deployed block stale after orchestra-block.sh source updates.)
    BLOCK_PRESENT=false
    grep -q "ORCHESTRA_BLOCK_START" "$STATUS_LINE" 2>/dev/null && BLOCK_PRESENT=true

    if $BLOCK_PRESENT; then
        # Extract deployed block (from ORCHESTRA_BLOCK_START to just before "# Output the status line")
        DEPLOYED_BLOCK="$(awk '/^# ORCHESTRA_BLOCK_START/,/^# Output the status line/' "$STATUS_LINE" | sed '$d')"
        SOURCE_BLOCK="$(sed '/^#!/d; /^# orchestra-block.sh/d; /^# USAGE/d; /^# just before the final/d; /^#$/d; /^# Prerequisites/d; /^#   -/d; /^# deploy.sh will/d; /^# The presence/d' "$REPO/status-line/orchestra-block.sh")"
        if [ "$DEPLOYED_BLOCK" = "$SOURCE_BLOCK" ]; then
            ok "unchanged: status-line.sh (orchestra block already present, matches source)"
        elif $DRY_RUN; then
            info "would re-deploy orchestra block (source has changed)"
        else
            # Strip old block (from ORCHESTRA_BLOCK_START up to but not including "# Output the status line")
            TMPFILE="$STATUS_LINE.orchestra-deploy.tmp"
            awk '
                /^# ORCHESTRA_BLOCK_START/ { in_block=1; next }
                in_block && /^# Output the status line/ { in_block=0 }
                !in_block && /ORCHESTRA_BLOCK_START/ { next }
                !in_block && /inline just before the final/ { next }
                !in_block { print }
            ' "$STATUS_LINE" > "$TMPFILE.stripped"
            # Now append fresh block via the same awk-insert logic
            sed '/^#!/d; /^# orchestra-block.sh/d; /^# USAGE/d; /^# just before the final/d; /^#$/d; /^# Prerequisites/d; /^#   -/d; /^# deploy.sh will/d; /^# The presence/d' "$REPO/status-line/orchestra-block.sh" > "$TMPFILE.block"
            awk -v bfile="$TMPFILE.block" '
                /^# Output the status line/ { while ((getline line < bfile) > 0) print line; print ""; }
                { print }
            ' "$TMPFILE.stripped" > "$TMPFILE"
            rm -f "$TMPFILE.stripped" "$TMPFILE.block"
            mv -f "$TMPFILE" "$STATUS_LINE"
            chmod +x "$STATUS_LINE"
            ok "updated: status-line.sh (orchestra block refreshed)"
        fi
    else
        if $DRY_RUN; then
            info "would append orchestra block to status-line.sh"
        else
            BLOCK="$REPO/status-line/orchestra-block.sh"
            TMPFILE="$STATUS_LINE.orchestra-deploy.tmp"
            sed '/^#!/d; /^# orchestra-block.sh/d; /^# USAGE/d; /^# just before the final/d; /^#$/d; /^# Prerequisites/d; /^#   -/d; /^# deploy.sh will/d; /^# The presence/d' "$BLOCK" > "$TMPFILE.block"
            awk -v bfile="$TMPFILE.block" '
                /^# Output the status line/ { while ((getline line < bfile) > 0) print line; print ""; }
                { print }
            ' "$STATUS_LINE" > "$TMPFILE"
            rm -f "$TMPFILE.block"
            mv -f "$TMPFILE" "$STATUS_LINE"
            chmod +x "$STATUS_LINE"
            ok "patched: status-line.sh (orchestra block appended)"
        fi
    fi
fi

# ── 9. Inject orchestra-guard block into ~/.config/opencode/AGENTS.md ──────────────────
# The guard fires every turn (AGENTS.md is loaded into the system prompt prefix
# by the harness on every turn), giving us per-turn reinforcement of the
# orchestra-pipeline rules — matching OC's per-turn context reload cadence. Without
# this, /brain reliably skips Planner/Actor dispatches in long Phase 0 sessions
# because /brain.md's instructions get buried by repeated context reload reminders.
# Skip-with-warning if the user's global AGENTS.md is absent.
echo "AGENTS.md guard:"
GLOBAL_AGENTS_MD="$HOME/.config/opencode/AGENTS.md"
GUARD_SOURCE="$REPO/agents-md-block/orchestra-guard.md"
if [ ! -f "$GLOBAL_AGENTS_MD" ]; then
    if $DRY_RUN; then
        info "would create: $GLOBAL_AGENTS_MD (empty, for orchestra-guard injection)"
    else
        touch "$GLOBAL_AGENTS_MD"
        ok "created: $GLOBAL_AGENTS_MD"
    fi
fi
if [ ! -f "$GUARD_SOURCE" ]; then
    warn "agents-md-block/orchestra-guard.md not found in repo — skipping injection"
else
    GUARD_PRESENT=false
    grep -q "ORCHESTRA_GUARD_START" "$GLOBAL_AGENTS_MD" 2>/dev/null && GUARD_PRESENT=true

    if $GUARD_PRESENT; then
        # Extract deployed block (between markers, exclusive of the markers themselves)
        DEPLOYED_GUARD="$(awk '/^<!-- ORCHESTRA_GUARD_START -->/{flag=1;next} /^<!-- ORCHESTRA_GUARD_END -->/{flag=0} flag' "$GLOBAL_AGENTS_MD")"
        SOURCE_GUARD="$(cat "$GUARD_SOURCE")"
        if [ "$DEPLOYED_GUARD" = "$SOURCE_GUARD" ]; then
            ok "unchanged: ~/.config/opencode/AGENTS.md (orchestra-guard block matches source)"
        elif $DRY_RUN; then
            info "would re-deploy orchestra-guard block in ~/.config/opencode/AGENTS.md (source has changed)"
        else
            TMPFILE="$GLOBAL_AGENTS_MD.orchestra-deploy.tmp"
            # Strip old block (markers and content)
            awk '
                /^<!-- ORCHESTRA_GUARD_START -->/ { in_block=1; next }
                /^<!-- ORCHESTRA_GUARD_END -->/ { in_block=0; next }
                !in_block { print }
            ' "$GLOBAL_AGENTS_MD" > "$TMPFILE"
            # Append fresh block at end
            {
                printf '\n<!-- ORCHESTRA_GUARD_START -->\n'
                cat "$GUARD_SOURCE"
                printf '<!-- ORCHESTRA_GUARD_END -->\n'
            } >> "$TMPFILE"
            mv -f "$TMPFILE" "$GLOBAL_AGENTS_MD"
            ok "updated: ~/.config/opencode/AGENTS.md (orchestra-guard block refreshed)"
        fi
    else
        if $DRY_RUN; then
            info "would append orchestra-guard block to ~/.config/opencode/AGENTS.md"
        else
            {
                printf '\n<!-- ORCHESTRA_GUARD_START -->\n'
                cat "$GUARD_SOURCE"
                printf '<!-- ORCHESTRA_GUARD_END -->\n'
            } >> "$GLOBAL_AGENTS_MD"
            ok "patched: ~/.config/opencode/AGENTS.md (orchestra-guard block appended)"
        fi
    fi
fi

# ── 10. Global gitignore ─────────────────────────────────────────────────────
# (removed v7.5beta) Sessions are now GLOBAL (~/.config/opencode/orchestra/);
# project-local .opencode/orchestra/ is no longer auto-created, so the
# .opencode/orchestra/ gitignore entry is dead. No action needed.

# ── 11. Restart the OC server ─────────────────────────────────────────────────
# OC reads its config (agents/, commands/, AGENTS.md, opencode.json) once at
# startup and never reloads. Without a restart, deployed changes have no effect
# until the next time the operator manually restarts. Run unconditionally
# (override with --no-restart for the rare case of file-only deploys).
echo "OC server:"
if $DRY_RUN; then
    info "would restart: systemctl --user restart $OC_SERVICE"
elif $NO_RESTART; then
    warn "skipping restart (--no-restart) — deployed changes will NOT take effect until:"
    warn "    systemctl --user restart $OC_SERVICE"
elif ! command -v systemctl >/dev/null 2>&1; then
    if [ "$OS_NAME" = "Darwin" ]; then
        # macOS has no systemd. The server is the OpenCode desktop app, which
        # must be restarted by hand; nothing here can do it for the operator.
        warn "macOS detected: there is no systemd unit to restart."
        warn "RESTART THE OPENCODE DESKTOP APP MANUALLY — deployed changes will NOT take effect until you do."
    else
        warn "systemctl not found; restart OC manually for deployed changes to take effect"
    fi
elif ! systemctl --user list-unit-files "$OC_SERVICE" >/dev/null 2>&1; then
    warn "$OC_SERVICE not installed; restart OC manually for deployed changes to take effect"
else
    if systemctl --user restart "$OC_SERVICE" 2>&1; then
        ok "restarted: $OC_SERVICE"
    else
        warn "restart failed — run manually: systemctl --user restart $OC_SERVICE"
    fi
fi

# ── 12. Post-restart agent verification ─────────────────────────────────────────
if $DRY_RUN; then
    info "would verify: authenticated GET /api/agent post-restart"
elif $NO_RESTART; then
    warn "skipping agent verification (--no-restart) — restart required before verification"
elif ! command -v systemctl >/dev/null 2>&1; then
    if [ "$OS_NAME" = "Darwin" ]; then
        # The desktop app does not record its port in service.json, so the live
        # check cannot be run reliably here. Skip loudly rather than guess a port.
        warn "skipping agent verification (macOS desktop app: live check not run) — restart the OpenCode desktop app, then verify the agents in it manually"
    else
        warn "skipping agent verification (systemctl not found) — verify manually"
    fi
elif ! systemctl --user list-unit-files "$OC_SERVICE" >/dev/null 2>&1; then
    warn "skipping agent verification ($OC_SERVICE not installed) — verify manually"
else
    # Credentials for the v2 server (HTTP Basic auth, user "opencode").
    # Read ONLY the two keys we need from the env file — never `source` it,
    # because it may hold other variables. Missing password => warn and skip.
    OC_ENV_FILE="$OC_HOME/opencode-server.env"
    OC_PASSWORD=""
    OC_PORT="4096"
    if [ -r "$OC_ENV_FILE" ]; then
        # Values may be wrapped in one pair of surrounding "..." or '...'; strip that pair.
        OC_PASSWORD="$(grep -m1 '^OPENCODE_SERVER_PASSWORD=' "$OC_ENV_FILE" | cut -d= -f2- | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" || true)"
        _port="$(grep -m1 '^OPENCODE_PORT=' "$OC_ENV_FILE" | cut -d= -f2- | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" || true)"
        if [ -n "$_port" ]; then
            OC_PORT="$_port"
        fi
    fi

    if [ -z "$OC_PASSWORD" ]; then
        warn "skipping agent verification (OPENCODE_SERVER_PASSWORD not found in $OC_ENV_FILE) — verify manually"
    else
        # The password goes into a curl config file (-K), NOT onto curl's argv,
        # so it never appears in `ps`. The file is 0600 and removed on exit.
        # Escape backslash and double quote for the curl config quoted-string syntax.
        _pw_escaped="${OC_PASSWORD//\\/\\\\}"
        _pw_escaped="${_pw_escaped//\"/\\\"}"
        OC_CURL_CFG="$(mktemp)"
        trap 'rm -f "$OC_CURL_CFG"' EXIT
        chmod 0600 "$OC_CURL_CFG"
        printf 'user = "opencode:%s"\n' "$_pw_escaped" > "$OC_CURL_CFG"

        # systemctl found and service installed; attempt verification.
        # Filter to user-defined agents (derived from agents/*.md) — OC built-ins
        # (build, compaction, summary, title, explore, general, plan) intentionally
        # have model=null and must not trigger a false warn.
        echo "Agent verification:"
        _EXPECTED_NAMES=""
        for _f in "$REPO"/agents/*.md; do
            _EXPECTED_NAMES="$_EXPECTED_NAMES $(basename "$_f" .md)"
        done
        _EXPECTED_NAMES="${_EXPECTED_NAMES# }"

        verified=false
        for attempt in {1..10}; do
            # /api/agent returns {location, data: [Agent.Info...]} (v2 protocol).
            if curl --max-time 2 -s -K "$OC_CURL_CFG" "http://localhost:${OC_PORT}/api/agent" 2>/dev/null \
                | "$PYTHON_BIN" -c "
import sys, json
expected = set(sys.argv[1].split())
payload = json.load(sys.stdin)
agents = payload.get('data') if isinstance(payload, dict) else None
if not isinstance(agents, list):
    sys.exit('unexpected /api/agent payload shape')
agents_by_name = {a.get('name'): a for a in agents}
missing = expected - set(agents_by_name)
if missing:
    sys.exit('user agents missing from /api/agent: ' + ', '.join(sorted(missing)))
problems = []
for name in expected:
    a = agents_by_name[name]
    # model is an {id, providerID, variant} dict (v2 shape) — check truthy, not isinstance str
    if not a.get('model'):
        problems.append(name + ': null model')
    desc = a.get('description')
    if not desc or not str(desc).strip():
        problems.append(name + ': null/empty description')
    if a.get('mode') != 'subagent':
        problems.append(name + ': mode=' + repr(a.get('mode')) + ' (expected subagent)')
if problems:
    sys.exit('; '.join(problems))
" "$_EXPECTED_NAMES" >/dev/null 2>&1; then
                ok "verified: all user agents report model, description and mode=subagent via /api/agent"
                verified=true
                break
            fi
            [ "$attempt" -lt 10 ] && sleep 1
        done
        rm -f "$OC_CURL_CFG"
        if [ "$verified" = "false" ]; then
            warn "agent verification failed after 10 retries — user agent may have null model, a missing description, or mode != subagent; check: curl -s -u opencode http://localhost:${OC_PORT}/api/agent | jq   (prompts for the password)"
        fi
    fi
fi

echo ""
$DRY_RUN && echo "Dry run complete — no files written." || echo "Deploy complete."
echo ""
echo "  Quick-start:"
echo "    1. Set octmux permission mode with Shift-TAB (ask / allow / deny)"
echo "    2. Type /brain <task>          — full pipeline (Planner → Actor → Reviewer)"
echo "       Type /brain-abandon         — cancel the active /brain session"
echo "    3. Type /duo-plan <task>      — open a /duo planning session (multi-turn refinement)"
echo "       Type /duo-act               — commit the plan and execute Actor"
echo "       Type /duo-abandon           — cancel the active /duo session"
echo "    4. See docs/design.md for full reference"
echo ""
