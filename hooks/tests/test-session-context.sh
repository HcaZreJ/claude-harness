#!/bin/bash
# Tests for hooks/session-context.sh (SessionStart hook).
#
# The hook surfaces every file in the cwd's .claude/plans/: active plans by
# status, finished-but-undeleted ones as a cleanup reminder, and files with a
# missing or unrecognizable "## Status" section as contract violations.
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

# Run the hook against a cwd and echo the injected context; returns non-zero
# when the hook itself exits non-zero.
run_hook_context() {
  local cwd="$1" output exit_code
  output=$(make_input "$cwd" | "$HOOK")
  exit_code=$?
  [ "$exit_code" -ne 0 ] && return "$exit_code"
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# --- test_session_context_active_statuses_shown ---
# Every unfinished status the plan contract allows is listed with its label.
test_session_context_active_statuses_shown() {
  local name="test_session_context_active_statuses_shown"
  local cwd="$TEST_ROOT/repo1"
  mkdir -p "$cwd/.claude/plans"
  write_plan "$cwd/.claude/plans/a-inprogress.md" "Feature: alpha" "In Progress — waiting on review"
  write_plan "$cwd/.claude/plans/b-paused.md"     "Feature: bravo" "Paused"
  write_plan "$cwd/.claude/plans/c-draft.md"      "Feature: charlie" "Draft"
  write_plan "$cwd/.claude/plans/d-planned.md"    "Feature: delta" "Planned"
  write_plan "$cwd/.claude/plans/e-ready.md"      "Feature: echo" "Ready"

  local ctx
  ctx=$(run_hook_context "$cwd") || { fail "$name (hook exited non-zero)"; return; }

  local missing=""
  grep -q 'a-inprogress.md: Feature: alpha \[In Progress\]' <<< "$ctx" || missing="$missing In Progress;"
  grep -q 'b-paused.md: Feature: bravo \[Paused\]'          <<< "$ctx" || missing="$missing Paused;"
  grep -q 'c-draft.md: Feature: charlie \[Draft\]'          <<< "$ctx" || missing="$missing Draft;"
  grep -q 'd-planned.md: Feature: delta \[Planned\]'        <<< "$ctx" || missing="$missing Planned;"
  grep -q 'e-ready.md: Feature: echo \[Ready\]'             <<< "$ctx" || missing="$missing Ready;"

  if [ -z "$missing" ]; then
    pass "$name"
  else
    fail "$name (missing or mislabeled:$missing): $ctx"
  fi
}

# --- test_session_context_completed_plans_flagged_for_cleanup ---
# Finished plans should have been deleted; the ones still on disk are named
# so the session can clean them up, and they never occupy an active entry.
test_session_context_completed_plans_flagged_for_cleanup() {
  local name="test_session_context_completed_plans_flagged_for_cleanup"
  local cwd="$TEST_ROOT/repo2"
  mkdir -p "$cwd/.claude/plans"
  write_plan "$cwd/.claude/plans/done1.md" "Feature: done one"   "Completed"
  write_plan "$cwd/.claude/plans/done2.md" "Feature: done two"   "Implemented"
  write_plan "$cwd/.claude/plans/done3.md" "Feature: done three" "Superseded"
  write_plan "$cwd/.claude/plans/done4.md" "Feature: done four"  "Done"

  local ctx
  ctx=$(run_hook_context "$cwd") || { fail "$name (hook exited non-zero)"; return; }

  local problems=""
  grep -q '4 个已完成的 plan 未删除' <<< "$ctx" || problems="$problems 未报出数量;"
  for f in done1.md done2.md done3.md done4.md; do
    grep -q "$f" <<< "$ctx" || problems="$problems 未点名 $f;"
  done
  # A finished plan is a cleanup item, never an active entry.
  grep -q '^- done1.md: Feature: done one \[' <<< "$ctx" && problems="$problems done1 被当成活跃 plan;"

  if [ -z "$problems" ]; then
    pass "$name"
  else
    fail "$name ($problems): $ctx"
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

# --- test_session_context_truncates_at_eight ---
test_session_context_truncates_at_eight() {
  local name="test_session_context_truncates_at_eight"
  local cwd="$TEST_ROOT/repo4"
  mkdir -p "$cwd/.claude/plans"
  for i in 01 02 03 04 05 06 07 08 09 10; do
    write_plan "$cwd/.claude/plans/plan-$i.md" "Feature: plan $i" "In Progress"
  done

  local ctx
  ctx=$(run_hook_context "$cwd") || { fail "$name (hook exited non-zero)"; return; }

  local listed_count
  listed_count=$(grep -oE 'plan-[0-9]{2}\.md' <<< "$ctx" | sort -u | wc -l | tr -d ' ')

  local line_count
  line_count=$(printf '%s' "$ctx" | wc -l | tr -d ' ')
  # printf without trailing newline undercounts by one line; normalize
  line_count=$((line_count + 1))

  if [ "$listed_count" -eq 8 ] && [ "$line_count" -le 20 ]; then
    pass "$name (listed=$listed_count lines=$line_count)"
  else
    fail "$name (expected exactly 8 entries and <=20 lines, got listed=$listed_count lines=$line_count): $ctx"
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

# --- test_session_context_no_status_field_flagged ---
# A plan with no readable "## Status" breaks the contract; surface it to fix.
test_session_context_no_status_field_flagged() {
  local name="test_session_context_no_status_field_flagged"
  local cwd="$TEST_ROOT/repo5"
  mkdir -p "$cwd/.claude/plans"
  write_plan "$cwd/.claude/plans/nostatus.md" "Feature: no status" ""
  write_plan "$cwd/.claude/plans/badstatus.md" "Feature: bad status" "进行中"

  local ctx
  ctx=$(run_hook_context "$cwd") || { fail "$name (hook exited non-zero)"; return; }

  local problems=""
  grep -q 'nostatus.md: Feature: no status \[Status 段缺失或值不规范' <<< "$ctx" \
    || problems="$problems 缺 Status 的 plan 未报;"
  grep -q 'badstatus.md: Feature: bad status \[Status 段缺失或值不规范' <<< "$ctx" \
    || problems="$problems Status 值不规范的 plan 未报;"

  if [ -z "$problems" ]; then
    pass "$name"
  else
    fail "$name ($problems): $ctx"
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

test_session_context_active_statuses_shown
test_session_context_completed_plans_flagged_for_cleanup
test_session_context_no_claude_dir
test_session_context_empty_plans_dir
test_session_context_truncates_at_eight
test_session_context_malformed_json_input
test_session_context_no_status_field_flagged
test_session_context_never_recurses

echo
echo "session-context.sh: $PASS_COUNT passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]
