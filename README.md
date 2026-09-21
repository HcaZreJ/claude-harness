# claude-harness

一套 Claude Code 全局配置：一份 `CLAUDE.md`、6 个 hook 脚本、11 个 sub-agent 定义、5 个 skill、2 个脚本。我从 2026 年 3 月起每天用它，2026 年 9 月把它从 `~/.claude` 与 `~/.agents/skills` 里抽出来开源，MIT 许可证。

这套配置到 2026 年 9 月为止的演进史写在仓库第一个 commit 的 message 里，`git log` 拉到底就能看到。想知道某条规则为什么长成现在这样，那里有 35 条带日期的记录。

## 这套配置解决什么问题

在 prompt 里写一句「记得先写测试」「高危改动先对齐再动手」，这个 session 照做，下个 session 不照做，往往等它没照做了，你才发现。

多数改动直接动手做完就好，约束只加在容易出事的那几类上。这套配置把约束拆成三层，三层各交给一种机制：

- **判断条件写在 `CLAUDE.md` 里**：这次改动要不要先对齐再动手、触及计费代码要不要先写测试，两张表格逐条给出条件，动手的时候照着判定。
- **`hooks/` 在工具层拦下操作**：改过业务代码又没跑过测试的 session 要结束时，Stop hook `block-no-tests.sh` 就 `exit 2`，这个 session 结束不了，模型只能先去跑测试。
- **`agents/` 与 `scripts/` 把职责分开**：审文稿的 agent 只拿用户原话和成品，草稿和讨论记录一概读不到；用户点名「盲测」时，写实现的 agent 读不到隐藏测试，只拿得到一行 `PASSED: 8/12 test cases`。

## 仓库结构

```
CLAUDE.md              全局规则：任务分流表、测试义务表、代码写法七条、12 条铁律
agents/                11 个 sub-agent 定义；agents/assets/ 放 ui-designer 用的 Swift 预览包模板
hooks/                 6 个 hook 脚本；hooks/tests/ 是自测脚本
scripts/               run-hidden-tests.sh、check-ci-reachability.sh；scripts/tests/ 是自测脚本
skills/                5 个 skill
settings.example.json  settings.json 样例，里面写了全局 hook 怎么挂
statusline-command.sh  状态栏脚本，Gruvbox 配色；要用的话在 settings.json 里挂 statusLine
```

## 第一层：判断条件写在 CLAUDE.md 里

全文 119 行，主体是两张表格加一份代码写法判据。

**任务分流表**列了 4 个条件：这次改动触及 schema、migration、数据模型；触及 auth、权限、计费、判分；做不可逆数据操作；或者用户说了 plan、设计、规划、重构、架构。命中任何一条就加载 `skills/feature-workflow/SKILL.md`，一条都不命中就直接动手。这 4 个条件只看改动的性质——碰没碰数据结构、权限、钱、不可逆操作——不看改了几个文件、改动有多大。

加载之后，这份 skill 要求三件事。先在对话里贴一段不超过 10 行的说明，跟用户对齐：要做什么、不做什么、怎么算验收通过、有哪些高危假设，用户认可了再动手。再按 skill 里那张风险表，改动命中哪一条就在说明末尾回答对应的问题：migration 能不能回退；重复提交和重试是什么后果；外部输入在流进 prompt、SQL、shell 之前经过哪些边界检查；上线之后出问题怎么回滚。**之后的测试、实现、验证由主 session 自己做，不派 sub-agent**——盲测分离、终审、把工作单元拆开并行做，这三件事列在 skill 末尾的 opt-in 表里，用户说出「盲测」「终审」「并行拆开做」才分别启用。

**测试义务表**按改动内容分 5 档，同时命中多条时取最严的一条。改到计费、权限、判分、迁移的代码，或者做不可逆数据操作，必须写测试，按 test-first 做，用户点名「盲测」才做盲测分离；改动含条件分支、计算、状态推导，按 test-first 做，最多 8 个用例；普通函数与模块之间的粘合代码，按 test-first 做，最多 4 个用例；纯样式与静态文案，跑起来验收，留下命令输出或截图；配置与文档，不要求测试。新增测试目录时先跑一次 `scripts/check-ci-reachability.sh`——CI 选不中的测试从不运行。

