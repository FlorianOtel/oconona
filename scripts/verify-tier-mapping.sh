#!/usr/bin/env bash
# verify-tier-mapping.sh — verify tier-to-model mapping against agents/*.md
# Outputs a 4-line table: <tier>\t<model> for each tier

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer repo-relative (running from repo's scripts/ dir)
AGENTS_DIR="${SCRIPT_DIR}/../agents"
# Fall back to deployed (running from ~/.config/opencode/scripts/)
if [[ ! -d "$AGENTS_DIR" ]]; then
    AGENTS_DIR="${HOME}/.config/opencode/agents"
fi
if [[ ! -d "$AGENTS_DIR" ]]; then
    echo "ERROR: agents dir not found (tried ${SCRIPT_DIR}/../agents and ${HOME}/.config/opencode/agents)" >&2
    exit 1
fi

# Parse model: from YAML frontmatter of each agent
for tier in planner actor actor-heavy reviewer; do
    agent_file="$AGENTS_DIR/${tier}.md"
    if [[ -f "$agent_file" ]]; then
        model=$(grep -E '^model:' "$agent_file" | sed 's/^model:[[:space:]]*//' | tr -d '\r')
        echo -e "${tier}\t${model}"
    else
        echo -e "${tier}\tMISSING" >&2
    fi
done

exit 0
