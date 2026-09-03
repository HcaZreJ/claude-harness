#!/bin/bash
# SessionStart hook: inject the cwd's in-progress plan status into context.
#
# cwd is read from the stdin JSON payload's `cwd` field, never from the
# process's PWD (SessionStart's process PWD is unreliable). Only
# $cwd/.claude/plans is scanned, at depth 1 — worktrees live under
# .claude/worktrees/ and every repo sits under ~/Documents, so recursing
# would scan the entire tree. Any error path falls through to a silent
# exit 0 so a broken hook can never block session startup.

# 直接在终端运行（无管道喂入 JSON）时给出用法，避免 cat 空等 stdin
if [ -t 0 ]; then
  echo "用法: 由 Claude Code 作为 hook 调用，JSON 从 stdin 传入。"
  echo "手工验证示例:"
  echo "  echo '{\"cwd\":\"/path/to/repo\"}' | bash $0"
  exit 0
fi

# stdin 无数据时最多等 2 秒，避免手工运行时无限期挂起
INPUT=$( (timeout 2 cat 2>/dev/null || true) )
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

if [ -z "$CWD" ] || [ "$CWD" = "null" ]; then
  exit 0
fi

PLANS_DIR="$CWD/.claude/plans"

if [ ! -d "$PLANS_DIR" ]; then
  exit 0
fi

FILES=$(find "$PLANS_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)

if [ -z "$FILES" ]; then
  exit 0
fi

ENTRIES=()

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ "${#ENTRIES[@]}" -ge 5 ] && break

  # A plan only has a "Status" field if it carries a "## Status" heading.
  # Scan the section under that heading (up to the next "## " heading or
  # EOF) for a recognized value; anything else counts as "no Status field"
  # per spec and is excluded.
  STATUS=$(awk '
    /^## Status/ { infield=1; next }
    infield && /^## / { infield=0 }
    infield && /In Progress/ { print "In Progress"; exit }
    infield && /Completed/ { print "Completed"; exit }
  ' "$f" 2>/dev/null)

  if [ "$STATUS" != "In Progress" ]; then
    continue
  fi

  TITLE=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# *//')
  if [ -z "$TITLE" ]; then
    TITLE=$(basename "$f" .md)
  fi

  ENTRIES+=("- $(basename "$f"): $TITLE [In Progress]")
done <<< "$FILES"

if [ "${#ENTRIES[@]}" -eq 0 ]; then
  exit 0
fi

CONTEXT="In-progress plans in this repo:"
for line in "${ENTRIES[@]}"; do
  CONTEXT="$CONTEXT
$line"
done

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}' 2>/dev/null

exit 0
