#!/usr/bin/env bash
set -euo pipefail

# verify-plan-filename-convention.sh — Tests for deterministic plan filename enforcement (#151)

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

cleanup() {
  rm -rf "$TMPDIR_TEST" 2>/dev/null || true
}
trap cleanup EXIT

TMPDIR_TEST=$(mktemp -d)

echo "=== Plan Filename Convention Tests ==="

# --- file-guard tests ---
echo ""
echo "file-guard.sh:"

# Test 1: file-guard blocks type-first PLAN name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01.md (type-first)"
else
  fail "blocks PLAN-01.md — got rc=$RC, output: $OUTPUT"
fi

# Test 2: file-guard blocks type-first SUMMARY name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/SUMMARY-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks SUMMARY-01.md (type-first)"
else
  fail "blocks SUMMARY-01.md — got rc=$RC, output: $OUTPUT"
fi

# Test 3: file-guard blocks type-first CONTEXT name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/CONTEXT-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks CONTEXT-01.md (type-first)"
else
  fail "blocks CONTEXT-01.md — got rc=$RC, output: $OUTPUT"
fi

# Test 4: file-guard allows number-first PLAN name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/01-PLAN.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "allows 01-PLAN.md (number-first)"
else
  fail "allows 01-PLAN.md — got rc=$RC, output: $OUTPUT"
fi

# Test 5: file-guard allows number-first SUMMARY name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/01-SUMMARY.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "allows 01-SUMMARY.md (number-first)"
else
  fail "allows 01-SUMMARY.md — got rc=$RC, output: $OUTPUT"
fi

# --- normalize-plan-filenames tests ---
echo ""
echo "normalize-plan-filenames.sh:"
NORM_SCRIPT="$SCRIPT_DIR/scripts/normalize-plan-filenames.sh"

# Test 6: renames type-first to number-first
TDIR="$TMPDIR_TEST/test6"
mkdir -p "$TDIR"
echo "plan1" > "$TDIR/PLAN-01.md"
echo "plan2" > "$TDIR/PLAN-02.md"
echo "summary" > "$TDIR/PLAN-01-SUMMARY.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ] && [ -f "$TDIR/02-PLAN.md" ] && [ -f "$TDIR/01-SUMMARY.md" ]; then
  pass "renames PLAN-01.md → 01-PLAN.md, PLAN-02.md → 02-PLAN.md, PLAN-01-SUMMARY.md → 01-SUMMARY.md"
else
  fail "rename — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 7: renames SUMMARY-NN.md
TDIR="$TMPDIR_TEST/test7"
mkdir -p "$TDIR"
echo "summary" > "$TDIR/SUMMARY-03.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/03-SUMMARY.md" ]; then
  pass "renames SUMMARY-03.md → 03-SUMMARY.md"
else
  fail "SUMMARY rename — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 8: renames CONTEXT-NN.md
TDIR="$TMPDIR_TEST/test8"
mkdir -p "$TDIR"
echo "context" > "$TDIR/CONTEXT-01.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-CONTEXT.md" ]; then
  pass "renames CONTEXT-01.md → 01-CONTEXT.md"
else
  fail "CONTEXT rename — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 9: idempotent on correct names
TDIR="$TMPDIR_TEST/test9"
mkdir -p "$TDIR"
echo "plan" > "$TDIR/01-PLAN.md"
echo "summary" > "$TDIR/01-SUMMARY.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ] && [ -f "$TDIR/01-SUMMARY.md" ] && [ -z "$OUTPUT" ]; then
  pass "idempotent on correct names (no output, no renames)"
else
  fail "idempotent — rc=$RC, output: '$OUTPUT'"
fi

# Test 10: handles collision (both PLAN-01.md and 01-PLAN.md exist)
TDIR="$TMPDIR_TEST/test10"
mkdir -p "$TDIR"
echo "correct" > "$TDIR/01-PLAN.md"
echo "misnamed" > "$TDIR/PLAN-01.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
CONTENT=$(cat "$TDIR/01-PLAN.md")
if [ "$RC" -eq 0 ] && [ "$CONTENT" = "correct" ] && echo "$OUTPUT" | grep -q "skipped"; then
  pass "collision: skips PLAN-01.md when 01-PLAN.md exists"
else
  fail "collision — rc=$RC, content: $CONTENT, output: $OUTPUT"
fi

