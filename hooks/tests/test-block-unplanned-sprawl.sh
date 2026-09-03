#!/bin/bash
# Tests for hooks/block-unplanned-sprawl.sh (PreToolUse hook, matcher Write|Edit).
# Derived from the spec in .claude/plans/harness-slimming.md (### W3 硬约束).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../block-unplanned-sprawl.sh"

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

# fresh, isolated log dir per test invocation so session counters never leak
new_log_dir() {
  mktemp -d "$TEST_ROOT/logs.XXXXXX"
}

# make_input <tool_name> <session_id> <file_path>
make_input() {
  local tool="$1" session="$2" file="$3"
  jq -n --arg tool "$tool" --arg session "$session" --arg file "$file" \
    '{session_id: $session, cwd: "/tmp", hook_event_name: "PreToolUse", tool_name: $tool, tool_input: {file_path: $file, content: "x"}}'
}

run_hook() {
  local logdir="$1" tool="$2" session="$3" file="$4"
  SPRAWL_LOG_DIR="$logdir" SPRAWL_MAX_FILES="${MAX_FILES:-3}" "$HOOK" < <(make_input "$tool" "$session" "$file")
}

# --- test_block_unplanned_sprawl_first_two_files_allowed ---
test_block_unplanned_sprawl_first_two_files_allowed() {
  local name="test_block_unplanned_sprawl_first_two_files_allowed"
  local logdir; logdir=$(new_log_dir)
  local session="sess-A"

  run_hook "$logdir" Write "$session" "/tmp/proj/file1.py" > /dev/null 2>&1
  local c1=$?
  run_hook "$logdir" Edit "$session" "/tmp/proj/file2.py" > /dev/null 2>&1
  local c2=$?

  if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (expected both exit 0, got $c1 and $c2)"
  fi
}

# --- test_block_unplanned_sprawl_third_file_rejected ---
test_block_unplanned_sprawl_third_file_rejected() {
  local name="test_block_unplanned_sprawl_third_file_rejected"
  local logdir; logdir=$(new_log_dir)
  local session="sess-B"

  run_hook "$logdir" Write "$session" "/tmp/proj/file1.py" > /dev/null 2>&1
  run_hook "$logdir" Edit "$session" "/tmp/proj/file2.py" > /dev/null 2>&1

  local stderr_out exit_code
  stderr_out=$(run_hook "$logdir" Write "$session" "/tmp/proj/file3.py" 2>&1 1>/dev/null)
  exit_code=$?

  if [ "$exit_code" -eq 2 ] && echo "$stderr_out" | grep -qi "BLOCKED"; then
    pass "$name"
  else
    fail "$name (expected exit 2 with BLOCKED message, got exit=$exit_code stderr='$stderr_out')"
  fi
}

# --- test_block_unplanned_sprawl_repeated_file_counts_once ---
test_block_unplanned_sprawl_repeated_file_counts_once() {
  local name="test_block_unplanned_sprawl_repeated_file_counts_once"
  local logdir; logdir=$(new_log_dir)
  local session="sess-C"

  run_hook "$logdir" Write "$session" "/tmp/proj/fileA.py" > /dev/null 2>&1
  run_hook "$logdir" Edit  "$session" "/tmp/proj/fileA.py" > /dev/null 2>&1
  run_hook "$logdir" Edit  "$session" "/tmp/proj/fileA.py" > /dev/null 2>&1
  run_hook "$logdir" Write "$session" "/tmp/proj/fileB.py" > /dev/null 2>&1
  local exit_code
  run_hook "$logdir" Edit "$session" "/tmp/proj/fileA.py" > /dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (repeated writes to the same 2 distinct files should never block, got exit=$exit_code)"
  fi
}

