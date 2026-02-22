#!/usr/bin/env bash
set -euo pipefail

# verify-plugin-root-resolution.sh — Ensure CLAUDE_PLUGIN_ROOT resolves deterministically
#
# Problem: ${CLAUDE_PLUGIN_ROOT} is available in Claude Code's process env (for !` backtick
# and @ file references) but NOT in the Bash tool's shell environment. Model-executed
# bash commands that reference ${CLAUDE_PLUGIN_ROOT} expand it to an empty string.
#
# Fix: Every model-executed ${CLAUDE_PLUGIN_ROOT} is replaced with an inline !` backtick
# expression `!`echo $CLAUDE_PLUGIN_ROOT` that resolves at command load time. The model
# sees the actual absolute path, never the variable.
#
# Safe contexts (all refs must be in one of these):
#   - `!`echo $CLAUDE_PLUGIN_ROOT`   (inline load-time resolution — the standard pattern)
#   - !`...${CLAUDE_PLUGIN_ROOT}...` (preamble/context load-time bash)
#   - @${CLAUDE_PLUGIN_ROOT}/...     (file inclusion at load time)
#   - Plugin root: ...               (preamble display line)
#
# Unsafe (must not exist):
#   - bare ${CLAUDE_PLUGIN_ROOT} in model-executed text (resolves to empty in bash)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"
REFERENCES_DIR="$ROOT/references"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

echo "=== Plugin Root Inline Resolution Verification ==="

for file in "$COMMANDS_DIR"/*.md "$REFERENCES_DIR"/*.md; do
  base="$(basename "$file" .md)"

  # Skip files with no CLAUDE_PLUGIN_ROOT references at all
  if ! grep -q 'CLAUDE_PLUGIN_ROOT' "$file"; then
    pass "$base: no CLAUDE_PLUGIN_ROOT references"
    continue
  fi

  # Count total references
  total_refs=$(grep -c 'CLAUDE_PLUGIN_ROOT' "$file" || true)

  # Count lines with CLAUDE_PLUGIN_ROOT that are NOT in any safe context.
  # Safe contexts: !` backtick expressions, @ file references, Plugin root: preamble,
  # and inline `!`echo $CLAUDE_PLUGIN_ROOT` resolution patterns.
  unsafe_count=$(grep 'CLAUDE_PLUGIN_ROOT' "$file" \
    | grep -v '!`[^`]*CLAUDE_PLUGIN_ROOT' \
    | grep -v '@${CLAUDE_PLUGIN_ROOT}' \
    | grep -v 'Plugin root:' \
    | grep -vc '`!`echo .*CLAUDE_PLUGIN_ROOT' || true)

  if [ "$unsafe_count" -eq 0 ]; then
    pass "$base: all $total_refs references are in safe contexts (inline !-backtick or @ file ref)"
  else
    fail "$base: $unsafe_count CLAUDE_PLUGIN_ROOT refs in model-executed context (not inline-resolved)"
    # Show the offending lines for debugging
    grep -n 'CLAUDE_PLUGIN_ROOT' "$file" \
      | grep -v '!`[^`]*CLAUDE_PLUGIN_ROOT' \
      | grep -v '@${CLAUDE_PLUGIN_ROOT}' \
      | grep -v 'Plugin root:' \
      | grep -v '`!`echo .*CLAUDE_PLUGIN_ROOT' \
      | while IFS= read -r line; do echo "      $line"; done
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All plugin root inline resolution checks passed."
echo ""

# --- Phase 2: Verify preamble !` backtick expansions have CLAUDE_CONFIG_DIR fallback ---
echo "=== Preamble Fallback Verification ==="
echo "(Ensures preamble !-backtick CLAUDE_PLUGIN_ROOT refs include :-fallback for non-standard installs)"

PASS2=0
FAIL2=0

for file in "$COMMANDS_DIR"/*.md "$REFERENCES_DIR"/*.md; do
  base="$(basename "$file" .md)"

  # Only check preamble !` backtick expressions (those using ${CLAUDE_PLUGIN_ROOT} with braces).
  # Inline `!`echo $CLAUDE_PLUGIN_ROOT` patterns (without braces) are intentionally bare —
  # they rely on CLAUDE_PLUGIN_ROOT always being set at load time and don't need a fallback.
  backtick_lines=$(grep -n 'CLAUDE_PLUGIN_ROOT' "$file" \
    | grep '!`[^`]*\${CLAUDE_PLUGIN_ROOT' || true)

  [ -z "$backtick_lines" ] && continue

  # For each matching line, check it uses the :- fallback pattern
  has_bare=0
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    if echo "$match" | grep -q 'CLAUDE_PLUGIN_ROOT:-'; then
      : # has fallback, safe
    else
      has_bare=1
      lineno="${match%%:*}"
      echo "  BARE  $base:$lineno — missing :-fallback in preamble !-backtick expansion"
    fi
  done <<< "$backtick_lines"

  if [ "$has_bare" -eq 0 ]; then
    echo "PASS  $base: all preamble !-backtick CLAUDE_PLUGIN_ROOT refs have :-fallback"
    PASS2=$((PASS2 + 1))
  else
    fail "$base: has preamble !-backtick CLAUDE_PLUGIN_ROOT without :-fallback"
    FAIL2=$((FAIL2 + 1))
  fi
done

if [ "$PASS2" -eq 0 ] && [ "$FAIL2" -eq 0 ]; then
  echo "(no preamble !-backtick CLAUDE_PLUGIN_ROOT expansions found — nothing to check)"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS2 PASS, $FAIL2 FAIL"
echo "==============================="

if [ "$FAIL2" -gt 0 ]; then
  exit 1
fi

echo "All preamble fallback checks passed."
exit 0