这两张表格的条件，动手的时候照着一条条对就能判定。剩下的 12 条铁律也一样，例如「跑命令拿输出再下结论」「范围 = 用户字面需求」「push 由用户明确要求」。

**代码写法**七条管的是函数内部长什么样：主路径留在最外层，前置条件用 guard 挡在前面，条件超过两三条就收进一个命名的判定函数；名字答得出「这是什么」和「接下来发生什么」；外部服务的字段名止于适配层；类型只描述真实存在的状态；业务规则算成一个值，副作用另起一段，权限、计费、判分因此才测得动；错误同时给机器读的 code 和人读的 message；一个变更一个目的。七条共用一个判断标准——让下一次改动更容易。每条配一组 before/after 代码放在 `skills/code-craft/`，写函数、重构、给代码写法做 review 时加载。

`CLAUDE.md` 还有两节约束力更强、装上就一直生效的内容，装之前值得先看一眼。**Repo 初始化**要求每个仓库根目录有 `AGENTS.md` 作主入口，并指向 PROJECT / PATTERNS / TECHSTACK / DEVFLOW 四份内容文档；缺任何一份，进这个仓库先补文档再写业务代码。**Living Documentation** 规定改动触及什么就更新哪一份：产品的场景、用户、用法、要求或对标变了改 PROJECT.md，设计范式或代码约定变了改 PATTERNS.md，依赖、目录结构或核心 data model 变了改 TECHSTACK.md，构建测试部署流程变了改 DEVFLOW.md。纯实现细节、bugfix、不改这些约定的重构不用动文档。这两节不合你的习惯就删掉，它们和三层机制之间没有依赖。

## 第二层：hooks 在工具层拦下操作

拿 `hooks/block-no-tests.sh` 举例。它挂在 Stop 事件上，session 要结束时才运行：从 stdin 的 JSON 里取 `transcript_path`，读这个 session 的完整记录，先看 Write 和 Edit 写过的文件有没有业务代码后缀（`.py`、`.ts`、`.go` 等 8 种），再看 Bash 命令里有没有跑过测试（pytest、npm test、cargo test、go test 等）。这个 session 改过业务代码又没跑过测试，脚本就 `exit 2`，在 stderr 打印：「本次 session 修改了业务代码但未执行测试。请先运行测试验证改动再结束。」

这个 session 没有结束，模型拿到的是一条拒绝消息。「写完代码跑测试」写在 prompt 里，模型可能照做也可能不照做；挂成 Stop hook，脚本在每个 session 结束前查一遍记录，改过业务代码又没跑过测试的 session 就结束不了。

6 个脚本各管一件事：

| 脚本 | 事件 | 拦什么 |
|---|---|---|
| `hooks/block-pip.sh` | PreToolUse · Bash | `pip install` / `pip uninstall`，放行 `uv pip` |
| `hooks/block-absolute-paths.sh` | PreToolUse · Write\|Edit | 往 `.py`、`.ts`、`.sh` 等代码与配置文件里写死 `/Users/…`、`/home/…`、`C:\Users` |
| `hooks/block-hidden-tests.sh` | PreToolUse · Read\|Glob\|Grep | 任何指向 `tests/hidden/` 的 Read、Glob、Grep |
| `hooks/block-no-tests.sh` | Stop | 改过业务代码却没跑过测试的 session，Stop 时拦下不让结束 |
| `hooks/session-context.sh` | SessionStart | 不拦任何操作。扫 cwd 下的 `.claude/plans/`，只扫一层，把未完成的 plan 连同 Status 注入上下文；已完成却没删的列成清理提醒，Status 段缺失或值不规范的点名待补 |
| `hooks/check-prose-output.sh` | Stop | 不拦任何操作。本 session 加载过 `de-ai-writing` 时，把这一轮打给用户的正文喂给 `check.pl`，命中处列出来给用户看 |

