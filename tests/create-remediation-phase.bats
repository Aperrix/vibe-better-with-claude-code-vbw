#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy && git add dummy && git commit -m "init" --quiet
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "create-remediation-phase creates next numbered phase and copies source UAT" {
  mkdir -p .vbw-planning/phases/01-foundation
  mkdir -p .vbw-planning/milestones/02-archive/phases/08-cost-basis

  cat > .vbw-planning/milestones/02-archive/phases/08-cost-basis/08-UAT.md <<'EOF'
---
phase: 08
status: issues_found
---
Severity: major
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/02-archive/phases/08-cost-basis

  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^phase=02$'
  echo "$output" | grep -q '^phase_dir=.vbw-planning/phases/02-remediate-02-archive-cost-basis$'
  [ -f .vbw-planning/phases/02-remediate-02-archive-cost-basis/02-CONTEXT.md ]
  [ -f .vbw-planning/phases/02-remediate-02-archive-cost-basis/02-SOURCE-UAT.md ]
}

@test "create-remediation-phase works when source UAT file is missing" {
  mkdir -p .vbw-planning/milestones/legacy/phases/03-api

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/legacy/phases/03-api

  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^phase=01$'
  echo "$output" | grep -q '^source_uat=none$'
}