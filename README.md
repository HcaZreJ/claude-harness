# claude-harness

一套 Claude Code 全局配置：一份 `CLAUDE.md`、一份 `rules/code.md`、4 个 hook 脚本、6 个 sub-agent 定义、6 个 skill、1 个脚本。我从 2026 年 3 月起每天用它，2026 年 9 月把它从 `~/.claude` 与 `~/.agents/skills` 里抽出来开源，MIT 许可证。

这套配置到 2026 年 9 月为止的演进史写在仓库第一个 commit 的 message 里，`git log` 拉到底就能看到。想知道某条规则为什么长成现在这样，那里有 35 条带日期的记录。

## 这套配置解决什么问题

在 prompt 里写一句「记得先写测试」「高危改动先对齐再动手」，这个 session 照做，下个 session 不照做，往往等它没照做了，你才发现。

多数改动直接动手做完就好，约束只加在容易出事的那几类上。这套配置把约束拆成三层，三层各交给一种机制：

- **判断条件写在 `CLAUDE.md` 和 `rules/code.md` 里**：这次改动要不要先对齐再动手，看 `CLAUDE.md` 的任务分流一段；触及计费代码要不要先写测试，看 `rules/code.md` 的测试义务表。两处都逐条给出条件，动手的时候照着判定。
- **`hooks/` 在工具层拦下操作**：模型要用 `pip install` 装包时，hook 脚本 `block-pip.sh` 在这条命令执行之前就拦下它，模型只能改用 `uv`。
- **`agents/` 把职责分开**：审文稿的 agent 只拿用户原话和成品，草稿和讨论记录一概读不到，派它的时候 Claude Code 也不给它加载 `CLAUDE.md` 和 memory。

## 仓库结构

```
CLAUDE.md              全局规则：任务分流、界面与文字派 agent、9 条铁律
rules/code.md          写代码时的规则：测试义务表、代码写法六条、文档更新对照表
agents/                6 个 sub-agent 定义；agents/assets/ 放 ui-designer 用的 Swift 预览包模板
hooks/                 4 个 hook 脚本；hooks/tests/ 是自测脚本
scripts/               check-ci-reachability.sh；scripts/tests/ 是自测脚本
skills/                6 个 skill
settings.example.json  settings.json 样例，里面写了全局 hook 怎么挂
statusline-command.sh  状态栏脚本，Gruvbox 配色；要用的话在 settings.json 里挂 statusLine
```

## 第一层：判断条件写在 CLAUDE.md 和 rules/code.md 里

`CLAUDE.md` 全文 54 行，主体是一段任务分流、一张派 agent 的表格和 9 条铁律。测试义务表、代码写法六条和文档更新对照表放在 `rules/code.md`，这份文件开头用 `paths:` 列了 15 种代码文件后缀（`.py`、`.ts`、`.go` 等），Claude Code 只在读写这些文件时加载它。

**任务分流**一段列了 4 个条件：这次改动触及 schema、migration、数据模型；触及 auth、权限、计费、判分；做不可逆数据操作；或者用户说了 plan、技术方案设计、规划、重构、架构。命中任何一条就加载 `skills/feature-workflow/SKILL.md`，一条都不命中就直接动手。这 4 个条件只看改动的性质——碰没碰数据结构、权限、钱、不可逆操作——不看改了几个文件、改动有多大。

加载之后，这份 skill 要求三件事。先在对话里贴一段不超过 10 行的说明，跟用户对齐：要做什么、不做什么、怎么算验收通过、有哪些高危假设，用户认可了再动手。再按 skill 里那张风险表，改动命中哪一条就在说明末尾回答对应的问题：migration 能不能回退；重复提交和重试是什么后果；外部输入在流进 prompt、SQL、shell 之前经过哪些边界检查；上线之后出问题怎么回滚。**之后的测试、实现、验证由主 session 自己做**，只有一种情况可以派 sub-agent：plan 里有 3 个以上互不依赖的工作单元时，可以派 `unit-developer` 并行做，同一个文件里的工作单元按顺序做，验收时主 session 审测试 diff，再亲自重跑全量测试。skill 开头还有一条「新机制先问一句」：版本管理、缓存层、抽象层这类用户没提的机制，想加之前先用一句话问用户，用户点头再做。

