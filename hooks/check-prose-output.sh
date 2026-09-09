#!/bin/bash
# Stop hook: 把本轮 agent 打给用户的正文过一遍 check.pl，命中就把摘要显示出来。
#
# 不阻断。据打回让原 agent 重写自己刚写的句子改不好，所以这里只把命中处
# 摊给用户看，重写与否由用户决定，改写交 prose-finisher。
#
# 只在本 session 碰过 de-ai-writing 时出声，普通编码 session 完全静默。
# 任何读取或解析失败都退出 0 —— 坏掉的 hook 不能卡住用户。

if [ -t 0 ]; then
  echo "用法: 由 Claude Code 作为 Stop hook 调用，JSON 从 stdin 传入。"
  echo "手工验证示例:"
  echo "  jq -nc '{transcript_path:\"/path/to.jsonl\",hook_event_name:\"Stop\"}' | bash $0"
  exit 0
fi

INPUT=$( (timeout 2 cat 2>/dev/null || true) )

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# 本 session 没碰过 de-ai-writing 就不出声
grep -q 'de-ai-writing' "$TRANSCRIPT" 2>/dev/null || exit 0

CHECK="${DE_AI_CHECK:-$HOME/.agents/skills/de-ai-writing/scripts/check.pl}"
[ -f "$CHECK" ] || exit 0
command -v perl >/dev/null 2>&1 || exit 0

TMP=$(mktemp) || exit 0
trap 'rm -f "$TMP"' EXIT

# 正文优先取 hook input 自带的字段，没有就从 transcript 末尾捞最后一条 assistant 文本
MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
if [ -n "$MSG" ]; then
  printf '%s\n' "$MSG" > "$TMP"
else
  # 末条 assistant 事件常常是工具调用，回溯到最后一条真正带正文的
  tail -n 400 "$TRANSCRIPT" 2>/dev/null \
    | jq -c 'select(.type=="assistant") | select(any(.message.content[]?; .type=="text"))' 2>/dev/null \
    | tail -n 1 \
    | jq -r '.message.content[]? | select(.type=="text") | .text' 2>/dev/null \
    > "$TMP"
fi
[ -s "$TMP" ] || exit 0

OUT=$(perl "$CHECK" "$TMP" 2>/dev/null)
if [ $? -eq 1 ]; then
  echo "──── 本轮正文的 AI 味残渣 ────"
  echo "$OUT" | grep -E '^\[|^  L[0-9]+:' | head -20
  echo "──── 要改就说一声，改写走 prose-finisher ────"
fi
exit 0
