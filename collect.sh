#!/usr/bin/env bash
# collect.sh — sync changes FROM ~/.config/opencode/ back into this repo
#
# Use this when you've been iterating directly in ~/.config/opencode/ and want to
# checkpoint those changes back to the repo for versioning / sharing.
#
# Usage:
#   ./collect.sh           — copy live files into repo, print diff summary
#   ./collect.sh --dry-run — show what would change without writing

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OC_HOME="${HOME}/.config/opencode"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in --dry-run) DRY_RUN=true ;; esac
done

info() { printf "\033[36m  •\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m  ✓\033[0m %s\n" "$*"; }

collect_file() {
    local src="$1" dst="$2"
    if $DRY_RUN; then
        if [ -f "$src" ]; then
            diff -q "$src" "$dst" >/dev/null 2>&1 && info "unchanged: $(basename "$dst")" || info "would update: $(basename "$dst")"
        else
            info "source missing, skip: $src"
        fi
        return
    fi
    if [ ! -f "$src" ]; then
        info "source missing, skipped: $src"
        return
    fi
    if [ -f "$dst" ] && diff -q "$src" "$dst" >/dev/null 2>&1; then
        ok "unchanged: $(basename "$dst")"
    else
        cp -f "$src" "$dst"
        ok "collected: $(basename "$dst")"
    fi
}

echo ""
echo "OpenCode Orchestra — collect (live → repo)"
echo "  source: $OC_HOME"
echo "  repo:   $REPO"
$DRY_RUN && echo "  mode:   DRY RUN"
echo ""

echo "Agents:"
collect_file "$OC_HOME/agent/planner.md"        "$REPO/agents/planner.md"
collect_file "$OC_HOME/agent/actor.md"           "$REPO/agents/actor.md"
collect_file "$OC_HOME/agent/actor-heavy.md"    "$REPO/agents/actor-heavy.md"
collect_file "$OC_HOME/agent/reviewer.md"        "$REPO/agents/reviewer.md"

echo "Commands:"
collect_file "$OC_HOME/command/brain.md"         "$REPO/commands/brain.md"
collect_file "$OC_HOME/command/brain-abandon.md" "$REPO/commands/brain-abandon.md"
collect_file "$OC_HOME/command/duo-plan.md"     "$REPO/commands/duo-plan.md"
collect_file "$OC_HOME/command/duo-act.md"       "$REPO/commands/duo-act.md"
collect_file "$OC_HOME/command/duo-abandon.md"   "$REPO/commands/duo-abandon.md"

echo "Scripts:"
collect_file "$OC_HOME/scripts/orchestra-hook.sh" "$REPO/scripts/orchestra-hook.sh"
collect_file "$OC_HOME/scripts/ctx-segment.sh" "$REPO/scripts/ctx-segment.sh"
collect_file "$OC_HOME/scripts/sohoai-live-cost.sh" "$REPO/scripts/sohoai-live-cost.sh"

echo "Config:"
collect_file "$OC_HOME/orchestra/config.yaml"    "$REPO/config/config.yaml"
collect_file "$OC_HOME/orchestra/context-windows.yaml" "$REPO/config/context-windows.yaml"

echo ""
$DRY_RUN && echo "Dry run complete — no files written." || echo "Collect complete."
echo ""
if ! $DRY_RUN; then
    echo "  Next steps:"
    echo "    git diff           — review changes"
    echo "    git add -p         — stage selectively"
    echo "    git commit -m '...' — commit"
    echo "    git push           — publish"
fi
echo ""
