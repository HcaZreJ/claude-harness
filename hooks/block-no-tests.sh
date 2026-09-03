#!/bin/bash
# Stop hook: BLOCKS agent from stopping if it wrote business code but didn't run tests.
# Skips check if no business code files (.py/.js/.ts/.go/.rs/.java) were Write/Edit'd.
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# Check if any business code files were written/edited in this session
CODE_EDITED=$(jq -r '
  .message.content[]? |
  select(.name == "Write" or .name == "Edit") |
  .input.file_path // empty
' "$TRANSCRIPT_PATH" 2>/dev/null | grep -qE '\.(py|js|ts|tsx|go|rs|java|rb)$' && echo "yes")

# If no business code was touched, skip — this is a config/setup session
if [ "$CODE_EDITED" != "yes" ]; then
  exit 0
fi

# Business code was edited — check if tests were run
TESTS_RAN=$(jq -r '
  .message.content[]? |
  select(.name == "Bash") |
  .input.command // empty
' "$TRANSCRIPT_PATH" 2>/dev/null | grep -qiE 'pytest|npm\s+test|npm\s+run\s+test|cargo\s+test|go\s+test|vitest|jest|rspec|mocha' && echo "found")

if [ "$TESTS_RAN" = "found" ]; then
  exit 0
fi

# Block: code was written but no tests were run
echo "本次 session 修改了业务代码但未执行测试。请先运行测试验证改动再结束。" >&2
exit 2