**测试义务表**在 `rules/code.md` 里，按改动内容分 5 档，同时命中多条时取最严的一条。改到计费、权限、判分、迁移的代码，或者做不可逆数据操作，必须写测试，按 test-first 做；改动含条件分支、计算、状态推导，按 test-first 做，最多 8 个用例；普通函数与模块之间的粘合代码，按 test-first 做，最多 4 个用例；纯样式与静态文案，跑起来验收，留下命令输出或截图；配置与文档，不要求测试。新增测试目录时先跑一次 `scripts/check-ci-reachability.sh`，再对照 CI 配置人工核对它的报告。CI 选不中的测试从不运行。

`scripts/check-ci-reachability.sh` 从 `git ls-files` 取测试文件清单，从 `.github/workflows/` 取真正跑测试的命令，逐个测试目录判定有没有哪条命令会跑这个目录里的测试，只要有一个目录没有命令跑就 `exit 1`。这个脚本目前会把没有命令跑的目录也报成可达，所以它的报告要人工核对，详见下面的「已知缺陷」。

任务分流和测试义务表的条件，动手的时候照着一条条对就能判定。`CLAUDE.md` 的 9 条铁律也一样，例如「跑命令拿输出再下结论」「审查意见先核实再处理」「push 由用户明确要求」。铁律沿用删减之前的编号，所以编号中间有空号。

**代码写法**六条也在 `rules/code.md` 里，管的是函数内部长什么样：主路径留在最外层，前置条件用 guard 挡在前面，条件超过两三条就收进一个命名的判定函数；名字答得出「这是什么」和「接下来发生什么」；外部服务的字段名止于适配层；类型只描述真实存在的状态；业务规则算成一个值，副作用另起一段，权限、计费、判分因此才测得动；错误同时给机器读的 code 和人读的 message。六条共用一个判断标准——让下一次改动更容易。

还有两块内容会改变你在每个仓库里的工作方式，装之前值得先看一眼。**仓库文档初始化**放在 `skills/repo-docs-init/`，要求每个仓库根目录有 `AGENTS.md` 作主入口，并指向 PROJECT / PATTERNS / TECHSTACK / DEVFLOW 四份内容文档；新建仓库、仓库缺其中任何一份、用户要求补项目文档时，模型加载这个 skill，先补文档再写业务代码。**文档更新对照表**放在 `rules/code.md`，规定改动触及什么就更新哪一份：产品的场景、用户、用法、要求或对标变了改 PROJECT.md，设计范式或代码约定变了改 PATTERNS.md，依赖、目录结构或核心 data model 变了改 TECHSTACK.md，构建测试部署流程变了改 DEVFLOW.md。纯实现细节、bugfix、不改这些约定的重构不用动文档。plan 文件什么时候更新 Status、什么时候删掉，写在 `CLAUDE.md` 铁律 1 后面。这两块不合你的习惯，就删掉这个 skill 或这张表，它们和三层机制之间没有依赖。

## 第二层：hooks 在工具层拦下操作

拿 `hooks/block-absolute-paths.sh` 举例。它挂在 PreToolUse 事件上，模型每次用 Write 或 Edit 写文件之前运行：从 stdin 的 JSON 里取要写的文件路径和新内容，先看文件后缀是不是代码或配置文件（`.py`、`.ts`、`.json`、`.sh` 等 12 种），再看这个文件在不在某个 git 仓库里、在不在 `.claude/` 目录之外。临时目录、`~/.claude/`、不在任何 git 仓库里的文件直接放行；worktree 虽然放在 `.claude/worktrees/` 下，里面的代码照查。剩下的文件，新内容里只要出现 `/Users/…`、`/home/…`、`C:\Users` 这类本机绝对路径，脚本就 `exit 2`，在 stderr 打印：「BLOCKED: 检测到绝对本地路径写入 <文件路径>。请改用 repo-relative 路径或环境变量，绝对路径部署到服务器后会 break。」

这次写入没有发生，模型拿到的是一条拒绝消息。「代码里不要写死本机路径」写在 prompt 里，模型可能照做也可能不照做；挂成 PreToolUse hook，脚本在每次写文件之前查一遍新内容，写死本机路径的内容就写不进文件。

4 个脚本各管一件事：

