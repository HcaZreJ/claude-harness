#!/bin/bash
# PreToolUse hook: blocks direct pip/pip3 install, allows uv pip
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# Allow uv pip commands
if echo "$COMMAND" | grep -q 'uv pip'; then
  exit 0
fi

# Block direct pip/pip3 install/uninstall
if echo "$COMMAND" | grep -qE '\bpip3?\s+(install|uninstall)\b'; then
  echo "$INPUT" | jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny"
    },
    systemMessage: "BLOCKED: pip 直接安装被阻断。必须使用 uv:\n- uv add <package>\n- uv pip install -r requirements.txt\n- uv run python script.py"
  }'
  exit 0
fi

exit 0
