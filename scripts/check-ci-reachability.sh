#!/bin/bash
# 报告 repo 里每个测试目录是否被 CI workflow 选中。
# 用法: check-ci-reachability.sh [repo-path]
# 退出码: 0 = 全部可达；1 = 存在不可达的测试目录。
#
# 测试文件清单取自 git ls-files，因此构建产物（.build/）、虚拟环境
# （.venv/、site-packages/）与 node_modules/ 天然不计入。

REPO="${1:-$(pwd)}"
REPO="${REPO%/}"

# `-e` 而非 `-d`：git worktree 里 `.git` 是一个指向主仓库的文件，不是目录。
[ -e "$REPO/.git" ] || { echo "不是 git repo: $REPO"; exit 1; }

echo "CI 可达性检查: $REPO"
echo

# ── 1. 测试目录与文件数（来自版本控制）────────────────────────────
TESTFILES=$(git -C "$REPO" ls-files 2>/dev/null | grep -EI \
  '(^|/)([Tt]ests?)/|(_test|_spec)\.[a-z]+$|\.(test|spec)\.[a-z]+$|(^|/)test_[^/]+\.py$')

if [ -z "$TESTFILES" ]; then
  echo "未发现测试文件。"
  exit 0
fi

# 测试文件所在的顶层目录
DIRS=$(echo "$TESTFILES" | awk -F/ '{
  if ($1 ~ /^[Tt]ests?$/) print $1;
  else if (NF>1 && $2 ~ /^[Tt]ests?$/) print $1"/"$2;
  else { d=$0; sub(/\/[^\/]*$/,"",d); print (d==$0 ? "." : d) }
}' | sort -u)

# ── 2. workflow 里实际跑测试的命令 ───────────────────────────────
WF_DIR="$REPO/.github/workflows"
TEST_CMDS=""
if [ -d "$WF_DIR" ]; then
  TEST_CMDS=$(grep -rhoE \
    '(uv run pytest|python[0-9.]* -m (pytest|unittest)|pytest|py\.test|npm (run )?test|yarn test|pnpm (run )?test|npx (jest|vitest)|jest|vitest|node --test[^"]*|go test|cargo test|swift test|\./\.build/[a-z]*/[A-Za-z]*Tests|make test|tox|dotnet test|gradlew test)[^\n]*' \
    "$WF_DIR" 2>/dev/null | grep -vE 'install|add ' | sort -u)
fi

if [ -z "$TEST_CMDS" ]; then
  if [ -d "$WF_DIR" ]; then
    echo "workflow 存在，但没有任何一条命令运行测试。"
  else
    echo "没有 .github/workflows 目录——没有 CI 能跑这些测试。"
  fi
  echo
  echo "测试目录:"
  UNREACH=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    n=$(echo "$TESTFILES" | grep -c "^$d/")
    echo "  [不可达] $d ($n 个文件)"
    UNREACH=$((UNREACH+1))
  done <<< "$DIRS"
  echo
  echo "结果: 0/$UNREACH 个测试目录可达。"
  exit 1
fi

echo "workflow 里的测试命令:"
echo "$TEST_CMDS" | sed 's/^/  /'
echo

# ── 3. 逐目录判定 ────────────────────────────────────────────────
echo "测试目录:"
TOTAL=0; UNREACH=0

# 从每条命令里剥掉命令名与 flag，剩下的路径参数决定它跑哪些目录。
# 一条路径参数都没有 = 全量发现，覆盖所有测试目录。
PATH_ARGS=""
HAS_BARE_CMD=0
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  args=$(echo "$cmd" | tr -d "\"'" | awk '{for(i=2;i<=NF;i++) print $i}' | grep -vE '^-' )
  paths=$(echo "$args" | grep -E '/|\*' )
  if [ -z "$paths" ]; then
    HAS_BARE_CMD=1
  else
    PATH_ARGS="$PATH_ARGS
$paths"
  fi
done <<< "$TEST_CMDS"

while IFS= read -r d; do
  [ -z "$d" ] && continue
  TOTAL=$((TOTAL+1))
  n=$(echo "$TESTFILES" | grep -c "^$d/")
  base=$(basename "$d")
  if [ "$HAS_BARE_CMD" -eq 1 ]; then
    hit=$(echo "$TEST_CMDS" | head -1)
    echo "  [可达]   $d ($n 个文件) ← ${hit}（全量发现）"
  elif echo "$PATH_ARGS" | grep -qE "(^|/)$base(/|$|\*)"; then
    hit=$(echo "$TEST_CMDS" | grep -F "$base" | head -1)
    echo "  [可达]   $d ($n 个文件) ← $hit"
  else
    echo "  [不可达] $d ($n 个文件)"
    UNREACH=$((UNREACH+1))
  fi
done <<< "$DIRS"

echo
echo "结果: $((TOTAL-UNREACH))/$TOTAL 个测试目录可达。"
[ "$UNREACH" -eq 0 ] || { echo "$UNREACH 个不可达——把它们挂进某个 job 的测试命令。"; exit 1; }
exit 0
