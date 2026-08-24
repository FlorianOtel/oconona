#!/usr/bin/env python3
"""
check-tiers.py — verify tier → model assignment consistency across the oconona project.

Hard-fail checks (exit 1 if ANY fail):
  1. Agent frontmatter models match orchestra-tiers.yaml tier definitions.
  2. All tier and recommendation models exist in model-rates.yaml.
  3. All tier and recommendation models exist in context-windows.yaml.

Soft-warn checks (print warnings, continue, exit 0 regardless):
  1. README.md tier-model table mentions each tier model.
  2. AGENTS.md model-recommendations block mentions each recommendation model.
  3. commands/brain.md mentions Reviewer model in first 20 lines.
  4. docs/design.md mentions each tier model somewhere.

Usage:
  python check-tiers.py [--repo-root /path/to/repo]
"""

import yaml
import sys
import re
from pathlib import Path
from argparse import ArgumentParser


def load_yaml(filepath):
    """Load YAML file, return dict or die with [HARD-FAIL]."""
    try:
        with open(filepath) as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"[HARD-FAIL] {filepath}: file not found")
        sys.exit(1)
    except Exception as e:
        print(f"[HARD-FAIL] {filepath}: {e}")
        sys.exit(1)


def extract_yaml_frontmatter(filepath):
    """Extract YAML frontmatter (between top --- delimiters) from a markdown file.

    Falls back to simple key-value parsing if YAML parsing fails
    (e.g., due to unquoted special characters in description).
    """
    try:
        with open(filepath) as f:
            content = f.read()
    except FileNotFoundError:
        return None

    if not content.startswith("---"):
        return None

    # Find closing ---
    lines = content.split('\n')
    if len(lines) < 2 or lines[0] != "---":
        return None

    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm_text = "\n".join(lines[1:i])
            try:
                return yaml.safe_load(fm_text)
            except Exception as e:
                # Fallback: simple key-value parsing for common fields
                result = {}
                for line in fm_text.split('\n'):
                    if ':' in line and not line.startswith(' '):
                        key, val = line.split(':', 1)
                        result[key.strip()] = val.strip()
                return result if result else None
    return None