# Test 11: empty/missing dir exits 0
OUTPUT=$(bash "$NORM_SCRIPT" "$TMPDIR_TEST/nonexistent" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "exits 0 for nonexistent directory"
else
  fail "nonexistent dir — got rc=$RC"
fi

# --- phase-detect misnamed_plans diagnostic ---
echo ""
echo "phase-detect.sh misnamed_plans diagnostic:"

# Test 12: detects misnamed plans
TDIR="$TMPDIR_TEST/test12"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-01.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=true"; then
  pass "phase-detect reports misnamed_plans=true"
else
  fail "phase-detect misnamed — output missing misnamed_plans=true"
fi

# Test 13: clean names report false
TDIR="$TMPDIR_TEST/test13"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/01-PLAN.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=false"; then
  pass "phase-detect reports misnamed_plans=false for clean names"
else
  fail "phase-detect clean — output missing misnamed_plans=false"
fi

# --- Uppercase extension (.MD) tests ---
echo ""
echo "Uppercase extension (.MD) handling:"

# Test 14: file-guard blocks uppercase PLAN-01.MD
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01.MD"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01.MD (uppercase extension)"
else
  fail "blocks PLAN-01.MD — got rc=$RC, output: $OUTPUT"
fi

# Test 15: file-guard blocks mixed-case SUMMARY-01.Md
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/SUMMARY-01.Md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks SUMMARY-01.Md (mixed-case extension)"
else
  fail "blocks SUMMARY-01.Md — got rc=$RC, output: $OUTPUT"
fi

# Test 16: normalize handles uppercase PLAN-01.MD (normalizes extension to lowercase)
TDIR="$TMPDIR_TEST/test16"
mkdir -p "$TDIR"
echo "plan" > "$TDIR/PLAN-01.MD"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ]; then
  pass "renames PLAN-01.MD → 01-PLAN.md (normalizes extension to lowercase)"
else
  fail "uppercase rename — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 17: phase-detect catches uppercase PLAN-01.MD
TDIR="$TMPDIR_TEST/test17"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-01.MD"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=true"; then
  pass "phase-detect catches uppercase PLAN-01.MD"
else
  fail "phase-detect uppercase — output missing misnamed_plans=true"
fi

# --- PLAN-NN-CONTEXT compound form test ---
echo ""
echo "Compound form handling:"

# Test 18: normalize handles PLAN-01-CONTEXT.md → 01-CONTEXT.md
TDIR="$TMPDIR_TEST/test18"
mkdir -p "$TDIR"
echo "context" > "$TDIR/PLAN-01-CONTEXT.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-CONTEXT.md" ] && [ ! -f "$TDIR/01-PLAN.md" ]; then
  pass "renames PLAN-01-CONTEXT.md → 01-CONTEXT.md (not 01-PLAN.md)"
else
  fail "PLAN-NN-CONTEXT compound — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 19: normalize handles PLAN-02-SUMMARY.md alongside PLAN-02-CONTEXT.md
TDIR="$TMPDIR_TEST/test19"
mkdir -p "$TDIR"
echo "summary" > "$TDIR/PLAN-02-SUMMARY.md"
echo "context" > "$TDIR/PLAN-02-CONTEXT.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/02-SUMMARY.md" ] && [ -f "$TDIR/02-CONTEXT.md" ] && [ ! -f "$TDIR/02-PLAN.md" ]; then
  pass "renames both PLAN-02-SUMMARY.md and PLAN-02-CONTEXT.md correctly"
else
  fail "compound pair — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# --- file-guard precision tests ---
echo ""
echo "File-guard precision (false-positive prevention):"

# Test 20: file-guard allows plan-01-review.md (arbitrary name, not a plan)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/plan-01-review.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "allows plan-01-review.md (not a type-first pattern)"
else
  fail "plan-01-review.md — got rc=$RC, output: $OUTPUT"
fi

# Test 21: file-guard allows summary-1custom.md (digits followed by letters)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/summary-1custom.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "allows summary-1custom.md (not a strict type-first pattern)"
else
  fail "summary-1custom.md — got rc=$RC, output: $OUTPUT"
fi

# Test 22: file-guard still blocks PLAN-01-SUMMARY.md (compound type-first)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01-SUMMARY.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01-SUMMARY.md (compound type-first)"
else
  fail "PLAN-01-SUMMARY.md — got rc=$RC, output: $OUTPUT"
fi

# Test 23: file-guard still blocks PLAN-01-CONTEXT.md (compound type-first)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01-CONTEXT.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01-CONTEXT.md (compound type-first)"
else
  fail "PLAN-01-CONTEXT.md — got rc=$RC, output: $OUTPUT"
fi

echo ""
echo "==============================="
echo "Plan filename convention: $PASS passed, $FAIL failed"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1
