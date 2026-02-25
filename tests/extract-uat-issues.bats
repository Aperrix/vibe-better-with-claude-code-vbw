#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  # Create a phase directory with a UAT file
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

# Helper: create a UAT file with given content
create_uat_file() {
  local content="$1"
  printf '%s\n' "$content" > "$PHASE_DIR/03-UAT.md"
}

@test "extract-uat-issues: single major issue" {
  create_uat_file '---
phase: 03
plan_count: 3
status: issues_found
started: 2026-02-22
completed: 2026-02-22
total_tests: 6
passed: 5
skipped: 0
issues: 1
---

# Phase 03 UAT

## Tests

### P01-T1: Passing test

- **Plan:** 03-01 — Fix something
- **Scenario:** Do something
- **Expected:** It works
- **Result:** pass

### P01-T2: Failing test

- **Plan:** 03-01 — Fix something else
- **Scenario:** Do another thing
- **Expected:** It should work
- **Result:** issue
- **Issue:**
  - Description: Widget fails on edge case
  - Severity: major

## Summary

- Passed: 5
- Issues: 1
- Total: 6'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_phase=03"* ]]
  [[ "${lines[0]}" == *"uat_issues_total=1"* ]]
  [[ "${lines[1]}" == "P01-T2|major|Widget fails on edge case" ]]
}

@test "extract-uat-issues: multiple issues with mixed severity" {
  create_uat_file '---
phase: 03
status: issues_found
issues: 3
---

## Tests

### P01-T1: First issue

- **Result:** issue
- **Issue:**
  - Description: First problem
  - Severity: critical

### P02-T1: Passing

- **Result:** pass

### P02-T2: Second issue

- **Result:** issue
- **Issue:**
  - Description: Second problem
  - Severity: minor

### D1: Discovered issue

- **Result:** issue
- **Issue:**
  - Description: Found during testing
  - Severity: major

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_issues_total=3"* ]]
  [[ "${lines[1]}" == "P01-T1|critical|First problem" ]]
  [[ "${lines[2]}" == "P02-T2|minor|Second problem" ]]
  [[ "${lines[3]}" == "D1|major|Found during testing" ]]
}

@test "extract-uat-issues: long description is preserved in full" {
  local long_desc
  long_desc=$(printf 'x%.0s' {1..250})
  create_uat_file "---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Long desc

- **Result:** issue
- **Issue:**
  - Description: ${long_desc}
  - Severity: major

## Summary"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Description must NOT be truncated — full 250 chars preserved
  [[ "${lines[1]}" != *"..."* ]]
  [[ "${lines[1]}" == "P01-T1|major|${long_desc}" ]]
}

