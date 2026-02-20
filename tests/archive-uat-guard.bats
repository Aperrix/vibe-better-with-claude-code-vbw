#!/usr/bin/env bats
# Tests for archive UAT guard and post-archive UAT detection (Issue #120)

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

# --- phase-detect.sh: milestone UAT scanning ---

@test "phase-detect detects unresolved UAT in latest shipped milestone when active phases empty" {
  mkdir -p .vbw-planning/phases
  mkdir -p .vbw-planning/milestones/01-foundation/phases/08-cost-basis/
  echo "# Shipped" > .vbw-planning/milestones/01-foundation/SHIPPED.md

  # Phase 8 has full execution artifacts + unresolved UAT
  touch .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-01-PLAN.md
  touch .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-UAT.md <<'EOF'
---
phase: 08
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** sample issue
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_phase=08"
  echo "$output" | grep -q "milestone_uat_slug=01-foundation"
  echo "$output" | grep -q "milestone_uat_major_or_higher=true"
}

@test "phase-detect reports milestone_uat_issues=false when shipped UATs are all complete" {
  mkdir -p .vbw-planning/phases
  mkdir -p .vbw-planning/milestones/01-foundation/phases/08-cost-basis/
  echo "# Shipped" > .vbw-planning/milestones/01-foundation/SHIPPED.md

  touch .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-01-PLAN.md
  touch .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-UAT.md <<'EOF'
---
phase: 08
status: complete
---
All passed.
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=false"
}

@test "phase-detect reports milestone_uat_issues=false when no milestones exist" {
  mkdir -p .vbw-planning/phases

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=false"
}

@test "phase-detect scans latest milestone (highest sort order) for UAT issues" {
  mkdir -p .vbw-planning/phases

  # Older milestone — UAT resolved
  mkdir -p .vbw-planning/milestones/01-old/phases/01-setup/
  echo "# Shipped" > .vbw-planning/milestones/01-old/SHIPPED.md
  touch .vbw-planning/milestones/01-old/phases/01-setup/01-01-PLAN.md
  touch .vbw-planning/milestones/01-old/phases/01-setup/01-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-old/phases/01-setup/01-UAT.md <<'EOF'
---
phase: 01
status: complete
---
All passed.
EOF

  # Latest milestone — UAT unresolved
  mkdir -p .vbw-planning/milestones/02-latest/phases/03-api/
  echo "# Shipped" > .vbw-planning/milestones/02-latest/SHIPPED.md
  touch .vbw-planning/milestones/02-latest/phases/03-api/03-01-PLAN.md
  touch .vbw-planning/milestones/02-latest/phases/03-api/03-01-SUMMARY.md
  cat > .vbw-planning/milestones/02-latest/phases/03-api/03-UAT.md <<'EOF'
---
phase: 03
status: issues_found
---
  - Severity: critical
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_slug=02-latest"
}

@test "phase-detect does not scan milestones when active phases have work" {
  # Active phases with work — milestone scanning should be skipped
  mkdir -p .vbw-planning/phases/01-active/
  touch .vbw-planning/phases/01-active/01-01-PLAN.md

  # Milestone with unresolved UAT
  mkdir -p .vbw-planning/milestones/01-old/phases/01-done/
  echo "# Shipped" > .vbw-planning/milestones/01-old/SHIPPED.md
  touch .vbw-planning/milestones/01-old/phases/01-done/01-01-PLAN.md
  touch .vbw-planning/milestones/01-old/phases/01-done/01-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-old/phases/01-done/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Active phases have work → milestone UAT scan should not fire
  echo "$output" | grep -q "milestone_uat_issues=false"
  echo "$output" | grep -q "next_phase_state=needs_execute"
}

@test "phase-detect milestone UAT minor-only sets major_or_higher=false" {
  mkdir -p .vbw-planning/phases
  mkdir -p .vbw-planning/milestones/01-foundation/phases/05-polish/
  echo "# Shipped" > .vbw-planning/milestones/01-foundation/SHIPPED.md

  touch .vbw-planning/milestones/01-foundation/phases/05-polish/05-01-PLAN.md
  touch .vbw-planning/milestones/01-foundation/phases/05-polish/05-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-foundation/phases/05-polish/05-UAT.md <<'EOF'
---
phase: 05
status: issues_found
---

### P01-T1: typo
- Severity: minor
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_major_or_higher=false"
}

@test "phase-detect milestone UAT with no severity tags defaults to major" {
  mkdir -p .vbw-planning/phases
  mkdir -p .vbw-planning/milestones/01-foundation/phases/05-polish/
  echo "# Shipped" > .vbw-planning/milestones/01-foundation/SHIPPED.md

  touch .vbw-planning/milestones/01-foundation/phases/05-polish/05-01-PLAN.md
  touch .vbw-planning/milestones/01-foundation/phases/05-polish/05-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-foundation/phases/05-polish/05-UAT.md <<'EOF'
---
phase: 05
status: issues_found
---
Some issue without severity
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_major_or_higher=true"
}

