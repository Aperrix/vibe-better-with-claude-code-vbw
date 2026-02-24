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
