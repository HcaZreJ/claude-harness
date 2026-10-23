#!/bin/bash
# PreToolUse hook: BLOCKS Write/Edit if absolute local paths are detected in code files.
# Agent sees the block and must fix to repo-relative paths before retrying.
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check code/config files
if ! echo "$FILE_PATH" | grep -qE '\.(py|js|ts|tsx|go|rs|java|yaml|yml|toml|json|sh)$'; then
  exit 0
fi

# Only check files inside a git repo and outside .claude/ (worktree code under .claude/worktrees/ is still checked).
# Temp dirs, ~/.claude/, a repo's own .claude/ config and scratchpads, and files outside any repo pass.
case "$FILE_PATH" in
  /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) exit 0 ;;
esac
REL="$FILE_PATH"
case "$REL" in
  */.claude/worktrees/*) REL="${REL#*/.claude/worktrees/}"; REL="${REL#*/}" ;;
esac
case "$REL" in
  .claude/*|*/.claude/*) exit 0 ;;
esac
DIR=$(dirname "$FILE_PATH")
while [ ! -d "$DIR" ] && [ "$DIR" != "/" ]; do DIR=$(dirname "$DIR"); done
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Extract new content based on tool type
case "$TOOL_NAME" in
  Write)
    NEW_TEXT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
    ;;
  Edit)
    NEW_TEXT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
    ;;
  *)
    exit 0
    ;;
esac

# Check for hardcoded absolute local paths
if echo "$NEW_TEXT" | grep -qE '/Users/[a-zA-Z]|/home/[a-zA-Z]|C:\\\\Users'; then
  echo "BLOCKED: 检测到绝对本地路径写入 $FILE_PATH。请改用 repo-relative 路径或环境变量，绝对路径部署到服务器后会 break。" >&2
  exit 2
fi

exit 0
