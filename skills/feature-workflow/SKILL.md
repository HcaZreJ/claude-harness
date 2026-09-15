---
name: feature-workflow
version: 2.0.0
description: "高危改动闸：≤10 行对齐贴对话 → 风险闸 → 主上下文亲自交付。当改动触及 schema 或 migration 或数据模型、auth 或权限或计费或判分、不可逆数据操作，或用户说 plan、设计、规划、重构、架构时加载。触发词：plan、设计、规划、重构、架构、迁移、数据模型。"
metadata:
  companion_hooks:
    - ~/.claude/hooks/session-context.sh
  companion_scripts:
    - ~/.claude/scripts/check-ci-reachability.sh
    - ~/.claude/scripts/run-hidden-tests.sh
---

# Feature Workflow（高危改动闸）

范围 = 用户字面提出的需求。用户没提的机制（版本管理、提交流程、缓存层、配置系统、抽象层），想加先用一句话问，用户点头才做。

## 1 · 对齐（≤10 行，直接贴对话里）

- **要做什么** — 一句话
- **不做什么** — 明确排除的范围
- **验收判据** — 可观测，编号列出
- **高危假设** — 仅列猜错影响为 high 且 repo 查不到的，每条附默认取值

用户认可后开工。plan 落文件（`<repo>/.claude/plans/<slug>.md`，git tracked，含 Status 行）只在两种情况：用户主动说 plan / 规划，或任务明确跨 session 交接。落文件时内容同上四段加 work unit 清单，完成即删，git 历史承载。

## 2 · 风险闸（命中才答，附在对齐段末尾）

| 命中 | 作答 |
|---|---|
| 含 migration | downgrade 存在，干净库上 up/down 往返通过 |
| 新增写路径 | 重复提交与重试的后果，一句话 |
| 外部输入流进 prompt / SQL / shell | 中间经过的边界 |
| 改动会上线 | 回滚路径：feature flag、revert 影响面、数据可逆性 |

## 3 · 交付（主上下文亲自做）

测试义务按 CLAUDE.md 测试义务表。测试亲自写、实现亲自写、测试亲自跑，以自己终端的输出为准。同一问题修复尝试累计 3 次仍无效时停手，转去质疑 spec、设计、或对问题的理解本身。

收尾三件事：

1. 关键用户路径对真实栈走通一次（curl / 浏览器 / 脚本，以真实输出为准）；新增测试目录跑 `check-ci-reachability.sh <repo>`，退出码 0 才算挂上 CI
2. 按 Living Documentation 表更新文档；plan 文件若有，完成即删
3. 汇报（铁律 8：写给没读过代码的 manager）→ commit；push 由用户明确要求

## Opt-in（用户点名才启用）

| 用户说 | 动作 |
|---|---|
| 「盲测」 | 派 `test-author` 出 visible + hidden 测试，架构师审过、stub 上全 FAIL 后，派 `function-implementer` 实现；hidden 结果经 `run-hidden-tests.sh` 只回通过数 |
| 「终审」 | 派 `impl-reviewer` 审 spec 合规 + 质量 + 安全 |
| 「并行拆开做」 | 拆 work unit 派 `unit-developer`，同文件单元按序；验收审测试 diff + 亲自重跑全量 |