脚本要拒绝一次操作，有两种写法，两种都写在 Claude Code 的 hook 协议里：`block-pip.sh` 与 `block-hidden-tests.sh` 输出带 `permissionDecision: "deny"` 的 JSON；`block-absolute-paths.sh` 与 `block-no-tests.sh` 用 `exit 2` 加 stderr。`hooks/tests/` 下有两份自测脚本，测的是这两个不拦操作的 hook：

```
$ bash hooks/tests/test-session-context.sh
session-context.sh: 8 passed, 0 failed

$ bash hooks/tests/test-check-prose-output.sh
check-prose-output.sh: 5 passed, 0 failed
```

## 第三层：agents 与 scripts 把职责分开

### 盲测分离：出题的和答题的互相看不见

用户点名「盲测」，高风险工作单元（计费、权限、判分、迁移、不可逆数据操作）就分三步做。

`agents/test-author.md` 只拿 spec，从不读实现代码，产出两份测试：`tests/visible/<unit>_test.py` 放 2-3 个用例给实现者当样例，`tests/hidden/<unit>_test.py` 放 10 个以上的用例，覆盖每一个 error case 和每一处边界情况。

`agents/function-implementer.md` 拿 spec、目标文件、visible 测试。它读不到 hidden 测试，唯一的反馈通道是 `scripts/run-hidden-tests.sh`，这个脚本只打印一行：

```
PASSED: 8/12 test cases
```

这一行里没有测试名，没有断言，没有 stack trace，看不出失败的是哪几条。实现者拿到的只有失败条数，拿不到失败在哪一条，只能回去重读 spec；照着报错逐条改到测试通过这条路走不通。pytest、jest、vitest、`go test`、`cargo test`、`node --test` 六种工具的输出格式各不一样，脚本自己识别是哪一种，再换算成同一种一行计数。

`scripts/check-ci-reachability.sh` 管另一件事：从 `git ls-files` 取测试文件清单，从 `.github/workflows/` 取真正跑测试的命令，逐个测试目录判定有没有哪条命令会跑这个目录里的测试，只要有一个目录没有命令跑就 `exit 1`。CI 选不中的测试从不运行。这个脚本目前会把没有命令跑的目录也报成可达，详见下面的「已知缺陷」。

### 不带背景的审查：只拿用户原话和成品

`agents/prose-auditor.md` 的 `tools` 只有 `Read`。派它的时候只给两样东西：用户在本次任务里发出的全部消息原文和成品的路径。草稿、调研档案、需求讨论、repo 里的代码，都不在它的输入里，它也不去找。

它判定两件事：一是仅凭这两样，读者能不能读懂；二是成品有没有回答用户真正问的问题。写成品的 agent 一路积累了大量背景，读自己写的句子时会自动把缺的意思补上，这类缺口它自己审不出来。审查者的上下文里没有这些背景，才不会跟着一起补。

### 11 个 agent

前三个与 Claude Code 内置的 agent 同名，装上之后覆盖内置版本而不是并列存在；其余八个是新增的。

