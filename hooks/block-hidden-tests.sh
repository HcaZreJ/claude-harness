#!/bin/bash
# PreToolUse hook: blocks Read/Glob/Grep access to tests/hidden/ paths
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

# Extract the relevant path field based on tool type
PATH_TO_CHECK=""
case "$TOOL_NAME" in
  Read)
    PATH_TO_CHECK=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    ;;
  Glob)
    PATH_TO_CHECK=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty')
    GLOB_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty')
    PATH_TO_CHECK="$PATH_TO_CHECK $GLOB_PATH"
    ;;
  Grep)
    PATH_TO_CHECK=$(echo "$INPUT" | jq -r '.tool_input.path // empty')
    GLOB_FIELD=$(echo "$INPUT" | jq -r '.tool_input.glob // empty')
    PATH_TO_CHECK="$PATH_TO_CHECK $GLOB_FIELD"
    ;;
esac

# Block if any path references tests/hidden (case-insensitive: Swift repos use Tests/hidden)
if echo "$PATH_TO_CHECK" | grep -qi 'tests/hidden'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny"
    },
    systemMessage: "BLOCKED: Hidden test files 不可读取。使用 bash ~/.claude/scripts/run-hidden-tests.sh <repo-root> [function] 来获取 pass/fail 数量。"
  }'
  exit 0
fi

exit 0
