---
name: feature-workflow
version: 2.0.0
description: "高危改动闸：≤10 行对齐贴对话 → 风险闸 → 主上下文亲自交付。当改动触及 schema 或 migration 或数据模型、auth 或权限或计费或判分代码、不可逆数据操作，或用户说 plan、技术方案设计、规划、重构、架构时加载。触发词：plan、技术方案设计、规划、重构、架构、迁移、数据模型。"
metadata:
  companion_hooks:
    - ~/.claude/hooks/session-context.sh
  companion_scripts:
    - ~/.claude/scripts/check-ci-reachability.sh
---

# Feature Workflow（高危改动闸）

**新机制先问一句。** 用户没提的机制（版本管理、提交流程、缓存层、配置系统、抽象层）会扩大改动面和以后的维护量，想加时先用一句话问，用户点头再做。完成需求本身要做的事（查到根因、补测试、更新文档、跑验证）属于需求的一部分，直接做。

## 1 · 对齐（≤10 行，直接贴对话里）

- **要做什么** — 一句话
- **不做什么** — 明确排除的范围
- **验收判据** — 可观测，编号列出
- **高危假设** — 仅列猜错影响为 high 且 repo 查不到的，每条附默认取值

用户认可后开工。plan 落文件（`<repo>/.claude/plans/<slug>.md`，git tracked，含 Status 行）在四种情况：用户主动说 plan / 规划，收到一大段需求或设计描述，任务跨多个阶段或明确跨 session 交接，预计上下文超过 20 万 token。落文件时写上面四段、「已决定事项和否决方案」一节（照抄用户原话）、work unit 清单和 Status；每完成一个 work unit 更新 Status。上下文超过 20 万 token 时的交接照全局 CLAUDE.md 铁律 1。完成即删，git 历史承载。

## 2 · 风险闸（命中才答，附在对齐段末尾）

| 命中 | 作答 |
|---|---|
| 含 migration | downgrade 存在，干净库上 up/down 往返通过 |
| 新增写路径 | 重复提交与重试的后果，一句话 |
| 外部输入流进 prompt / SQL / shell | 中间经过的边界 |
| 改动会上线 | 回滚路径：feature flag、revert 影响面、数据可逆性 |

## 3 · 交付（主上下文亲自做）

测试义务按 `~/.claude/rules/code.md` 的测试义务表。测试亲自写、实现亲自写、测试亲自跑，以自己终端的输出为准。同一问题修复尝试累计 3 次仍无效时停手，转去质疑 spec、设计、或对问题的理解本身。

收尾三件事：

1. 关键用户路径对真实栈走通一次（curl / 浏览器 / 脚本，以真实输出为准）；新增测试目录跑 `check-ci-reachability.sh <repo>`，再对照 CI 配置人工核对报告，确认目录挂进了选中它的 job
2. 按 `~/.claude/rules/code.md` 的文档更新表更新文档；plan 文件若有，完成即删
3. 汇报（铁律 8：写给没读过代码的 manager）→ commit；push 由用户明确要求

## 并行

plan 里有 3 个以上互不依赖的工作单元时，可派 `unit-developer` 并行，同一文件的单元按顺序做；验收时审测试 diff，并亲自重跑全量测试。