@test "phase-detect emits milestone_uat_phase_dir for routable recovery" {
  mkdir -p .vbw-planning/phases
  mkdir -p .vbw-planning/milestones/01-foundation/phases/08-cost-basis/
  echo "# Shipped" > .vbw-planning/milestones/01-foundation/SHIPPED.md

  touch .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-01-PLAN.md
  touch .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-UAT.md <<'EOF'
---
phase: 08
status: issues_found
---
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_phase_dir=.vbw-planning/milestones/01-foundation/phases/08-cost-basis"
}

@test "phase-detect finds unresolved UAT in older milestone when latest milestone is clean" {
  mkdir -p .vbw-planning/phases

  # Older milestone has unresolved UAT
  mkdir -p .vbw-planning/milestones/01-old/phases/03-api/
  echo "# Shipped" > .vbw-planning/milestones/01-old/SHIPPED.md
  touch .vbw-planning/milestones/01-old/phases/03-api/03-01-PLAN.md
  touch .vbw-planning/milestones/01-old/phases/03-api/03-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-old/phases/03-api/03-UAT.md <<'EOF'
---
phase: 03
status: issues_found
---
  - Severity: major
EOF

  # Latest milestone is fully clean
  mkdir -p .vbw-planning/milestones/02-latest/phases/04-ui/
  echo "# Shipped" > .vbw-planning/milestones/02-latest/SHIPPED.md
  touch .vbw-planning/milestones/02-latest/phases/04-ui/04-01-PLAN.md
  touch .vbw-planning/milestones/02-latest/phases/04-ui/04-01-SUMMARY.md
  cat > .vbw-planning/milestones/02-latest/phases/04-ui/04-UAT.md <<'EOF'
---
phase: 04
status: complete
---
All passed.
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_slug=01-old"
  echo "$output" | grep -q "milestone_uat_phase=03"
}

@test "phase-detect milestone ordering handles non-zero-padded names" {
  mkdir -p .vbw-planning/phases

  mkdir -p .vbw-planning/milestones/9-old/phases/01-legacy/
  echo "# Shipped" > .vbw-planning/milestones/9-old/SHIPPED.md
  touch .vbw-planning/milestones/9-old/phases/01-legacy/01-01-PLAN.md
  touch .vbw-planning/milestones/9-old/phases/01-legacy/01-01-SUMMARY.md
  cat > .vbw-planning/milestones/9-old/phases/01-legacy/01-UAT.md <<'EOF'
---
phase: 01
status: complete
---
All passed.
EOF

  mkdir -p .vbw-planning/milestones/10-new/phases/02-api/
  echo "# Shipped" > .vbw-planning/milestones/10-new/SHIPPED.md
  touch .vbw-planning/milestones/10-new/phases/02-api/02-01-PLAN.md
  touch .vbw-planning/milestones/10-new/phases/02-api/02-01-SUMMARY.md
  cat > .vbw-planning/milestones/10-new/phases/02-api/02-UAT.md <<'EOF'
---
phase: 02
status: issues_found
---
  - Severity: critical
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_slug=10-new"
}

@test "phase-detect brownfield milestone without SHIPPED.md is still scanned" {
  mkdir -p .vbw-planning/phases
  mkdir -p .vbw-planning/milestones/legacy-archive/phases/07-payments/

  touch .vbw-planning/milestones/legacy-archive/phases/07-payments/07-01-PLAN.md
  touch .vbw-planning/milestones/legacy-archive/phases/07-payments/07-01-SUMMARY.md
  cat > .vbw-planning/milestones/legacy-archive/phases/07-payments/07-UAT.md <<'EOF'
---
phase: 07
status: issues_found
---
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "has_shipped_milestones=true"
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_slug=legacy-archive"
}

@test "archive-uat-guard blocks on active unresolved UAT" {
  echo "# Project" > .vbw-planning/PROJECT.md
  mkdir -p .vbw-planning/phases/01-core/
  touch .vbw-planning/phases/01-core/01-01-PLAN.md
  touch .vbw-planning/phases/01-core/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-core/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/archive-uat-guard.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"active-phase UAT"* ]]
}

@test "prompt-preflight blocks archive even with --skip-audit --force when milestone UAT unresolved" {
  echo "# Project" > .vbw-planning/PROJECT.md
  mkdir -p .vbw-planning/phases
  mkdir -p .vbw-planning/milestones/01-foundation/phases/08-cost-basis/
  echo "# Shipped" > .vbw-planning/milestones/01-foundation/SHIPPED.md
  touch .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-01-PLAN.md
  touch .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-01-SUMMARY.md
  cat > .vbw-planning/milestones/01-foundation/phases/08-cost-basis/08-UAT.md <<'EOF'
---
phase: 08
status: issues_found
---
  - Severity: major
EOF

  INPUT='{"prompt":"/vbw:vibe --archive --skip-audit --force"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("VBW pre-flight block")' >/dev/null
}
