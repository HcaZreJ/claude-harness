#!/bin/bash
# SessionStart hook: inject the cwd's plan-directory status into context.
#
# Contract with .claude/plans/: a plan file lives there only while its work is
# unfinished (In Progress / Paused / Draft / Planned / Ready, or 进行中 / 暂停 /
# 草稿 / 未开始 / 待用户验收). Completed plans
# are deleted on wrap-up — git history is the archive — so every file found
# here is worth surfacing: active ones by status, finished-but-undeleted ones
# as a cleanup reminder, and the rest with whatever their Status says. Only the first 8 active plans
# get expanded entries (context economy); the rest are still named in an
# overflow line — a plan must never silently vanish from the session's view.
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
OVERFLOW_NAMES=()

while IFS= read -r f; do
  [ -z "$f" ] && continue

  # Scan the section under "## Status" (up to the next "## " heading or EOF).
  # Rule order matters: an active status wins over a finished one when a line
  # mentions both (e.g. "进行中。plan 01 已完成"). With no status word anywhere
  # in the section, its first non-empty line is shown verbatim.
  STATUS=$(awk '
    /^## Status/ { infield=1; next }
    infield && /^## / { infield=0 }
    infield && /In Progress/ { print "In Progress"; found=1; exit }
    infield && /进行中/ { print "进行中"; found=1; exit }
    infield && /Paused/ { print "Paused"; found=1; exit }
    infield && /暂停/ { print "暂停"; found=1; exit }
    infield && /Draft/ { print "Draft"; found=1; exit }
    infield && /草稿/ { print "草稿"; found=1; exit }
    infield && /Planned/ { print "Planned"; found=1; exit }
    infield && /未开始/ { print "未开始"; found=1; exit }
    infield && /Ready/ { print "Ready"; found=1; exit }
    infield && /待用户验收/ { print "待用户验收"; found=1; exit }
    infield && /Completed|Implemented|Superseded|Done|已完成|已废弃/ { print "DONE"; found=1; exit }
    infield && NF && first == "" { first = $0 }
    END { if (!found && first != "") print "RAW:" first }
  ' "$f" 2>/dev/null)

  BASE=$(basename "$f")

  if [ "$STATUS" = "DONE" ]; then
    DONE_NAMES+=("$BASE")
    continue
  fi

  if [ "${#ENTRIES[@]}" -ge 8 ]; then
    OVERFLOW_NAMES+=("$BASE")
    continue
  fi

  TITLE=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# *//')
  if [ -z "$TITLE" ]; then
    TITLE=$(basename "$f" .md)
  fi

  if [ -z "$STATUS" ]; then
    ENTRIES+=("- $BASE: $TITLE [无 Status 段]")
  elif [ "${STATUS#RAW:}" != "$STATUS" ]; then
    ENTRIES+=("- $BASE: $TITLE [${STATUS#RAW:}]")
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

if [ "${#OVERFLOW_NAMES[@]}" -gt 0 ]; then
  CONTEXT="$CONTEXT
- 另有 ${#OVERFLOW_NAMES[@]} 个进行中的 plan 未展开（读文件取 Status）: ${OVERFLOW_NAMES[*]}"
fi

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
