#!/bin/bash
# PreToolUse hook (matcher: Write|Edit): blocks the Nth distinct file a
# session tries to Write/Edit (N = SPRAWL_MAX_FILES, default 5), prompting
# escalation to the feature-workflow
# skill instead of letting an unplanned change quietly sprawl across files.
#
# Per-session state (list of distinct files already touched, plus an
# unlock marker) lives under $SPRAWL_LOG_DIR (default
# ~/.claude/hooks/logs), keyed by session_id so concurrent sessions never
# share counters. Any read/parse failure falls through to exit 0 — a
# broken hook must never wedge the user.

# 直接在终端运行（无管道喂入 JSON）时给出用法，避免 cat 空等 stdin
if [ -t 0 ]; then
  echo "用法: 由 Claude Code 作为 hook 调用，JSON 从 stdin 传入。"
  echo "手工验证示例:"
  echo "  echo '{\"tool_name\":\"Write\",\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"/tmp/a.py\"}}' | bash $0"
  exit 0
fi

# stdin 无数据时最多等 2 秒，避免手工运行时无限期挂起
INPUT=$( (timeout 2 cat 2>/dev/null || true) )

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

if [ -z "$FILE_PATH" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

MAX_FILES="${SPRAWL_MAX_FILES:-5}"
[[ "$MAX_FILES" =~ ^[0-9]+$ ]] || MAX_FILES=5

LOG_DIR="${SPRAWL_LOG_DIR:-$HOME/.claude/hooks/logs}"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

FILES_LOG="$LOG_DIR/sprawl-$SESSION_ID.files"
UNLOCK_MARKER="$LOG_DIR/sprawl-$SESSION_ID.unlocked"

# feature-workflow skill has been loaded for this session -> guard lifted
if [ -f "$UNLOCK_MARKER" ]; then
  exit 0
fi

touch "$FILES_LOG" 2>/dev/null || exit 0

# a file already counted for this session never re-triggers the count
if grep -qxF "$FILE_PATH" "$FILES_LOG" 2>/dev/null; then
  exit 0
fi

DISTINCT_COUNT=$(wc -l < "$FILES_LOG" 2>/dev/null | tr -d '[:space:]')
[[ "$DISTINCT_COUNT" =~ ^[0-9]+$ ]] || DISTINCT_COUNT=0

if [ "$DISTINCT_COUNT" -ge "$((MAX_FILES - 1))" ]; then
  echo "BLOCKED: 本次会话已写入 $DISTINCT_COUNT 个不同文件，即将触及第 $((DISTINCT_COUNT + 1)) 个（${FILE_PATH}）。加载 feature-workflow skill 判定走轻量路径还是完整流程，然后执行以下命令解除本闸门：
  touch \"$UNLOCK_MARKER\"" >&2
  exit 2
fi

echo "$FILE_PATH" >> "$FILES_LOG"
exit 0