| 定义文件 | model | 职责 |
|---|---|---|
| `agents/Explore.md` | haiku | 只读检索，大范围扫描定位文件与符号 |
| `agents/general-purpose.md` | sonnet | 通用调研、盘点、多步执行 |
| `agents/Plan.md` | opus | 为复杂任务设计实现方案 |
| `agents/unit-developer.md` | sonnet | 常规工作单元：从 spec 推导测试 → 在 stub 上确认红灯 → 实现到测试全部通过 |
| `agents/test-author.md` | sonnet | 盲测分离的出题方 |
| `agents/function-implementer.md` | sonnet | 盲测分离的答题方 |
| `agents/impl-reviewer.md` | sonnet | 高风险工作单元终审：spec 合规 + 质量 + 安全，一遍走完 |
| `agents/repo-analyzer.md` | sonnet | 通读仓库，只读不写，把技术栈与开发流程的事实整理出来 |
| `agents/ui-designer.md` | opus | 界面设计，出稿前先取市面上的做法——查仓库里已有的竞品调研，没有就联网找对标产品——再按目标载体分两条路：网页类交付可在浏览器打开的 HTML 设计稿，macOS 原生界面交付可 `swift run` 打开的 AppKit 设计稿 |
| `agents/prose-finisher.md` | opus | 给面向人类读者的文字做去 AI 味收尾 |
| `agents/prose-auditor.md` | opus | 交付前的最后一道审查：只拿用户原话和成品 |

`ui-designer` 与 `prose-finisher` 在 frontmatter 里用 `skills:` 字段挂上 `interface-design` 与 `de-ai-writing`。派发这两个 agent 的时候，SKILL.md 正文会跟着进它们各自的上下文，主 session 不用读这两份合计 270 行的规则文件。

## hooks 挂在两个地方

**全局这一级**的 hook 挂在 `settings.json` 里，对所有 session、所有 agent 生效。`settings.example.json` 里挂了 4 个 hook：`block-pip.sh`、`block-absolute-paths.sh`、`session-context.sh`、`check-prose-output.sh`。

**sub-agent 这一级**的 hook 挂在 agent 定义的 frontmatter 里，只在那一个 sub-agent 的生命周期内生效。`agents/function-implementer.md` 挂了 2 个 hook：

```yaml
hooks:
  PreToolUse:
    - matcher: "Read|Glob|Grep"
      hooks:
        - type: command
          command: "bash ~/.claude/hooks/block-hidden-tests.sh"
  Stop:
    - hooks:
        - type: command
          command: "bash ~/.claude/hooks/block-no-tests.sh"
          timeout: 10
```

`settings.example.json` 里没提 `block-hidden-tests.sh` 与 `block-no-tests.sh`，只看 `settings.json` 的人会以为这两个脚本没启用。它们的作用域正好是盲测分离要的：主 session 读 `tests/hidden/` 不受影响，答题的那个 agent 读不到；主 session 改完配置直接结束没问题，写过业务代码的那个 agent 不跑测试就停不下来。

## 安装

### 装之前先知道两件事

**这套配置接管你整个全局 Claude Code 配置**，不是并进去。下面的命令把 `CLAUDE.md`、`agents`、`hooks`、`scripts`、`skills` 拷进 `~/.claude`，同名文件直接覆盖，你原有的同名内容就没了——先备份 `~/.claude` 再装。`settings.json` 本 repo 只给样例，你自己的权限配置、MCP server、statusline 要手工并进去。

**运行时依赖**：Claude Code（要支持 agent frontmatter 里的 `skills:` 与 `hooks:` 字段）、bash、git、`jq`（hook 脚本解析工具调用的 JSON）。另外两个 skill 各自还要一样东西：`skills/de-ai-writing/scripts/check.pl` 与 `hooks/check-prose-output.sh` 要 Perl，`skills/interface-design/scripts/design-check.cjs` 要 Node 和 Playwright。这两样不装也不影响其余部分。`ui-designer` 设计 macOS 原生界面时要 Swift toolchain（`swift run`），这条路只在 macOS 上成立，设计网页不需要它。脚本按 macOS 与 Linux 写，没有在 Windows 上验证过。

### 装

```bash
git clone https://github.com/<你的账号>/claude-harness.git ~/Documents/claude-harness
cd ~/Documents/claude-harness

# 全局规则、agent、hook、脚本
cp CLAUDE.md ~/.claude/CLAUDE.md
cp -R agents hooks scripts ~/.claude/

# skill 拷两处，下一节说为什么
mkdir -p ~/.agents/skills ~/.claude/skills
cp -R skills/* ~/.agents/skills/
cp -R skills/* ~/.claude/skills/

# settings.json 只给样例，自己的配置往里并
cp settings.example.json ~/.claude/settings.json
```

