#!/usr/bin/env bash
# install.sh
#
# 建软链，方向是 repo 里是真身，~/.claude 与 ~/.agents 下放链指向 repo。
# 只建链，不搬运内容。重复运行幂等。
#
# 支持环境变量覆盖根路径（便于测试）：
#   HARNESS_PUBLIC  覆盖 public repo 路径（默认 $HOME/Documents/claude-harness）
#   HARNESS_PRIVATE 覆盖 private repo 路径（默认 $HOME/Documents/claude-harness-private）
#   HOME            覆盖用户 home 目录
set -u

HOME_DIR="${HOME:?HOME must be set}"
PUBLIC="${HARNESS_PUBLIC:-$HOME_DIR/Documents/claude-harness}"
PRIVATE="${HARNESS_PRIVATE:-$HOME_DIR/Documents/claude-harness-private}"

if [[ ! -d "$PUBLIC" ]]; then
  echo "Error: public repo not found: $PUBLIC" >&2
  exit 1
fi

if [[ ! -d "$PRIVATE" ]]; then
  echo "Error: private repo not found: $PRIVATE" >&2
  exit 1
fi

shopt -s nullglob

_timestamp() {
  date +%Y%m%dT%H%M%S
}

# link_one <target_path> <link_source_path>
# 若 target 已是指向 source 的软链则跳过；
# 若 target 存在（文件/目录/其它软链，含悬空软链）则先备份为 <target>.bak-<timestamp>；
# 然后创建软链 target -> source。
link_one() {
  local target="$1"
  local source="$2"

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink "$target")"
    if [[ "$current" == "$source" ]]; then
      echo "skip (already linked): $target"
      return 0
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local bak="${target}.bak-$(_timestamp)"
    mv "$target" "$bak"
    echo "backed up: $target -> $bak"
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  echo "linked: $target -> $source"
}

# 1. ~/.claude/CLAUDE.md -> <public>/CLAUDE.md
link_one "$HOME_DIR/.claude/CLAUDE.md" "$PUBLIC/CLAUDE.md"

# 2. ~/.claude/{agents,hooks,scripts} -> <public>/{agents,hooks,scripts}
for d in agents hooks scripts; do
  link_one "$HOME_DIR/.claude/$d" "$PUBLIC/$d"
done

# 3. ~/.agents/skills/<name> -> <public>/skills/<name> 或 <private>/skills/<name>
#    再把 ~/.claude/skills/<name> 链到 ~/.agents/skills/<name>——Claude Code 读的是前者，
#    缺这一跳 skill 不会被加载。~/.agents 这一层让其他 agent 工具共用同一份 skill。
mkdir -p "$HOME_DIR/.agents/skills"

if [[ -d "$PUBLIC/skills" ]]; then
  for entry in "$PUBLIC/skills"/*/; do
    [[ -d "$entry" ]] || continue
    name="$(basename "$entry")"
    link_one "$HOME_DIR/.agents/skills/$name" "$PUBLIC/skills/$name"
  done
fi

if [[ -d "$PRIVATE/skills" ]]; then
  for entry in "$PRIVATE/skills"/*/; do
    [[ -d "$entry" ]] || continue
    name="$(basename "$entry")"
    link_one "$HOME_DIR/.agents/skills/$name" "$PRIVATE/skills/$name"
  done
fi

# 3b. ~/.claude/skills/<name> -> ~/.agents/skills/<name>
#     Claude Code 只认 ~/.claude/skills，这一跳建完 skill 才生效。
mkdir -p "$HOME_DIR/.claude/skills"
if [[ -d "$HOME_DIR/.agents/skills" ]]; then
  for entry in "$HOME_DIR/.agents/skills"/*/; do
    [[ -e "$entry" ]] || continue
    name="$(basename "$entry")"
    link_one "$HOME_DIR/.claude/skills/$name" "$HOME_DIR/.agents/skills/$name"
  done
fi

# 4. ~/.claude/plans -> <private>/plans，~/.claude/settings.json -> <private>/settings.json
#    plan 文件与 settings.json 归各自的作者，留在 private repo 里。
mkdir -p "$PRIVATE/plans"
link_one "$HOME_DIR/.claude/plans" "$PRIVATE/plans"
link_one "$HOME_DIR/.claude/settings.json" "$PRIVATE/settings.json"

exit 0
