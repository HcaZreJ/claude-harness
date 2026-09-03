---
name: feature-workflow
version: 1.0.0
description: "多工作单元 feature 的完整交付流程：对齐意图 → 落 plan 文件 → 拆 BACKLOG → 用户验收闸门 → test-first 派发 → 验收 → 集成验证与收尾。含瘦身版 plan 模板、按改动内容分级的测试义务表、sub-agent 派发与验收规则。当改动触及 schema 或数据模型、auth 或权限或计费、不可逆数据操作、共享或全局配置（harness、CI workflow、多 repo 复用的库）、同步路径新增外部调用或新增并发结构，或本次改动即将写入第 5 个文件时加载。触发词：plan、设计、规划、重构、架构、拆任务、工作单元、多文件改动。"
metadata:
  companion_hooks:
    - ~/.claude/hooks/block-unplanned-sprawl.sh
    - ~/.claude/hooks/session-context.sh
  companion_scripts:
    - ~/.claude/scripts/check-ci-reachability.sh
---

# Feature Workflow

一个 feature 从需求到 commit 的完整链条。每步产出交给下一步，plan 文件是跨 session 的权威载体。

## 0 · 进入路径

**因文件数闸门进入时**，先执行拦截消息里给出的那条 `touch` 命令解除闸门，本 session 后续写入即畅通。

再判定走哪条路径：

| 进入原因 | 路径 |
|---|---|
| 仅文件数超阈值，改动本身是普通实现 | 轻量路径 |
| 触及 schema、权限、计费、判分、迁移、不可逆数据操作、共享或全局配置、同步路径新增外部调用、新增并发结构 | 完整路径（§1 起） |
| 用户说了 plan、设计、规划、重构、架构 | 完整路径（§1 起） |

### 轻量路径

改动面宽而风险低时走这条：

1. 列出 work unit 清单（口头列出即可，交给用户过目），标出每个单元的目标文件与验收判据
2. 按 §6 的测试义务表逐个交付，同文件的单元按序执行
3. 每个单元自验收：跑该单元的测试，再跑全量确认零新增失败
4. 全部完成后跑一次端到端冒烟，汇报

轻量路径产出 work unit 清单，不落 plan 文件、不设用户批准闸门。判定中途发现命中完整路径的任一条件时，转入 §1。

## 1 · 对齐意图

建立 intent model：Goal、Motivation、Known context（用户给的 + repo 实证）、Constraints、Non-goals、Success criteria、Assumptions、Unknowns。

**提问的判据**：某个 unknown 猜错的影响为 high，且从本地 repo 查不到答案。每个问题绑定一个具体决策，写清为什么重要、不答时的默认假设、该默认的风险。

`confidence ≤ medium` 且 `impact = high` 的假设，走三条路之一：问用户、从 repo 验证、记为「用户接受的风险」。

## 2 · 落 plan 文件

写进 `<repo>/.claude/plans/<feature-slug>.md`，该目录保持 git tracked。

```markdown
# Feature: <name>

## 对齐段
**要做什么** — 一段话
**不做什么** — 明确排除的范围
**验收标准** — 可观测的判据，编号列出
**待确认假设** — 仅列 impact = high 的

## 执行段
### 风险闸
### Work Units
### 依赖与波次

## Status
In Progress | Completed
```

**对齐段 ≤ 15 行**，用户读这段就能判断方向对不对。全文 ≤ 100 行。

### 风险闸

答本次改动命中的条目，命中即逐条作答：

| 命中条件 | 作答内容 |
|---|---|
| 用户可见路径新增外部调用 | 列出路径上每次 LLM / HTTP / 重查询与最坏时延，说明调用次数的上限 |
| 新增后台任务或并发结构 | 锁边界：谁先 commit、谁等谁、持锁期间发生什么 |
| 新增写路径 | 重复提交与重试的后果，一句话 |
| 新增测试目录 | 跑 `check-ci-reachability.sh <repo>`，写出选中它的 workflow 与 job 名 |
| 含 migration | downgrade 存在，且在干净库上 up/down 往返通过 |
| 外部输入流进 prompt / SQL / shell | 中间经过的边界 |
| 改动会上线 | 回滚路径：feature flag、revert 影响面、数据可逆性 |