| 脚本 | 事件 | 拦什么 |
|---|---|---|
| `hooks/block-pip.sh` | PreToolUse · Bash | `pip install` / `pip uninstall`，放行 `uv pip` |
| `hooks/block-absolute-paths.sh` | PreToolUse · Write\|Edit | 往 git 仓库里、`.claude/` 之外的 `.py`、`.ts`、`.sh` 等代码与配置文件里写死 `/Users/…`、`/home/…`、`C:\Users`；worktree 里的代码照查，临时目录、`~/.claude/`、不在任何 git 仓库里的文件直接放行 |
| `hooks/session-context.sh` | SessionStart | 不拦任何操作。扫 cwd 下的 `.claude/plans/`，只扫一层，把未完成的 plan 连同 Status 注入上下文；已完成却没删的列成清理提醒。中文状态词（进行中、暂停、草稿、未开始、待用户验收、已完成）和对应的英文状态词都认得出，认不出的原样显示 Status 段的第一行，没有 Status 段的标「无 Status 段」；未完成的 plan 只展开前 8 个，其余在一行里点名，不会悄悄漏掉 |
| `hooks/check-prose-output.sh` | Stop | 不拦任何操作。本 session 加载过 `de-ai-writing` 时，把这一轮打给用户的正文喂给 `check.pl`，命中处列出来给用户看 |

脚本要拒绝一次操作，有两种写法，两种都写在 Claude Code 的 hook 协议里：`block-pip.sh` 输出带 `permissionDecision: "deny"` 的 JSON；`block-absolute-paths.sh` 用 `exit 2` 加 stderr。`hooks/tests/` 下有三份自测脚本：一份测 `block-absolute-paths.sh` 该拦和该放行的 8 种情况，另外两份测那两个不拦操作的 hook：

```
$ bash hooks/tests/test-block-absolute-paths.sh
ALL PASS

$ bash hooks/tests/test-session-context.sh
session-context.sh: 9 passed, 0 failed

$ bash hooks/tests/test-check-prose-output.sh
check-prose-output.sh: 5 passed, 0 failed
```

## 第三层：agents 把职责分开

### 不带背景的审查：只拿用户原话和成品

`agents/prose-auditor.md` 的 `tools` 只有 `Read`，文件头还写了 `omitClaudeMd: true`，Claude Code 启动它时不加载 `CLAUDE.md`、`AGENTS.md` 和 memory。派它的时候只给两样东西：用户在本次任务里发出的全部消息原文和成品的路径。草稿、调研档案、需求讨论、repo 里的代码，都不在它的输入里，它也不去找。

它判定两件事：一是仅凭这两样，读者能不能读懂；二是成品有没有回答用户真正问的问题。写成品的 agent 一路积累了大量背景，读自己写的句子时会自动把缺的意思补上，这类缺口它自己审不出来。审查者的上下文里没有这些背景，才不会跟着一起补。它读不到 `CLAUDE.md`，所以哪些问题算必修（数字写错、要读者做的事没写清、一句话能读出两种意思），直接写在它自己的定义文件里。

`agents/cold-reader.md` 把同一个思路往前挪到出稿阶段，文件头同样写了 `omitClaudeMd: true`。页面、文案、报告给用户看之前，派 3 个互不见面的实例，每个只拿到成品全文、一句读者人设、一句进入情境。它们逐块用自己的话复述、列出推不出含义的词、给每块信息归类（我的结果 / 教我怎么读的说明 / 让我做的事），再在撤走原文后只凭记住的要点答任务题。复述对不对由派发方对照事先写好的事实清单判，同一位置有 2 个以上实例出错才算缺陷；改完稿重测要换一批没读过旧稿的新实例。

### 6 个 agent

`general-purpose` 与 Claude Code 内置的 agent 同名，装上之后覆盖内置版本而不是并列存在；其余五个是新增的。Explore 和 Plan 直接用 Claude Code 内置的版本，本仓库不带它们的定义文件。

| 定义文件 | model | 职责 |
|---|---|---|
| `agents/general-purpose.md` | sonnet | 通用调研、盘点、多步执行 |
| `agents/unit-developer.md` | sonnet | 常规工作单元：从 spec 推导测试 → 在 stub 上确认红灯 → 实现到测试全部通过 |
| `agents/ui-designer.md` | opus | 界面设计，出稿前先取市面上的做法——查仓库里已有的竞品调研，没有就联网找对标产品——再按目标载体分两条路：网页类交付可在浏览器打开的 HTML 设计稿，macOS 原生界面交付可 `swift run` 打开的 AppKit 设计稿 |
| `agents/prose-finisher.md` | opus | 给面向人类读者的文字做去 AI 味收尾 |
| `agents/prose-auditor.md` | opus | 交付前的最后一道审查：只拿用户原话和成品 |
| `agents/cold-reader.md` | sonnet | 出稿闸门：零背景读者逐块复述、列生词、撤稿答题，三实例两票判缺陷 |