def main():
    parser = ArgumentParser(description="Verify tier → model assignment consistency")
    parser.add_argument("--repo-root", help="Repository root (default: inferred from script location)")
    args = parser.parse_args()

    if args.repo_root:
        repo_root = Path(args.repo_root).resolve()
    else:
        repo_root = Path(__file__).parent.parent

    # Track results
    hard_fails = []
    soft_warns = []

    # Load tiers config
    tiers_file = repo_root / "config" / "orchestra-tiers.yaml"
    if not tiers_file.exists():
        print("[HARD-FAIL] config/orchestra-tiers.yaml: file not found")
        sys.exit(1)

    tiers_config = load_yaml(tiers_file)
    tier_models = {k: v["model"] for k, v in tiers_config.get("tiers", {}).items()}
    rec_models = {k: v["model"] for k, v in tiers_config.get("recommendations", {}).items()}

    all_models = set(tier_models.values()) | set(rec_models.values())

    # ────── HARD-FAIL CHECKS ──────────────────────────────────────────────────────

    # Check 1: Agent frontmatter models match tier definitions
    for tier_name, expected_model in tier_models.items():
        agent_file = repo_root / "agents" / f"{tier_name}.md"
        if not agent_file.exists():
            hard_fails.append(f"agents/{tier_name}.md: file not found")
            continue

        fm = extract_yaml_frontmatter(agent_file)
        if not fm or "model" not in fm:
            hard_fails.append(f"agents/{tier_name}.md: no 'model' field in frontmatter")
            continue

        actual_model = fm["model"]
        if actual_model != expected_model:
            hard_fails.append(
                f"agents/{tier_name}.md: model is {actual_model}, expected {expected_model}"
            )
        else:
            print(f"[OK] agents/{tier_name}.md model matches tiers.{tier_name}")

    # Check 2: All models exist in model-rates.yaml
    rates_file = repo_root / "scripts" / "model-rates.yaml"
    rates_config = load_yaml(rates_file)
    provider_models = set(rates_config.get("provider_models", {}).keys())

    for model in all_models:
        if model not in provider_models:
            hard_fails.append(f"model-rates.yaml: no entry for {model}")
        else:
            print(f"[OK] model-rates.yaml: {model} entry exists")

    # Check 3: All models exist in context-windows.yaml
    # context-windows.yaml uses:
    #   - Bare names for Anthropic models (claude-opus-5, claude-sonnet-5)
    #   - Full sohoai/ prefix for SoHoAI models (sohoai/qwen3-coder-next)
    ctx_file = repo_root / "config" / "context-windows.yaml"
    ctx_config = load_yaml(ctx_file)
    ctx_models = set(ctx_config.get("models", {}).keys())

    for model in all_models:
        # Strip provider prefix for lookup
        lookup_key = model
        if model.startswith("anthropic/"):
            lookup_key = model.replace("anthropic/", "")
        # SoHoAI models use full prefix in context-windows

        if lookup_key not in ctx_models:
            hard_fails.append(f"context-windows.yaml: no entry for {model}")
        else:
            print(f"[OK] context-windows.yaml: {model} entry exists")

    # ────── SOFT-WARN CHECKS ──────────────────────────────────────────────────────

    # Check 1: README.md mentions tier models in model-tiers table (lines 5-15)
    readme_file = repo_root / "README.md"
    if readme_file.exists():
        try:
            with open(readme_file) as f:
                all_lines = f.readlines()
                readme_lines = all_lines[4:15] if len(all_lines) >= 5 else []
            readme_text = "".join(readme_lines)
            for model in tier_models.values():
                if model not in readme_text:
                    soft_warns.append(f"README.md: tier-table may not reflect {model}")
                else:
                    print(f"[OK] README.md: {model} appears in tier-table")
        except Exception as e:
            soft_warns.append(f"README.md: could not read (error: {e})")
    else:
        soft_warns.append("README.md: file not found")

    # Check 2: AGENTS.md mentions each model in "model recommendations" block
    agents_md_file = repo_root / "AGENTS.md"
    if agents_md_file.exists():
        try:
            with open(agents_md_file) as f:
                agents_text = f.read()
            # Look for the "## Brain and /duo model recommendations" header
            if "## Brain and /duo model recommendations" in agents_text or \
               "## Brain" in agents_text or "model recommendations" in agents_text:
                # Extract text after this header
                idx = max(agents_text.find("## Brain"), agents_text.find("## model"))
                rec_block = agents_text[idx:] if idx >= 0 else agents_text
                for model in rec_models.values():
                    if model not in rec_block:
                        soft_warns.append(f"AGENTS.md: model-recommendations block may not reflect {model}")
                    else:
                        print(f"[OK] AGENTS.md: {model} appears in model-recommendations")
            else:
                soft_warns.append("AGENTS.md: 'model recommendations' block not found")
        except Exception as e:
            soft_warns.append(f"AGENTS.md: could not read (error: {e})")
    else:
        soft_warns.append("AGENTS.md: file not found")

    # Check 3: commands/brain.md mentions Reviewer model in first 20 lines
    brain_cmd_file = repo_root / "commands" / "brain.md"
    reviewer_model = tier_models.get("reviewer", "anthropic/claude-sonnet-5")
    researcher_model = "anthropic/claude-haiku-4-5"
    if brain_cmd_file.exists():
        try:
            with open(brain_cmd_file) as f:
                brain_lines = f.readlines()[:20]
            brain_text = "".join(brain_lines)
            if reviewer_model not in brain_text:
                soft_warns.append(f"commands/brain.md: Reviewer model mention may be stale")
            else:
                print(f"[OK] commands/brain.md: Reviewer model ({reviewer_model}) mentioned")
            if researcher_model not in brain_text:
                soft_warns.append(f"commands/brain.md: Researcher model mention may be stale ({researcher_model} not in first 20 lines)")
            else:
                print(f"[OK] commands/brain.md: Researcher model ({researcher_model}) mentioned")
        except Exception as e:
            soft_warns.append(f"commands/brain.md: could not read (error: {e})")
    else:
        soft_warns.append("commands/brain.md: file not found")

    # Check 4: docs/design.md mentions each tier model
    design_file = repo_root / "docs" / "design.md"
    if design_file.exists():
        try:
            with open(design_file) as f:
                design_text = f.read()
            for model in tier_models.values():
                if model not in design_text:
                    soft_warns.append(f"docs/design.md: tier table may not reflect {model}")
                else:
                    print(f"[OK] docs/design.md: {model} appears in design doc")
        except Exception as e:
            soft_warns.append(f"docs/design.md: could not read (error: {e})")
    else:
        soft_warns.append("docs/design.md: file not found")

    # ────── PRINT RESULTS ──────────────────────────────────────────────────────────

    for warn in soft_warns:
        print(f"[SOFT-WARN] {warn}")

    print(f"check-tiers: {len(hard_fails)} hard-fail(s), {len(soft_warns)} soft-warn(s)")

    if hard_fails:
        print("\nHard failures:")
        for fail in hard_fails:
            print(f"  [HARD-FAIL] {fail}")
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