### Work Units

粒度：一个 sub-agent 一个 context window 能完整交付并自验收——通常一个文件、一个紧耦合方法簇、一个 migration、一处接线。

```yaml
- id: T1
  title: 限流配置子系统
  file_path: core/config.py
  functions:
    - name: load_rl_config
      inputs: [...]
      outputs: ...
      error_cases:
        - { condition: "...", behavior: "..." }
  dependencies: []
  reuse_candidates: 搜过哪里、有无可复用实现、为何仍新写
  acceptance: 可观测的完成判据
```

契约写输入、输出、error case、验收。实现路径由 implementer 读 repo 自行决定。

写 spec 前先 Search-Before-Write：搜 codebase 有无可复用实现，结果记进 `reuse_candidates`。

### 依赖与波次

依赖图为 DAG。按拓扑分波，同波可并行。

## 3 · plan 红队评审

plan 触及架构、数据模型、权限、计费、迁移时，派 `plan-reviewer` 审一轮。它只报会导致方案失败或产生实际损害的 FAIL 项。FAIL 修进 plan 后 plan 完成。

红队的价值在于评审上下文与撰写上下文脱钩：写 spec 时的盲区会原样复制进每个 implementer，独立上下文把这条相关性打断。

## 4 · 拆 BACKLOG

写进 `<repo>/BACKLOG.md`，按波次组织：

```markdown
## 执行中 · Plan: <slug>   (→ .claude/plans/<slug>.md)

### Wave 1 — 无依赖 · 可并行
- [ ] T1  限流配置子系统   file: core/config.py
        spec: load_rl_config, merge_env, validate
        验收: config 模块 tests 全绿 + 启动校验通过
```

条目点名 plan 里的 spec id、给出交付物与验收判据，设计细节留在 plan。

BACKLOG 只装当前 plan 拆出、本 session 处理的单元。长期待办走 GitHub issues。

## 5 · 用户验收闸门

把 BACKLOG 摆给用户 review，得到明确批准后进入派发。这一步让用户先校验任务拆解是否合理。

## 6 · 派发

### 测试义务

按**改动内容**定，同时命中多条时取最严的一条：

| 改动内容 | 测试义务 |
|---|---|
| 计费 / 权限 / 判分 / 迁移 / 不可逆数据操作 | 盲测分离，必测 |
| 含条件分支、计算、状态推导 | test-first，≤ 8 例/单元 |
| 普通函数 / 接线 | test-first，≤ 4 例/单元 |
| 纯样式、静态文案 | 跑起来验收，留命令输出或截图 |
| 配置 / 文档 | 无测试义务 |

带业务分支的前端组件按「含条件分支」处理。

新增测试目录时跑 `check-ci-reachability.sh <repo>`，把目录挂进选中它的 job——CI 选不中的测试从不运行。

### 调度

两条约束同时满足才并行：依赖单元全部完成（DAG），且目标文件互不相同。目标同一文件的单元按序执行。

### 常规单元

派一个 `unit-developer`。输入：本单元 spec + TECHSTACK.md 路径 + 目标文件 + 依赖单元的接口 + repo 根路径 + 全量测试与 lint 命令。它按序执行：从 spec 推导测试 → stub 红灯确认 → 实现到本单元全绿 → 全量零失败才交付。

架构师验收：审它的**测试 diff** + 亲自重跑全量。审四点——
- **正确性**：每个 expected 与 spec 一致
- **覆盖度**：spec 的每个 error_case 都有测试；边界（空、None、0、极值、畸形）覆盖
- **断言精确度**：判到具体值，避开浮点精确相等、字典键序、不稳定字符串
- **隔离性**：测试间状态独立，与执行顺序无关

### 高风险单元

计费、权限、判分、migration、不可逆数据操作走盲测分离三步：