# --- test_block_unplanned_sprawl_independent_sessions ---
test_block_unplanned_sprawl_independent_sessions() {
  local name="test_block_unplanned_sprawl_independent_sessions"
  local logdir; logdir=$(new_log_dir)

  run_hook "$logdir" Write "sess-D1" "/tmp/proj/d1-file1.py" > /dev/null 2>&1
  run_hook "$logdir" Edit  "sess-D1" "/tmp/proj/d1-file2.py" > /dev/null 2>&1

  # a brand new session should not be affected by sess-D1's count
  run_hook "$logdir" Write "sess-D2" "/tmp/proj/d2-file1.py" > /dev/null 2>&1
  local c1=$?
  run_hook "$logdir" Edit "sess-D2" "/tmp/proj/d2-file2.py" > /dev/null 2>&1
  local c2=$?

  if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (expected independent session to allow its own first two files, got $c1 and $c2)"
  fi
}

# --- test_block_unplanned_sprawl_malformed_input_allowed ---
test_block_unplanned_sprawl_malformed_input_allowed() {
  local name="test_block_unplanned_sprawl_malformed_input_allowed"
  local logdir; logdir=$(new_log_dir)

  echo '{not valid json,,,' | SPRAWL_LOG_DIR="$logdir" SPRAWL_MAX_FILES=3 "$HOOK" > /dev/null 2>&1
  local exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (expected malformed input to pass through with exit 0, got $exit_code)"
  fi
}

# --- test_block_unplanned_sprawl_unlock_marker_lifts_block ---
test_block_unplanned_sprawl_unlock_marker_lifts_block() {
  local name="test_block_unplanned_sprawl_unlock_marker_lifts_block"
  local logdir; logdir=$(new_log_dir)
  local session="sess-E"

  run_hook "$logdir" Write "$session" "/tmp/proj/e1.py" > /dev/null 2>&1
  run_hook "$logdir" Edit  "$session" "/tmp/proj/e2.py" > /dev/null 2>&1

  # confirm 3rd file is blocked before unlocking
  run_hook "$logdir" Write "$session" "/tmp/proj/e3.py" > /dev/null 2>&1
  local pre_exit=$?

  # feature-workflow skill loaded -> unlock marker created for this session
  touch "$logdir/sprawl-$session.unlocked"

  run_hook "$logdir" Write "$session" "/tmp/proj/e3.py" > /dev/null 2>&1
  local post_exit=$?

  if [ "$pre_exit" -eq 2 ] && [ "$post_exit" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (expected blocked before unlock (got $pre_exit) and allowed after (got $post_exit))"
  fi
}

test_block_unplanned_sprawl_first_two_files_allowed
test_block_unplanned_sprawl_third_file_rejected
test_block_unplanned_sprawl_repeated_file_counts_once
test_block_unplanned_sprawl_independent_sessions
test_block_unplanned_sprawl_default_threshold_is_five() {
  local name="test_block_unplanned_sprawl_default_threshold_is_five"
  local logdir; logdir=$(mktemp -d)
  local session="default-thresh-$$"
  local rc
  # 不设 SPRAWL_MAX_FILES 走默认值：前 4 个文件放行
  for i in 1 2 3 4; do
    SPRAWL_LOG_DIR="$logdir" "$HOOK" < <(make_input "Write" "$session" "/tmp/f$i.py") >/dev/null 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
      fail "$name (第 $i 个文件本应放行, rc=$rc)"; rm -rf "$logdir"; return
    fi
  done
  # 第 5 个被拦
  SPRAWL_LOG_DIR="$logdir" "$HOOK" < <(make_input "Write" "$session" "/tmp/f5.py") >/dev/null 2>&1
  rc=$?
  rm -rf "$logdir"
  if [ "$rc" -eq 2 ]; then pass "$name"; else fail "$name (第 5 个本应被拦, rc=$rc)"; fi
}

test_block_unplanned_sprawl_malformed_input_allowed
test_block_unplanned_sprawl_unlock_marker_lifts_block
test_block_unplanned_sprawl_default_threshold_is_five

echo
echo "block-unplanned-sprawl.sh: $PASS_COUNT passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]
