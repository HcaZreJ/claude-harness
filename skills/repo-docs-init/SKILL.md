---
name: repo-docs-init
description: 仓库文档初始化。新建仓库、仓库缺 AGENTS.md 或 PROJECT.md / PATTERNS.md / TECHSTACK.md / DEVFLOW.md 任一份、用户要求补项目文档时加载：给出 AGENTS.md 的结构、四份文档各管什么、调查清单和文档内容契约模板。
---

# 仓库文档初始化

## 文档结构

每个仓库以根目录 `AGENTS.md` 为主入口，`CLAUDE.md` 只有一行 `@AGENTS.md`。AGENTS.md 给出文档地图、文档内容契约、本仓库铁律，指向四份内容文档：

- **PROJECT.md** — 产品视角：项目目的、使用场景、目标用户、核心功能与使用方式、技术/设计/交互/产品上的要求、市场最接近的对标产品
- **PATTERNS.md** — 可复用设计范式：架构原则、数据建模、模块边界、命名、函数签名、代码模式、刻意省略的设计
- **TECHSTACK.md** — 技术栈、依赖、数据库与核心 data model 概览、外部服务、目录结构与模块地图、环境变量、端口
- **DEVFLOW.md** — 本地开发、运行/测试/构建/迁移/部署命令、分支工作流、CI/CD 速查

铁律只收全仓、所有任务都成立的条目，每条一两句并指向细则。只在某个代码目录成立的约束，细则写进 PATTERNS.md，该目录的 AGENTS.md 写一句指针（同目录 CLAUDE.md 一行 `@AGENTS.md`），读该目录的文件时自动加载。

## 补文档的步骤

仓库缺 AGENTS.md 或四份内容文档任一份时，先补齐再写业务代码。派 general-purpose agent 只读调查仓库，按下面的清单交回事实，据它的产出补齐；文档里只用仓库的真实命令和事实。

调查清单 · 技术栈：
1. 依赖清单（`pyproject.toml`、`package.json`、`go.mod`、`Cargo.toml`、构建文件），每个依赖按用途归类。
2. 架构：`src/`、`app/`、`services/`、`models/`、`routes/` 等目录，Service Class 模式（`*Service`、`*Manager`、`*Handler`），配置的位置。
3. 数据库：迁移目录、ORM 模型、数据库配置、docker-compose 里的服务。
4. 外部服务：API 客户端、SDK、webhook、第三方配置。
5. 代码约定：命名风格、import 组织、错误处理模式、类型标注。

调查清单 · 开发流程：
1. Docker：服务、卷、端口、引用的环境变量、镜像里拷进了哪些目录。
2. 环境变量：读 `.env.example` 一类模板并 grep 代码里的读取处，分必需 / 可选、密钥 / 配置；`.env` 本身不读。
3. CI/CD：每个 workflow 的触发条件、步骤、测试/lint/构建阶段、哪个分支部署到哪。写出每个 job 跑测试的确切命令和它选中的测试路径；有测试目录没被任何 job 选中时，报出来并附文件数。
4. 测试基础设施：测试目录、框架、配置、fixture；数测试文件时排除 `.venv`、`site-packages`、`node_modules`。
5. 本地开发：Makefile、package.json scripts、启动命令、种子数据。
6. 构建与部署：构建命令、产物、部署目标、基础设施代码。

新增测试目录时跑 `~/.claude/scripts/check-ci-reachability.sh <repo>`，再对照 CI 配置人工核对报告（它会把没有 job 跑的目录也报成可达）。

## 文档内容契约模板

新仓库 AGENTS.md 的「文档内容契约」照此写，按仓库实际增删：

| 这次改动触及 | 就更新 |
|---|---|
| 项目目的、使用场景、目标用户、核心功能或使用方式、技术·设计·交互·产品要求、对标产品变化 | PROJECT.md |
| 新设计范式、数据建模规则、代码约定、新增扩展点配方 | PATTERNS.md |
| 加换删依赖、新框架·外部服务·数据库、目录结构调整、模块增减或职责变、核心 data model 变、环境变量增减 | TECHSTACK.md |
| 构建·测试·运行·迁移·部署命令或流程、CI 闸门、分支工作流 | DEVFLOW.md |
| 完成某 work-unit | 从 BACKLOG.md 移走 |
| 正在执行某 plan | 更新该 plan 的 Status |
| 完成某 plan | 删除该 plan 文件 |
| 长期或未来想做的事 | GitHub issues |
| 只在某个代码目录成立的新硬约束 | 细则写进 PATTERNS.md，该目录的 AGENTS.md 写一句指针；根 AGENTS.md 的铁律只收全仓所有任务都成立的条目 |

纯实现细节、bugfix、不改上述约定的重构，不更新文档。
