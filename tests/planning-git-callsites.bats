#!/usr/bin/env bats

load test_helper

@test "planning-git callsites avoid raw CLAUDE_PLUGIN_ROOT path" {
  run bash -c "grep -R -n 'bash \\\${CLAUDE_PLUGIN_ROOT}/scripts/planning-git\\.sh' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git callsites include marketplace fallback" {
  run bash -c "grep -R -n 'plugins/marketplaces/vbw-marketplace/scripts/planning-git.sh' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null | wc -l"
  [ "$status" -eq 0 ]

  local count
  count=$(echo "$output" | tr -d '[:space:]')
  [[ "$count" =~ ^[0-9]+$ ]]
  [ "$count" -ge 8 ]
}

@test "planning-git callsites include cache fallback lookup" {
  run bash -c "grep -R -n 'plugins/cache/vbw-marketplace/vbw' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null | grep 'planning-git.sh' | wc -l"
  [ "$status" -eq 0 ]

  local count
  count=$(echo "$output" | tr -d '[:space:]')
  [[ "$count" =~ ^[0-9]+$ ]]
  [ "$count" -ge 8 ]
}