### 装完是一份拷贝，不是链接

`~/.claude` 下的是实体文件，和 repo 各走各的。repo 里改了要重拷一次，`~/.claude` 里改了要手工回填 repo。

这个 repo 公开发布，发之前每份文件都要脱敏，所以两边不做同步：`~/.claude` 里是我每天在用的真实配置，含 repo 名、内部项目、私人路径；repo 里是把这些抹掉之后的版本。两边内容本来就不该逐字相同，链在一起等于每次编辑都要当场做一遍脱敏判断。漂移由我手工回填。

### skill 为什么拷两处

Claude Code 加载 skill 只认 `~/.claude/skills`，缺这一份 skill 不会被加载。

另一处 `~/.agents/skills` 是三个固定路径的落点：`agents/ui-designer.md` 和 `skills/interface-design/SKILL.md` 里那条 `design-check.cjs` 命令、`hooks/check-prose-output.sh` 找 `check.pl` 的默认位置，都按这个路径写。这一层也让别的 agent 工具（比如 codex）读同一份 skill。

只用 Claude Code 的话，把这三处路径里的 `~/.agents/skills` 改成 `~/.claude/skills`，就只用拷一份。`check-prose-output.sh` 还认 `DE_AI_CHECK` 环境变量，`check.pl` 放哪都能指过去。

### 不想要了怎么退回去

删掉拷进去的那几项，把装之前的备份放回原处：

```bash
rm -f ~/.claude/CLAUDE.md ~/.claude/settings.json
rm -rf ~/.claude/agents ~/.claude/hooks ~/.claude/scripts
for s in feature-workflow de-ai-writing interface-design push-code-to-main; do
  rm -rf ~/.claude/skills/"$s" ~/.agents/skills/"$s"
done
```

repo 本身删不删都行，删了不影响已经恢复的配置。

## 已知缺陷

`scripts/check-ci-reachability.sh` 要找出没有任何 CI job 会跑的测试目录。这类目录，它报成可达。

建一个 repo：workflow 用 `defaults.run.working-directory: services/api` 把作用域限定在一个服务上，另建一个测试目录 `services/legacy/tests`，没有任何 job 会跑它。跑出来的报告是：

```
测试目录:
  [可达]   services/api/tests (1 个文件) ← pytest（全量发现）
  [可达]   services/legacy/tests (1 个文件) ← pytest（全量发现）

结果: 2/2 个测试目录可达。
```

退出码 0。`services/legacy/tests` 实际不可达。

**在这些修掉之前，它返回退出码 0 不能当作「测试都在 CI 里跑得到」的证据**——而 `CLAUDE.md` 的测试义务表和 `feature-workflow` 都要求新增测试目录时先跑一次它。

5 个原因，每一个都有单独的复现例子：

1. **脚本不解析 `working-directory:`。** 它见到不带路径参数的命令（`run: pytest`），就打上报告里那个「全量发现」标记，按这条命令覆盖了仓库里所有测试目录来处理，不去看这个 job 把工作目录限定到了哪里。
2. **脚本把安装命令当成测试命令。** workflow 里只要有一条装 pytest 的 `pip install`，脚本就算成 CI 在跑 pytest。它本来会用 `grep -vE 'install|add '` 过滤一次，但上一步的 `grep -o` 只截取从 `pytest` 起的那一段，`install` 已经被切掉，过滤的时候匹配不到它。所以连一个只 build 镜像的 deploy workflow，脚本也算成在跑测试。
3. **测试目录归组归得太粗。** 归组只取路径第一段，`tests/` 下的子目录全归进同一组，只要有一条命令命中组里任何一个子目录，脚本就把整组判成可达。`tests/unit` 可达，把 `tests/orphan` 不可达这件事盖了过去，报告里 `tests/orphan` 连单独一行都不会有。
4. **第三方目录会进清单。** 只要 git 跟踪了 `.venv/`、`node_modules/` 里的测试文件，脚本就把这些目录当成这个项目自己的测试目录列出来，还计入总数。
5. **macOS 自带的 BSD grep 会截断抽出的命令。** `grep -oE` 配合脚本里那条复杂 ERE 时，`pytest tests/unit` 抽出来是 `pytest tests/u`，`npx vitest run` 抽出来是 `npx vitest ru`。路径参数被切掉，脚本拿这段被切短的命令去判定可达不可达，结果就是错的。