`ui-designer` 与 `prose-finisher` 在 frontmatter 里用 `skills:` 字段挂上 `interface-design` 与 `de-ai-writing`。派发这两个 agent 的时候，SKILL.md 正文会跟着进它们各自的上下文，主 session 不用读这两份合计 336 行的规则文件。

## hooks 挂在 settings.json 里

4 个 hook 都挂在全局的 `settings.json` 里，对所有 session、所有 agent 生效。`settings.example.json` 里挂了这 4 个 hook：`block-pip.sh`、`block-absolute-paths.sh`、`session-context.sh`、`check-prose-output.sh`。

## 安装

### 装之前先知道两件事

**这套配置接管你整个全局 Claude Code 配置**，不是并进去。下面的命令把 `CLAUDE.md`、`rules/code.md`、`agents`、`hooks`、`scripts`、`skills` 拷进 `~/.claude`，同名文件直接覆盖，你原有的同名内容就没了——先备份 `~/.claude` 再装。`settings.json` 本 repo 只给样例，你自己的权限配置、MCP server、statusline 要手工并进去。

**运行时依赖**：Claude Code（要支持 agent frontmatter 里的 `skills:` 与 `omitClaudeMd:` 字段，以及 `rules/` 文件开头的 `paths:` 字段）、bash、git、`jq`（hook 脚本解析工具调用的 JSON）。另外两个 skill 各自还要一样东西：`skills/de-ai-writing/scripts/check.pl` 与 `hooks/check-prose-output.sh` 要 Perl，`skills/interface-design/scripts/design-check.cjs` 要 Node 和 Playwright。这两样不装也不影响其余部分。`ui-designer` 设计 macOS 原生界面时要 Swift toolchain（`swift run`），这条路只在 macOS 上成立，设计网页不需要它。脚本按 macOS 与 Linux 写，没有在 Windows 上验证过。

### 装

