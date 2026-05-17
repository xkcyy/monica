---
name: acquire-codebase-knowledge
description: '当用户明确要求映射、记录或上手一个现有代码库时使用。触发提示包括 "map this codebase"、"document this architecture"、"onboard me to this repo" 或 "create codebase docs"。不要为常规功能实现、bugfix 或窄范围代码编辑触发，除非用户要求 repository-level discovery。'
license: MIT
compatibility: '跨平台。需要 Python 3.8+ 和 git。从目标项目根目录运行 scripts/scan.py。'
metadata:
  version: "1.3"
  enhancements:
    - 多语言 manifest 检测（支持 25+ 语言）
    - CI/CD pipeline 检测（10+ 平台）
    - Container 与 orchestration 检测
    - 按语言统计代码指标
    - Security 与 compliance 配置检测
    - Performance testing 标记
argument-hint: '可选：指定关注区域，例如 "architecture only"、"testing and concerns"'
---

# 获取代码库知识

在 `docs/codebase/` 中产出七份填充好的文档，覆盖高效参与项目所需的一切。只记录能从文件或终端输出验证的内容，绝不要推断或假设。

## 输出契约（必需）

结束前，以下条件必须全部为真：

1. `docs/codebase/` 中精确存在这些文件：`STACK.md`、`STRUCTURE.md`、`ARCHITECTURE.md`、`CONVENTIONS.md`、`INTEGRATIONS.md`、`TESTING.md`、`CONCERNS.md`。
2. 每个声明都可追溯到源文件、配置或终端输出。
3. 未知项标记为 `[TODO]`；依赖意图的决定标记为 `[ASK USER]`。
4. 每份文档都包含简短的 "evidence" 列表，列出具体文件路径。
5. 最终回复包含编号的 `[ASK USER]` 问题，以及 intent-vs-reality 差异。

## 工作流

复制并跟踪这个 checklist：

```
- [ ] Phase 1: Run scan, read intent documents
- [ ] Phase 2: Investigate each documentation area
- [ ] Phase 3: Populate all seven docs in docs/codebase/
- [ ] Phase 4: Validate docs, present findings, resolve all [ASK USER] items
```

## 关注区域模式

如果用户提供了关注区域（例如："architecture only" 或 "testing and concerns"）：

1. 始终完整运行 Phase 1。
2. 先完整完成关注区域对应的文档。
3. 对尚未分析的非关注文档，保留必需章节并将未知项标记为 `[TODO]`。
4. 最终输出前仍要对所有七份文档运行 Phase 4 validation loop。

### Phase 1：扫描并读取意图

1. 从目标项目根目录运行扫描脚本：
   ```bash
   python3 "$SKILL_ROOT/scripts/scan.py" --output docs/codebase/.codebase-scan.txt
   ```
   其中 `$SKILL_ROOT` 是 skill 文件夹的绝对路径。适用于 Windows、macOS 和 Linux。

   **快速开始：**如果你已直接有路径：
   ```bash
   python3 /absolute/path/to/skills/acquire-codebase-knowledge/scripts/scan.py --output docs/codebase/.codebase-scan.txt
   ```

2. 搜索 `PRD`、`TRD`、`README`、`ROADMAP`、`SPEC`、`DESIGN` 文件并阅读。
3. 在阅读任何源代码前，总结项目声明的意图。

### Phase 2：调查

使用扫描输出回答七个模板各自的问题。加载 [`references/inquiry-checkpoints.md`](references/inquiry-checkpoints.md)，获取完整的逐模板问题列表。

如果 stack 不明确（多个 manifest 文件、不熟悉的文件类型、没有 `package.json`），加载 [`references/stack-detection.md`](references/stack-detection.md)。

### Phase 3：填充模板

把 `assets/templates/` 中的每个模板复制到 `docs/codebase/`。按以下顺序填写：

1. [STACK.md](assets/templates/STACK.md) - 语言、运行时、框架、所有依赖
2. [STRUCTURE.md](assets/templates/STRUCTURE.md) - 目录布局、入口点、关键文件
3. [ARCHITECTURE.md](assets/templates/ARCHITECTURE.md) - 层、模式、数据流
4. [CONVENTIONS.md](assets/templates/CONVENTIONS.md) - 命名、格式、错误处理、imports
5. [INTEGRATIONS.md](assets/templates/INTEGRATIONS.md) - 外部 API、数据库、auth、monitoring
6. [TESTING.md](assets/templates/TESTING.md) - 框架、文件组织、mocking 策略
7. [CONCERNS.md](assets/templates/CONCERNS.md) - 技术债、bug、安全风险、性能瓶颈

对代码无法确定的任何内容使用 `[TODO]`。需要团队意图才能回答的内容使用 `[ASK USER]`。

### Phase 4：校验、修复、验证

最终完成前运行这个强制 validation loop：

1. 根据 `references/inquiry-checkpoints.md` 验证每份文档。
2. 对每个非平凡声明，确认至少存在一个 evidence reference。
3. 如果任何必需章节缺失或缺少支持：
  - 修复文档。
  - 重新运行 validation。
