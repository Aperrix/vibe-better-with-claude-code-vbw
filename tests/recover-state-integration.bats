#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"

  # Init git so session-start.sh works
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt && git add init.txt && git commit -q -m "init"

  # Create minimal STATE.md
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'STATE'
Phase: 1 of 2 (Setup)
Status: in-progress
Progress: 50%
STATE

  # Create phases dir with a plan
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  echo "# Plan" > "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-01-PLAN.md"

  # Create PROJECT.md so session-start doesn't suggest /vbw:init
  echo "# Test Project" > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"
}

teardown() {
  teardown_temp_dir
}

# --- Unit tests for recover-state.sh ---

@test "recover-state: outputs empty JSON when event_recovery is false" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = false' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "recover-state: outputs empty JSON when no arguments" {
  run bash "$SCRIPTS_DIR/recover-state.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "recover-state: outputs empty JSON when phase dir not found" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/recover-state.sh" 99 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "recover-state: reconstructs state from SUMMARY.md files" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  # Create a completed plan (has SUMMARY.md)
  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  echo "# Summary" > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.phase == 1' >/dev/null
  echo "$output" | jq -e '.status == "complete"' >/dev/null
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
}

@test "recover-state: detects pending plans without SUMMARY.md" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  # Plan exists but no SUMMARY.md
  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pending"' >/dev/null
  echo "$output" | jq -e '.plans[0].status == "pending"' >/dev/null
}

# --- Integration: session-start.sh calls recover-state.sh ---

@test "session-start: calls recover-state.sh when event log is newer than execution state" {
  cd "$TEST_TEMP_DIR"
  # Enable event_recovery
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  # Create stale execution state
  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","plans":[{"id":"01-01","status":"pending"}]}
STATE

  # Create event log with a plan_end event (newer than state)
  mkdir -p .vbw-planning/.events
  sleep 1
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl

  # Create SUMMARY.md to confirm completion
  echo "# Summary" > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  # The execution state should have been recovered
  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "complete" ]
}

@test "session-start: skips recovery when event_recovery is false" {
  cd "$TEST_TEMP_DIR"
  # event_recovery is false by default in test config
  # Create a stale execution state that would be recovered if enabled
  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","plans":[{"id":"01-01","status":"pending"}]}
STATE

  mkdir -p .vbw-planning/.events
  sleep 1
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  echo "# Summary" > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  # State should NOT have been recovered (still running)
  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "running" ]
}

@test "session-start: recovers missing execution state when event log exists" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  # No execution state file, but event log exists
  mkdir -p .vbw-planning/.events
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  echo "# Summary" > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  # Execution state should have been created
  [ -f .vbw-planning/.execution-state.json ]
  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "complete" ]
}

@test "session-start: does not recover when event log does not exist" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  # No event log, no execution state
  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  # No execution state should have been created
  [ ! -f .vbw-planning/.execution-state.json ]
}

@test "session-start: does not recover when execution state is newer than event log" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  # Create event log first
  mkdir -p .vbw-planning/.events
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  echo "# Summary" > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  # Create execution state AFTER event log (newer)
  sleep 1
  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","plans":[{"id":"01-01","status":"pending"}]}
STATE

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  # State should NOT have been overwritten
  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "running" ]
}
