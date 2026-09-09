#!/bin/bash
# Tests for hooks/check-prose-output.sh (Stop hook).
# 覆盖：未加载 skill 的 session 静默、命中时打印摘要且退出码 0、末条 assistant 事件是工具调用时回溯取正文。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../check-prose-output.sh"
CHECK="$HOME/.agents/skills/de-ai-writing/scripts/check.pl"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
FAILURES=0; PASS_COUNT=0
pass() { echo "  [PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

# make_transcript <file> <mentions_skill:yes|no> <assistant_text>
make_transcript() {
  local f="$1" mentions="$2" text="$3"
  : > "$f"
  [ "$mentions" = yes ] && \
    jq -nc '{type:"user",message:{role:"user",content:"请加载 de-ai-writing 改稿"}}' >> "$f"
  jq -nc --arg t "$text" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$f"
}

# 真实场景里 Stop 触发时，最后一条 assistant 事件常常是工具调用而非文本
make_transcript_tool_last() {
  local f="$1" text="$2"
  : > "$f"
  jq -nc '{type:"user",message:{role:"user",content:"请加载 de-ai-writing 改稿"}}' >> "$f"
  jq -nc --arg t "$text" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$f"
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"Bash",input:{command:"ls"}}]}}' >> "$f"
  jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:"ok"}]}}' >> "$f"
}

run_hook() { jq -nc --arg p "$1" '{transcript_path:$p,hook_event_name:"Stop"}' | bash "$HOOK" 2>/dev/null; }

DIRTY='这不是一次改版，而是一次彻底的重写。'
CLEAN='这次迁移把订单表拆成了三张，分别存主单、子单和退款记录。'

echo "test-check-prose-output.sh"

# 1 未用过 skill 的 session：完全不出声
T="$TEST_ROOT/t1.jsonl"; make_transcript "$T" no "$DIRTY"
OUT=$(run_hook "$T"); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && pass "未加载 skill 的 session 无输出且 exit 0" \
  || fail "未加载 skill 的 session 应静默，实得 rc=$RC out=[$OUT]"

# 2 用过 skill + 正文有残渣：打摘要，但不阻断
T="$TEST_ROOT/t2.jsonl"; make_transcript "$T" yes "$DIRTY"
OUT=$(run_hook "$T"); RC=$?
if echo "$OUT" | grep -q '否定-转折句族' && [ "$RC" -eq 0 ]; then
  pass "有残渣时打印摘要且 exit 0（不阻断）"
else
  fail "有残渣时应打摘要且 exit 0，实得 rc=$RC out=[$OUT]"
fi

# 3 用过 skill + 正文干净：不出声
T="$TEST_ROOT/t3.jsonl"; make_transcript "$T" yes "$CLEAN"
OUT=$(run_hook "$T"); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && pass "正文干净时无输出" \
  || fail "正文干净时应静默，实得 rc=$RC out=[$OUT]"

# 4 transcript 不存在：静默退出，坏掉的 hook 不能卡住用户
OUT=$(run_hook "$TEST_ROOT/nope.jsonl"); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && pass "transcript 缺失时静默 exit 0" \
  || fail "transcript 缺失时应静默，实得 rc=$RC out=[$OUT]"

# 5 最后一条 assistant 是工具调用：仍要检出更早那条正文
T="$TEST_ROOT/t5.jsonl"; make_transcript_tool_last "$T" "$DIRTY"
OUT=$(run_hook "$T"); RC=$?
if echo "$OUT" | grep -q '否定-转折句族' && [ "$RC" -eq 0 ]; then
  pass "末条为工具调用时仍能取到正文并检出"
else
  fail "末条为工具调用时应回溯到上一条文本，实得 rc=$RC out=[$OUT]"
fi

echo "check-prose-output.sh: $PASS_COUNT passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]