**6a** 派 `test-author`。输入：该单元 spec + TECHSTACK.md + stub 的 import 路径 + repo 根路径。产出 `tests/visible/<unit>_test.py`（2-3 例）与 `tests/hidden/<unit>_test.py`（10+ 例）。测试函数命名 `test_<unit>_<scenario>`，便于 `-k <unit>` 过滤。全部完成后在 stub 状态跑一遍，确认全部 FAIL with NotImplementedError。

**6b** 架构师逐个单元审 visible + hidden 测试，审查点同上四条，外加 mock/fixture 是否准确模拟真实行为。发现问题直接改测试，改完重跑确认仍 FAIL with NotImplementedError。审过的测试才交给 implementer。

**6c** 派 `function-implementer`。输入：本单元 spec + TECHSTACK.md + 目标文件 + 依赖单元的实现或 stub + 本单元的 visible 测试 + repo 根路径。它用 `~/.claude/scripts/run-hidden-tests.sh <repo-root> <unit>` 跑 hidden 测试，输出为 `PASSED: X/Y`。

### 派发上下文卫生

大块输入（spec、目标文件、依赖产物）以文件路径传递让 sub-agent 自读，prompt 里留当前任务的指令本身。需要 diff review 时，先记下派发前的 BASE commit，用 `BASE..HEAD` 取全部改动核验。

### 可用的 sub-agent

`unit-developer` `test-author` `function-implementer` `plan-reviewer` `impl-reviewer` `repo-analyzer` `Explore` `general-purpose` `Plan`

交付面向人的界面或文字时另有三个：`ui-designer` 出界面设计与本地 HTML 设计稿；`prose-finisher` 给成段文字做去 AI 味收尾；`prose-auditor` 在交付前做零 prior 读者审查，派它时把用户本次任务的全部消息原文逐条不删节贴进 prompt。判据与交接顺序见 CLAUDE.md「界面与文字派 agent」。

模型分级：调研、检索、盘点、外抓、格式搬运用 sonnet 起；纯文件定位用 `Explore`（haiku）。判断密集的任务（深度调试、跨模块设计推演、需要品味的定稿评审）在 Agent 调用里显式传 `model: "opus"`，并在 prompt 里写清为什么需要强模型。

## 7 · 验收与升级

每个单元交付后架构师亲自核验：常规单元重跑全量测试，以自己的输出为准；盲测单元跑 hidden test 脚本。

失败时按序处理：
1. **先查测试质量**。实现合理而测试断言与 spec 不符时，直接改测试，让当前 implementer 重跑。
2. **升级 opus**。测试无误而 sonnet 仍搞不定时，用 `model: "opus"` 重派。
3. **反思 spec**。opus 也失败，多半 spec 不清或漏了关键细节，回头修 spec、测试、或对问题的理解。
4. **架构师下场**。亲自读码，先定位 root cause 再动手。深 bug 先建最小复现回路，再对假设排序、逐一证伪。

同一问题修复尝试累计 3 次仍无效时停手，转去质疑 spec、设计、或对问题的理解本身。

## 8 · 集成验证与收尾

全部单元完成后跑全量测试 + lint/type check，另加两道硬闸：

- **端到端冒烟**：plan 触及的每条关键用户路径，对真实栈（本地起服务或 DB）走通一次——curl、浏览器、脚本皆可，以真实输出为准。单元全绿证明函数合规，路径走通证明系统能用；时延、锁、异步衔接只在这里现形。
- **CI 可达性**：跑 `check-ci-reachability.sh <repo>`，退出码为 0 才算通过。

高风险单元派 `impl-reviewer` 终审（spec 合规 + 质量 + 安全，一遍过）。FAIL 修掉，WARN 交用户定。

按 Living Documentation 表更新触及的文档，plan 的 Status 改 Completed。

**收尾**：向用户汇报（各单元状态、测试通过情况、涉及文件、未决假设）→ 清空 BACKLOG 已完成条目 → commit。

commit 打在本地，粒度为 plan 级，message 格式 `feat: <plan 简述>`，body 列单元与文件、引用 plan 文件。push 由用户明确要求时执行——push 触发 CI/CD 发布，本地 commit 随时可 rollback 或往上堆叠。
