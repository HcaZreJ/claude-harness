#!/bin/bash
# Tests for hooks/session-context.sh (SessionStart hook).
# Derived from the spec in .claude/plans/harness-slimming.md (### W3 硬约束).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../session-context.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

FAILURES=0
PASS_COUNT=0

pass() {
  echo "  [PASS] $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "  [FAIL] $1"
  FAILURES=$((FAILURES + 1))
}

# Build a SessionStart hook stdin payload with a given cwd.
make_input() {
  local cwd="$1"
  jq -n --arg cwd "$cwd" '{session_id: "sess-test", cwd: $cwd, hook_event_name: "SessionStart", source: "startup"}'
}

write_plan() {
  # write_plan <path> <title> <status_line_or_empty>
  local path="$1" title="$2" status="$3"
  mkdir -p "$(dirname "$path")"
  {
    echo "# $title"
    echo
    echo "## Overview"
    echo "some body text"
    echo
    if [ -n "$status" ]; then
      echo "## Status"
      echo "$status"
    fi
  } > "$path"
}

# --- test_session_context_in_progress_plan_shown ---
test_session_context_in_progress_plan_shown() {
  local name="test_session_context_in_progress_plan_shown"
  local cwd="$TEST_ROOT/repo1"
  mkdir -p "$cwd/.claude/plans"
  write_plan "$cwd/.claude/plans/foo.md" "Feature: foo bar" "In Progress — waiting on review"

  local output exit_code
  output=$(make_input "$cwd" | "$HOOK")
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    fail "$name (expected exit 0, got $exit_code)"
    return
  fi

  if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' > /dev/null 2>&1; then
    local ctx
    ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
    if echo "$ctx" | grep -q "foo.md" && echo "$ctx" | grep -q "Feature: foo bar" && echo "$ctx" | grep -q "In Progress"; then
      pass "$name"
    else
      fail "$name (context missing expected fields): $ctx"
    fi
  else
    fail "$name (no additionalContext produced): $output"
  fi
}

# --- test_session_context_all_completed_hidden ---
test_session_context_all_completed_hidden() {
  local name="test_session_context_all_completed_hidden"
  local cwd="$TEST_ROOT/repo2"
  mkdir -p "$cwd/.claude/plans"
  write_plan "$cwd/.claude/plans/done1.md" "Feature: done one" "Completed"
  write_plan "$cwd/.claude/plans/done2.md" "Feature: done two" "Completed"

  local output exit_code
  output=$(make_input "$cwd" | "$HOOK")
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    fail "$name (expected exit 0, got $exit_code)"
    return
  fi

  if [ -z "$output" ]; then
    pass "$name"
  else
    fail "$name (expected silent/empty output, got): $output"
  fi
}

# --- test_session_context_no_claude_dir ---
test_session_context_no_claude_dir() {
  local name="test_session_context_no_claude_dir"
  local cwd="$TEST_ROOT/documents_stand_in"
  mkdir -p "$cwd"

  local output exit_code
  output=$(make_input "$cwd" | "$HOOK")
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    fail "$name (expected exit 0, got $exit_code)"
    return
  fi

  if [ -z "$output" ]; then
    pass "$name"
  else
    fail "$name (expected empty output for missing .claude dir), got: $output"
  fi
}

# --- test_session_context_empty_plans_dir ---
test_session_context_empty_plans_dir() {
  local name="test_session_context_empty_plans_dir"
  local cwd="$TEST_ROOT/repo3"
  mkdir -p "$cwd/.claude/plans"

  local output exit_code
  output=$(make_input "$cwd" | "$HOOK")
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    fail "$name (expected exit 0, got $exit_code)"
    return
  fi

  if [ -z "$output" ]; then
    pass "$name"
  else
    fail "$name (expected empty output for empty plans dir), got: $output"
  fi
}

# --- test_session_context_truncates_at_five ---
test_session_context_truncates_at_five() {
  local name="test_session_context_truncates_at_five"
  local cwd="$TEST_ROOT/repo4"
  mkdir -p "$cwd/.claude/plans"
  for i in 1 2 3 4 5 6 7; do
    write_plan "$cwd/.claude/plans/plan-0$i.md" "Feature: plan $i" "In Progress"
  done

  local output exit_code
  output=$(make_input "$cwd" | "$HOOK")
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    fail "$name (expected exit 0, got $exit_code)"
    return
  fi

  local ctx
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  local listed_count
  listed_count=$(echo "$ctx" | grep -oE 'plan-0[0-9]\.md' | sort -u | wc -l | tr -d ' ')

  local line_count
  line_count=$(printf '%s' "$ctx" | wc -l | tr -d ' ')
  # printf without trailing newline undercounts by one line; normalize
  line_count=$((line_count + 1))

  if [ "$listed_count" -eq 5 ] && [ "$line_count" -le 20 ]; then
    pass "$name (listed=$listed_count lines=$line_count)"
  else
    fail "$name (expected exactly 5 entries and <=20 lines, got listed=$listed_count lines=$line_count): $ctx"
  fi
}

# --- test_session_context_malformed_json_input ---
test_session_context_malformed_json_input() {
  local name="test_session_context_malformed_json_input"

  local output exit_code
  output=$(echo '{not valid json,,,' | "$HOOK")
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    fail "$name (expected exit 0, got $exit_code)"
    return
  fi

  if [ -z "$output" ]; then
    pass "$name"
  else
    fail "$name (expected empty output for malformed JSON), got: $output"
  fi
}

# --- test_session_context_no_status_field_not_listed ---
test_session_context_no_status_field_not_listed() {
  local name="test_session_context_no_status_field_not_listed"
  local cwd="$TEST_ROOT/repo5"
  mkdir -p "$cwd/.claude/plans"
  write_plan "$cwd/.claude/plans/nostatus.md" "Feature: no status" ""

  local output exit_code
  output=$(make_input "$cwd" | "$HOOK")
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    fail "$name (expected exit 0, got $exit_code)"
    return
  fi

  if [ -z "$output" ]; then
    pass "$name"
  else
    fail "$name (expected plan with no Status field to be excluded), got: $output"
  fi
}

# --- test_session_context_never_recurses ---
test_session_context_never_recurses() {
  local name="test_session_context_never_recurses"
  local cwd="$TEST_ROOT/repo6"
  mkdir -p "$cwd/.claude/plans/nested"
  write_plan "$cwd/.claude/plans/nested/deep.md" "Feature: deep nested" "In Progress"

  local output exit_code
  output=$(make_input "$cwd" | "$HOOK")
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    fail "$name (expected exit 0, got $exit_code)"
    return
  fi

  if [ -z "$output" ]; then
    pass "$name"
  else
    fail "$name (expected nested plan to be ignored, depth must be 1), got: $output"
  fi
}

test_session_context_in_progress_plan_shown
test_session_context_all_completed_hidden
test_session_context_no_claude_dir
test_session_context_empty_plans_dir
test_session_context_truncates_at_five
test_session_context_malformed_json_input
test_session_context_no_status_field_not_listed
test_session_context_never_recurses

echo
echo "session-context.sh: $PASS_COUNT passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]
