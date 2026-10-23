#!/bin/bash
# Tests for hooks/block-absolute-paths.sh (PreToolUse Write/Edit hook).
# 只检查 git 仓库里、.claude/ 之外（worktree 代码照查）的代码文件；其余放行。
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../block-absolute-paths.sh"
ROOT="$HOME/.cache/hook-test-abs-$$"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/repo/src" "$ROOT/repo/.claude/plans" "$ROOT/repo/.claude/worktrees/wt/src" "$ROOT/plain"
git -C "$ROOT/repo" init -q
FAILURES=0
ABS='open("/Users/someone/data.csv")'
run() { # name file content expected_exit
  local out code
  out=$(jq -n --arg f "$2" --arg c "$3" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}' | bash "$HOOK" 2>&1); code=$?
  if [ "$code" = "$4" ]; then echo "  [PASS] $1"; else echo "  [FAIL] $1 (exit $code, want $4)"; FAILURES=$((FAILURES+1)); fi
}
run "仓库代码写绝对路径 → 拦" "$ROOT/repo/src/a.py" "$ABS" 2
run "仓库代码不含绝对路径 → 放行" "$ROOT/repo/src/a.py" 'x = 1' 0
run "worktree 里的代码写绝对路径 → 拦" "$ROOT/repo/.claude/worktrees/wt/src/a.py" "$ABS" 2
run "仓库 .claude/ 配置 → 放行" "$ROOT/repo/.claude/plans/x.json" "$ABS" 0
run "~/.claude/ 下的文件 → 放行" "$HOME/.claude/hooks/zz-probe.sh" "$ABS" 0
run "/tmp 下的文件 → 放行" "/tmp/zz-probe.py" "$ABS" 0
run "不在 git 仓库里的文件 → 放行" "$ROOT/plain/a.py" "$ABS" 0
run "仓库里的非代码文件 → 放行" "$ROOT/repo/README.md" "$ABS" 0
[ "$FAILURES" -eq 0 ] && echo "ALL PASS" || { echo "$FAILURES FAILED"; exit 1; }