### 测试套件的状态

现在跑 `bash scripts/tests/test-check-ci-reachability.sh`，20 个断言失败，退出码 1。这 20 处分三类：

- **8 处是断言没跟上脚本。** 断言里写的还是英文输出（`[REACHABLE]`、`No test directories found`、`tests (2 files)`），脚本实际打印的是中文（`[可达]`、`未发现测试文件。`、`tests (2 个文件)`）。脚本打印中文没问题，这 8 处要改的是断言。
- **4 处断言测的是脚本从没实现过的能力。** 一是读 Dockerfile 判断镜像里有没有 COPY 进测试目录，二是把可达性归到具体的 workflow 文件名与 job 名上。脚本只打印命中的那条命令。
- **8 处打中的是上面那些真缺陷。** `working-directory` 那条占 3 处，deploy workflow 那条占 3 处，`.venv` 与 `node_modules` 各占 1 处。

这套测试原先不失败。它的夹具建完假 repo 就直接跑脚本，从不 `git init`，脚本第一步用 `git ls-files` 取测试文件清单，清单永远是空的。脚本走「未发现测试文件」那条分支提前退出并返回 0，断言核对的是一份空报告。夹具补上 `git init` 之后，上面这些失败才第一次暴露出来。

`hooks/` 下的那份自测脚本不受影响，跑起来全部通过，输出贴在上面「第二层」那节。

## 5 个 skill

| skill | 做什么 |
|---|---|
| `skills/feature-workflow/` | 高危改动动手前先跟用户对齐：把不超过 10 行的说明贴进对话，按命中的风险条目逐条回答对应的问题，用户认可后，测试、实现、验证由主 session 自己做；盲测分离、终审、把工作单元拆开并行做，这三件事用户点名才启用 |
| `skills/code-craft/` | 写函数时的七条判据，每条配一组 before/after：主路径留在最外层、名字给出业务含义、外部系统的字段名止于适配层、类型只描述真实存在的状态、决策算成值而副作用另起一段、错误同时给 code 与 message、一个变更一个目的 |
| `skills/de-ai-writing/` | 去 AI 味写作流程：先收集材料再写，写完把读者会看到的句子提取出来跑 `skills/de-ai-writing/scripts/check.pl` 做残渣检测，要判断的那些检查连同改写一起交给没参与写作的 sub-agent。`skills/de-ai-writing/tests/` 是 check.pl 的回归语料，改规则之后跑 `bash tests/run.sh` 量召回与误报两个数 |
| `skills/interface-design/` | 界面设计的硬性要求，先定信息层级：八条规则，`skills/interface-design/scripts/design-check.cjs` 用真截图加灰度高斯模糊算出画面第一眼焦点，再映射回具体 DOM 元素 |
| `skills/push-code-to-main/` | 开分支、commit、开 PR、squash 合并、删掉分支与 worktree、同步 main，合并后确认这个 repo 的 CI 结论 |

## 我还装了这个第三方 skill

**女娲（`huashu-nuwa`）**：输入一个人名，或者只用一句话说个模糊需求，它去做调研、提炼思维框架，产出一个能直接运行的人物 skill。

本 repo 不含它，要自己去装：

- 上游 <https://github.com/alchaincyf/nuwa-skill>，MIT
- 装到 `~/.agents/skills/huashu-nuwa`

