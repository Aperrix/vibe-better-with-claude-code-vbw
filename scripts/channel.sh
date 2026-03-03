#!/usr/bin/env bash
# channel.sh — VBW update channel resolution
#
# Source this file from other scripts:
#   . "$(dirname "$0")/channel.sh"
#
# After sourcing:
#   VBW_CHANNEL      — "stable" or "next" (default: "stable")
#   VBW_CHANNEL_FILE — path to the channel marker file
#   vbw_set_channel <channel>  — writes the marker
#   vbw_github_branch          — echoes "main" or "next"
#
# The marker lives at $CLAUDE_DIR/plugins/cache/vbw-marketplace/.channel
# (outside the vbw/ directory so cache-nuke.sh does not destroy it).
# Missing or unrecognized values fail-open to "stable".

# Source CLAUDE_DIR if not already set
if [ -z "${CLAUDE_DIR:-}" ]; then
  . "$(dirname "$0")/resolve-claude-dir.sh"
fi

VBW_CHANNEL_FILE="$CLAUDE_DIR/plugins/cache/vbw-marketplace/.channel"

# Read channel, default to stable
VBW_CHANNEL="stable"
if [ -f "$VBW_CHANNEL_FILE" ]; then
  _vbw_ch=$(cat "$VBW_CHANNEL_FILE" 2>/dev/null | tr -d '[:space:]')
  case "$_vbw_ch" in
    next) VBW_CHANNEL="next" ;;
    *)    VBW_CHANNEL="stable" ;;
  esac
  unset _vbw_ch
fi

vbw_set_channel() {
  local ch="$1"
  case "$ch" in
    next|stable) ;;
    *) ch="stable" ;;
  esac
  mkdir -p "$(dirname "$VBW_CHANNEL_FILE")" 2>/dev/null
  printf '%s\n' "$ch" > "$VBW_CHANNEL_FILE"
  VBW_CHANNEL="$ch"
}

vbw_github_branch() {
  case "$VBW_CHANNEL" in
    next) echo "next" ;;
    *)    echo "main" ;;
  esac
}

# No export — callers source this file, so variables are available in their scope.
# Avoid leaking into child processes unnecessarily.