4. 重复直到七份文档全部通过。

然后呈现七份文档摘要，把每个 `[ASK USER]` 项列成编号问题，并突出 Phase 1 中的 Intent vs. Reality 差异。

Validation 通过标准：

- 没有 unsupported claims。
- 没有空的必需章节。
- 未知项使用 `[TODO]`，而不是假设。
- 团队意图缺口明确标记为 `[ASK USER]`。

---

## 易错点

**Monorepos：**根 `package.json` 可能没有源码，要检查 `workspaces`、`packages/` 或 `apps/` 目录。每个 workspace 可能有独立依赖和约定。分别映射每个子包。

**过时 README：**README 经常描述的是意图架构，而不是当前架构。把任何 README 声明当事实前，要与实际文件结构交叉验证。

**TypeScript path aliases：**`tsconfig.json` 的 `paths` 配置意味着像 `@/foo` 这样的 imports 不会直接映射到文件系统。记录结构前先把 aliases 映射到真实路径。

**生成/编译输出：**绝不要从 `dist/`、`build/`、`generated/`、`.next/`、`out/` 或 `__pycache__/` 记录模式。这些是 artefacts，只记录源码约定。

**`.env.example` 暴露必需配置：**Secrets 绝不会提交。读取 `.env.example`、`.env.template` 或 `.env.sample` 来发现必需环境变量。

**`devDependencies` 不等于生产 stack：**只有 `dependencies`（或等价项，例如 `[tool.poetry.dependencies]`）在生产运行。单独把 linters、formatters 和测试框架记录为开发工具。

**测试 TODO 不等于生产债务：**`test/`、`tests/`、`__tests__/` 或 `spec/` 中的 TODO 是 coverage gaps，不是生产技术债。要在 `CONCERNS.md` 中区分。

**高变更文件 = 脆弱区域：**近期 git 历史中出现最多的文件变更率最高，通常有隐藏复杂度。始终在 `CONCERNS.md` 中记录它们。

---

## 反模式

| ❌ 不要 | ✅ 改为 |
|---------|--------------|
| "Uses Clean Architecture with Domain/Data layers."（当这些目录不存在时） | 只陈述目录结构实际显示的内容。 |
| "This is a Next.js project."（没检查 `package.json`） | 先检查 `dependencies`。陈述实际存在的内容。 |
| 从 `dbUrl` 这样的变量名猜数据库 | 检查 manifest 中是否有 `pg`、`mysql2`、`mongoose`、`prisma` 等。 |
| 把 `dist/` 或 `build/` 的命名模式记录为约定 | 只记录源文件。 |

---

## 增强扫描输出章节

`scan.py` 脚本现在会在原始输出之外产出以下章节：

- **CODE METRICS** - 总文件数、按语言统计的代码行数、最大文件（复杂度信号）
- **CI/CD PIPELINES** - 检测到的 GitHub Actions、GitLab CI、Jenkins、CircleCI 等
- **CONTAINERS & ORCHESTRATION** - Docker、Docker Compose、Kubernetes、Vagrant configs
- **SECURITY & COMPLIANCE** - Snyk、Dependabot、SECURITY.md、SBOM、security policies
- **PERFORMANCE & TESTING** - Benchmark configs、profiling markers、load testing tools

在 Phase 2 中使用这些章节来指导调查问题，并识别工具特定模式。

---

## Bundled Assets

| Asset | 何时加载 |
|-------|-------------|
| [`scripts/scan.py`](scripts/scan.py) | Phase 1 - 最先运行，早于阅读任何代码（需要 Python 3.8+） |

| [`references/inquiry-checkpoints.md`](references/inquiry-checkpoints.md) | Phase 2 - 加载逐模板调查问题 |
| [`references/stack-detection.md`](references/stack-detection.md) | Phase 2 - 仅在 stack 不明确时加载 |
| [`assets/templates/STACK.md`](assets/templates/STACK.md) | Phase 3 第 1 步 |
| [`assets/templates/STRUCTURE.md`](assets/templates/STRUCTURE.md) | Phase 3 第 2 步 |
| [`assets/templates/ARCHITECTURE.md`](assets/templates/ARCHITECTURE.md) | Phase 3 第 3 步 |
| [`assets/templates/CONVENTIONS.md`](assets/templates/CONVENTIONS.md) | Phase 3 第 4 步 |
| [`assets/templates/INTEGRATIONS.md`](assets/templates/INTEGRATIONS.md) | Phase 3 第 5 步 |
| [`assets/templates/TESTING.md`](assets/templates/TESTING.md) | Phase 3 第 6 步 |
| [`assets/templates/CONCERNS.md`](assets/templates/CONCERNS.md) | Phase 3 第 7 步 |

模板使用模式：

- 默认模式：只完成每个模板的 "Core Sections (Required)"。
- 扩展模式：仅当 repo 复杂度需要时，添加可选章节。