```bash
git clone https://github.com/<你的账号>/claude-harness.git ~/Documents/claude-harness
cd ~/Documents/claude-harness

# 全局规则、写代码时的规则、agent、hook、脚本
cp CLAUDE.md ~/.claude/CLAUDE.md
mkdir -p ~/.claude/rules
cp rules/code.md ~/.claude/rules/code.md
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
rm -f ~/.claude/CLAUDE.md ~/.claude/settings.json ~/.claude/rules/code.md
rm -rf ~/.claude/agents ~/.claude/hooks ~/.claude/scripts
for s in feature-workflow de-ai-writing interface-design product-thinking push-code-to-main repo-docs-init; do
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

**在这些修掉之前，它返回退出码 0 不能当作「测试都在 CI 里跑得到」的证据**——所以 `rules/code.md` 的测试义务表、`feature-workflow` 和 `repo-docs-init` 都要求新增测试目录时先跑一次它，再对照 CI 配置人工核对它的报告。

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

`hooks/` 下的三份自测脚本不受影响，跑起来全部通过，输出贴在上面「第二层」那节。

## 6 个 skill

| skill | 做什么 |
|---|---|
| `skills/feature-workflow/` | 高危改动动手前先跟用户对齐：把不超过 10 行的说明贴进对话，按命中的风险条目逐条回答对应的问题，用户认可后，测试、实现、验证由主 session 自己做；plan 里有 3 个以上互不依赖的工作单元时，可以派 `unit-developer` 并行做；用户没提的机制，想加之前先问用户一句 |
| `skills/de-ai-writing/` | 去 AI 味写作流程：先收集材料再写，写完把读者会看到的句子提取出来跑 `skills/de-ai-writing/scripts/check.pl` 做残渣检测，要判断的那些检查连同改写一起交给没参与写作的 sub-agent。`skills/de-ai-writing/tests/` 是 check.pl 的回归语料，改规则之后跑 `bash tests/run.sh` 量召回与误报两个数 |
| `skills/interface-design/` | 界面设计的硬性要求，先定信息层级：十条规则，`skills/interface-design/scripts/design-check.cjs` 用真截图加灰度高斯模糊算出画面第一眼焦点，再映射回具体 DOM 元素 |
| `skills/product-thinking/` | 产品判断框架：评审提案、判需求真伪、立项写 PRD、给已有产品找「只改一处」。核心是一条五环证据链（具体的人与挣扎时刻、用户现在拿什么顶替、新价值翻不翻得过替换成本、证据分级、谁付钱），评审产出是指认最弱的一环；`references/` 放推导长文、案例与分梯队的阅读路径 |
| `skills/push-code-to-main/` | 开分支、commit、开 PR、squash 合并、删掉分支与 worktree、同步 main，合并后确认这个 repo 的 CI 结论 |
| `skills/repo-docs-init/` | 仓库文档初始化：新建仓库、仓库缺 `AGENTS.md` 或 PROJECT / PATTERNS / TECHSTACK / DEVFLOW 四份文档中的任何一份、用户要求补项目文档时加载。给出 `AGENTS.md` 的结构、四份文档各管什么、调查仓库时要查的清单和文档内容契约模板 |

## 我还装了这个第三方 skill

**女娲（`huashu-nuwa`）**：输入一个人名，或者只用一句话说个模糊需求，它去做调研、提炼思维框架，产出一个能直接运行的人物 skill。

本 repo 不含它，要自己去装：

- 上游 <https://github.com/alchaincyf/nuwa-skill>，MIT
- 装到 `~/.agents/skills/huashu-nuwa`

上面那段安装命令只拷本 repo `skills/` 下的 6 个 skill，`huashu-nuwa` 不在其中，装不装都不影响这套配置运转。那 6 个 skill 都是我写的，别人写的 skill 我只额外装了女娲这一个，它的出处就是上面那两行。仓库里还有几处材料来自别人，不用你另外安装任何东西，归属写在文末「License 与第三方材料」一节。

## 文档用什么语言写

中文为主：`CLAUDE.md`、`rules/code.md`，`feature-workflow`、`de-ai-writing`、`interface-design`、`product-thinking`、`repo-docs-init` 这 5 个 skill，加上 `general-purpose`、`unit-developer`、`ui-designer`、`prose-finisher`、`prose-auditor`、`cold-reader` 这 6 个 agent，正文都是中文。

`push-code-to-main` 这个 skill 的正文是英文。所有 agent 的 frontmatter `description` 中英文混着写，hook 脚本的注释也是。

## License 与第三方材料

这个仓库我按 MIT 许可证开源，许可证全文在 `LICENSE` 文件里。你可以自由使用、修改和分发它，商用也可以；分发出去的副本里，把 `LICENSE` 里的版权声明和许可声明一并带上就行。

仓库里的文件都是我写的，有三处例外——一个 agent 字段、两份调研存档里的引文、状态栏的 8 个颜色值，这三处来自别人。另外还有一处不是材料而是参考：`de-ai-writing` 的审查流程借鉴过 GitHub 上 `shuorenhua` 这个 skill 的结构。四条逐一写在下面，`LICENSE` 末尾有对应的英文版本。

- `agents/general-purpose.md` 里的 `description` 字段，是我从 Claude Code 内置的同名 agent 里逐字照抄的，这个字段的著作权归 Anthropic 所有。我照抄它，是因为 Claude Code 读 `description` 决定什么时候派这个 agent。这个字段一个字不改，这份文件覆盖掉内置版之后，派发时机跟内置版一样。这份文件的正文是我写的。
- `skills/de-ai-writing/references/research.md` 和 `skills/interface-design/references/research.md` 这两份调研存档里，我引用了 Nielsen Norman Group 的文章，也引用了 Edward Tufte、George Orwell、Ted Chiang、Paul Graham、余光中、汪曾祺、Verlyn Klinkenborg 等人写过的句子。这几个是分量最重的来源，不是全部——每一处引文都在原地注明了出处，完整名单在两份文件末尾的「信源列表」一节。引文的著作权归原作者所有。哪些句子入选、句子怎么翻译、引文后面的分析怎么写，都是我自己定的，按 MIT 许可证授权。
- `statusline-command.sh` 里的 8 个颜色值取自 Gruvbox 配色。Gruvbox 的作者是 Pavel Pertsev，按 MIT 许可证发布；这 8 个值连同各自的名字都写在那个脚本开头的注释里。
- `skills/de-ai-writing/` 的审查流程是我写的，写的时候参考过 GitHub 上 shuorenhua 这个 skill 的六步结构（<https://github.com/MrGeDiao/shuorenhua>）。shuorenhua 的文字我一句都没照抄。这个 skill 我在 `skills/de-ai-writing/references/research.md` 的信源列表里注明了。

想把其中一处单独拿去用，条件不一样，这里一次说清。Gruvbox 那 8 个颜色值按 MIT 发布，照抄进你自己的项目没有障碍。Anthropic 那个字段和调研存档里的引文，我都没有替你取得额外许可——把 `description` 搬进别的项目、或者转载某一处引文，这个判断是你自己的，我这边做到的是逐处标明出处。第四处是设计参考，没有材料需要许可。`LICENSE` 末尾把这几条用英文写了一遍，措辞更正式，说的是同一件事。
