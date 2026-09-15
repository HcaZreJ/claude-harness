#!/bin/bash
# SessionStart hook: inject the cwd's plan-directory status into context.
#
# Contract with .claude/plans/: a plan file lives there only while its work is
# unfinished (In Progress / Paused / Draft / Planned / Ready). Completed plans
# are deleted on wrap-up — git history is the archive — so every file found
# here is worth surfacing: active ones by status, finished-but-undeleted ones
# as a cleanup reminder, and files whose "## Status" section is missing or
# unrecognizable as contract violations to fix.
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
DONE_NAMES=()

while IFS= read -r f; do
  [ -z "$f" ] && continue

  # Scan the section under "## Status" (up to the next "## " heading or EOF).
  # Rule order matters: "In Progress" wins over "Completed" when a line
  # mentions both (e.g. "In Progress——P1 已完成").
  STATUS=$(awk '
    /^## Status/ { infield=1; next }
    infield && /^## / { infield=0 }
    infield && /In Progress/ { print "In Progress"; exit }
    infield && /Paused/ { print "Paused"; exit }
    infield && /Draft/ { print "Draft"; exit }
    infield && /Planned/ { print "Planned"; exit }
    infield && /Ready/ { print "Ready"; exit }
    infield && /Completed|Implemented|Superseded|Done/ { print "DONE"; exit }
  ' "$f" 2>/dev/null)

  BASE=$(basename "$f")

  if [ "$STATUS" = "DONE" ]; then
    DONE_NAMES+=("$BASE")
    continue
  fi

  [ "${#ENTRIES[@]}" -ge 8 ] && continue

  TITLE=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# *//')
  if [ -z "$TITLE" ]; then
    TITLE=$(basename "$f" .md)
  fi

  if [ -z "$STATUS" ]; then
    ENTRIES+=("- $BASE: $TITLE [Status 段缺失或值不规范——先补 ## Status，已完成的按约定删除]")
  else
    ENTRIES+=("- $BASE: $TITLE [$STATUS]")
  fi
done <<< "$FILES"

if [ "${#ENTRIES[@]}" -eq 0 ] && [ "${#DONE_NAMES[@]}" -eq 0 ]; then
  exit 0
fi

CONTEXT="Plans in this repo (.claude/plans/):"
for line in "${ENTRIES[@]}"; do
  CONTEXT="$CONTEXT
$line"
done

if [ "${#DONE_NAMES[@]}" -gt 0 ]; then
  CONTEXT="$CONTEXT
- 另有 ${#DONE_NAMES[@]} 个已完成的 plan 未删除（约定=完成即删，git 历史承载）: ${DONE_NAMES[*]}"
fi

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}' 2>/dev/null

exit 0
