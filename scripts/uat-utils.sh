#!/usr/bin/env bash
# uat-utils.sh — Shared UAT helper functions for phase-detect, suggest-next,
# and prepare-reverification. Source this file; do not execute directly.
#
# Functions:
#   extract_status_value <file>   — Extract status value from YAML frontmatter
#                                   with body-level fallback for brownfield files.
#   latest_non_source_uat <dir>   — Find the latest canonical UAT file in a phase
#                                   directory, excluding SOURCE-UAT.md copies.

# Guard: prevent accidental direct execution
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Error: uat-utils.sh must be sourced, not executed directly" >&2
  exit 1
fi

# extract_status_value — Extract 'status:' value from a markdown file.
#
# Priority: YAML frontmatter (between --- delimiters at file start).
# Fallback: first unindented 'status:' line in the body. The body fallback
# requires the line to start at column 0 (no leading whitespace) to avoid
# matching indented prose, markdown list items, or table rows that happen
# to contain 'status:'.
extract_status_value() {
  local file="$1"
  local result
  # Try frontmatter first
  result=$(awk '
    BEGIN { in_fm = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && tolower($0) ~ /^[[:space:]]*status[[:space:]]*:/ {
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      print tolower(value)
      exit
    }
  ' "$file" 2>/dev/null || true)
  # Fallback: scan body for unindented status: line (brownfield/manual UATs)
  if [ -z "$result" ]; then
    result=$(awk '
      tolower($0) ~ /^status[[:space:]]*:/ {
        value = $0
        sub(/^[^:]*:[[:space:]]*/, "", value)
        gsub(/[[:space:]]+$/, "", value)
        print tolower(value)
        exit
      }
    ' "$file" 2>/dev/null || true)
  fi
  printf '%s' "$result"
}

# latest_non_source_uat — Find the latest [0-9]*-UAT.md file in a directory,
# excluding SOURCE-UAT.md files (verbatim copies from milestone remediation).
#
# Relies on glob expansion order: the last match in numeric-prefix order is
# returned. Returns empty string (and exit 0) if no matching file exists.
latest_non_source_uat() {
  local dir="$1"
  local f
  local latest=""

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

  for f in "${dir}"[0-9]*-UAT.md; do
    [ -f "$f" ] || continue
    case "$f" in
      *SOURCE-UAT.md) continue ;;
    esac
    latest="$f"
  done

  if [ -n "$latest" ]; then
    printf '%s\n' "$latest"
  fi
  return 0
}