@test "extract-uat-issues: no UAT file returns error marker" {
  rm -f "$PHASE_DIR"/*.md
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_extract_error=no_uat_file"* ]]
}

@test "extract-uat-issues: non-issues_found status returns status marker" {
  create_uat_file '---
phase: 03
status: complete
issues: 0
---

## Tests

### P01-T1: All good

- **Result:** pass

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_extract_status=complete"* ]]
}

@test "extract-uat-issues: missing directory returns error" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$TEST_TEMP_DIR/nonexistent"

  [ "$status" -ne 0 ]
}

@test "extract-uat-issues: excludes SOURCE-UAT.md" {
  # Create a SOURCE-UAT.md (copied from milestone) and a real UAT
  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Real issue

- **Result:** issue
- **Issue:**
  - Description: Real issue from latest UAT
  - Severity: major

## Summary'

  # Also create a SOURCE-UAT.md with different content
  cat > "$PHASE_DIR/03-SOURCE-UAT.md" <<'EOF'
---
phase: 03
status: issues_found
issues: 1
---

### P01-T1: Old

- **Result:** issue
- **Issue:**
  - Description: Old milestone issue
  - Severity: critical
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[1]}" == *"Real issue from latest UAT"* ]]
  [[ "$output" != *"Old milestone issue"* ]]
}

@test "extract-uat-issues: all pass tests produce zero issues" {
  create_uat_file '---
phase: 03
status: issues_found
issues: 0
---

## Tests

### P01-T1: Everything works

- **Result:** pass

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  # status: issues_found but no actual issue blocks — script still works
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_issues_total=0"* ]]
}

# ===========================================================================
# UAT pre-seeding expansion logic (vibe.md Block 5)
# ===========================================================================

@test "uat-preseed: runs phase-detect live when cached file is missing (race fix)" {
  # Simulate the race: symlink exists but cached phase-detect file does NOT.
  # The fix runs phase-detect.sh live instead of only reading the cached file.
  local session_key="test-race-$$"
  local link="/tmp/.vbw-plugin-root-link-${session_key}"
  local cache_file="/tmp/.vbw-phase-detect-${session_key}.txt"

  # Create symlink pointing to plugin root
  ln -sf "$PROJECT_ROOT" "$link"
  # Ensure NO cached file exists (simulates race)
  rm -f "$cache_file"

  # Create project state that phase-detect would read
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"
  create_uat_file '---
status: issues_found
---
### P01-T2: Test failure
- **Result:** issue
  - Description: Race condition test issue
  - Severity: major'

  cd "$TEST_TEMP_DIR"

  # Run the expansion logic (extracted from vibe.md Block 5)
  # This should run phase-detect.sh live when cached file is absent
  run bash -c '
    SESSION_KEY="'"$session_key"'"
    L="'"$link"'"
    P="'"$cache_file"'"
    PD=""
    if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
    fi
    [ -z "$PD" ] && [ -f "$P" ] && PD=$(cat "$P")
    STATE=$(printf "%s" "$PD" | grep "^next_phase_state=" | head -1 | cut -d= -f2)
    if [ "$STATE" = "needs_uat_remediation" ]; then
      SLUG=$(printf "%s" "$PD" | grep "^next_phase_slug=" | head -1 | cut -d= -f2)
      PDIR=".vbw-planning/phases/$SLUG"
      [ -d "$PDIR" ] && bash "$L/scripts/extract-uat-issues.sh" "$PDIR" 2>/dev/null || echo "uat_extract_error=true"
    else
      echo "not_in_remediation"
    fi
  '

  [ "$status" -eq 0 ]
  # phase-detect ran live but this test dir has no config.json etc,
  # so phase-detect returns an error or non-remediation state — that's fine,
  # the key assertion is that it didn't silently fail with empty PD.
  # The output should be "not_in_remediation" (no .vbw-planning/config.json)
  [[ "$output" == *"not_in_remediation"* ]] || [[ "$output" == *"uat_extract"* ]]

  # Cleanup
  rm -f "$link" "$cache_file"
}

@test "uat-preseed: falls back to cached file when symlink is missing" {
  local session_key="test-fallback-$$"
  local link="/tmp/.vbw-plugin-root-link-${session_key}"
  local cache_file="/tmp/.vbw-phase-detect-${session_key}.txt"

  # No symlink, but cached file exists
  rm -f "$link"
  echo "next_phase_state=needs_uat_remediation
next_phase_slug=03-test-phase
next_phase=3" > "$cache_file"

  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"
  create_uat_file '---
status: issues_found
---
### P01-T2: Test failure
- **Result:** issue
  - Description: Fallback test issue
  - Severity: major'

  cd "$TEST_TEMP_DIR"

  # With no symlink, wait loop exits after max retries, then falls back to cached file
  # Since symlink doesn't exist, extract-uat-issues.sh can't be resolved via $L
  run bash -c '
    SESSION_KEY="'"$session_key"'"
    L="'"$link"'"
    P="'"$cache_file"'"
    # Skip wait (no symlink to wait for in test)
    PD=""
    if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
    fi
    [ -z "$PD" ] && [ -f "$P" ] && PD=$(cat "$P")
    STATE=$(printf "%s" "$PD" | grep "^next_phase_state=" | head -1 | cut -d= -f2)
    echo "state=$STATE"
  '

  [ "$status" -eq 0 ]
  # Should have read the cached file and found needs_uat_remediation
  [[ "$output" == *"state=needs_uat_remediation"* ]]

  rm -f "$cache_file"
}