上面那段安装命令只拷本 repo `skills/` 下的 5 个 skill，`huashu-nuwa` 不在其中，装不装都不影响这套配置运转。那 5 个 skill 都是我写的，别人写的 skill 我只额外装了女娲这一个，它的出处就是上面那两行。仓库里还有几处材料来自别人，不用你另外安装任何东西，归属写在文末「License 与第三方材料」一节。

## 文档用什么语言写

中文为主：`CLAUDE.md`、`feature-workflow`、`code-craft`、`de-ai-writing`、`interface-design` 这 4 个 skill，加上 `Explore`、`general-purpose`、`Plan`、`unit-developer`、`ui-designer`、`prose-finisher`、`prose-auditor` 这 7 个 agent，正文都是中文。

`function-implementer`、`test-author`、`impl-reviewer`、`repo-analyzer` 这 4 个 agent，加上 `push-code-to-main` 这个 skill，正文都是英文。所有 agent 的 frontmatter `description` 中英文混着写，hook 脚本的注释也是。

## License 与第三方材料

这个仓库我按 MIT 许可证开源，许可证全文在 `LICENSE` 文件里。你可以自由使用、修改和分发它，商用也可以；分发出去的副本里，把 `LICENSE` 里的版权声明和许可声明一并带上就行。

仓库里的文件都是我写的，有三处例外——几个 agent 字段、两份调研存档里的引文、状态栏的 8 个颜色值，这三处来自别人。另外还有一处不是材料而是参考：`de-ai-writing` 的审查流程借鉴过 GitHub 上 `shuorenhua` 这个 skill 的结构。四条逐一写在下面，`LICENSE` 末尾有对应的英文版本。

- `agents/Explore.md` 和 `agents/Plan.md` 里，`description` 和 `tools` 两个字段是我从 Claude Code 内置的同名 agent 里逐字照抄的；`agents/general-purpose.md` 里，我照抄的只有 `description` 一个字段。这几个字段的著作权归 Anthropic 所有。我照抄它们，是因为这两个字段各管一件事：Claude Code 读 `description` 决定什么时候派这个 agent，读 `tools` 决定派出去的 agent 能用哪些工具。两个字段一个字不改，这三份文件覆盖掉内置版之后，派发时机和工具权限都跟内置版一样。这三份文件的正文是我写的。
- `skills/de-ai-writing/references/research.md` 和 `skills/interface-design/references/research.md` 这两份调研存档里，我引用了 Nielsen Norman Group 的文章，也引用了 Edward Tufte、George Orwell、Ted Chiang、Paul Graham、余光中、汪曾祺、Verlyn Klinkenborg 等人写过的句子。这几个是分量最重的来源，不是全部——每一处引文都在原地注明了出处，完整名单在两份文件末尾的「信源列表」一节。引文的著作权归原作者所有。哪些句子入选、句子怎么翻译、引文后面的分析怎么写，都是我自己定的，按 MIT 许可证授权。
- `statusline-command.sh` 里的 8 个颜色值取自 Gruvbox 配色。Gruvbox 的作者是 Pavel Pertsev，按 MIT 许可证发布；这 8 个值连同各自的名字都写在那个脚本开头的注释里。
- `skills/de-ai-writing/` 的审查流程是我写的，写的时候参考过 GitHub 上 shuorenhua 这个 skill 的六步结构（<https://github.com/MrGeDiao/shuorenhua>）。shuorenhua 的文字我一句都没照抄。这个 skill 我在 `skills/de-ai-writing/references/research.md` 的信源列表里注明了。

想把其中一处单独拿去用，条件不一样，这里一次说清。Gruvbox 那 8 个颜色值按 MIT 发布，照抄进你自己的项目没有障碍。Anthropic 那几个字段和调研存档里的引文，我都没有替你取得额外许可——把 `description` 搬进别的项目、或者转载某一处引文，这个判断是你自己的，我这边做到的是逐处标明出处。第四处是设计参考，没有材料需要许可。`LICENSE` 末尾把这几条用英文写了一遍，措辞更正式，说的是同一件事。
