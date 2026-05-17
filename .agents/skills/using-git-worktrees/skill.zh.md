---
name: using-git-worktrees
description: 开始需要与当前工作区隔离的功能工作，或执行实现计划前使用 - 确保存在隔离工作区，优先使用原生工具，必要时 fallback 到 git worktree
---

# 使用 Git Worktrees

## 概览

确保工作发生在隔离工作区中。优先使用平台原生的 worktree 工具。只有没有原生工具时，才 fallback 到手动 git worktree。

**核心原则：**先检测现有隔离。然后使用原生工具。然后 fallback 到 git。不要和 harness 对抗。

**开始时声明：**"我正在使用 using-git-worktrees skill 来设置隔离工作区。"

## 第 0 步：检测现有隔离

**创建任何东西之前，先检查自己是否已经处在隔离工作区。**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**Submodule guard：**在 git submodule 里，`GIT_DIR != GIT_COMMON` 也为 true。得出"已经在 worktree 中"结论前，先确认你不是在 submodule 中：

```bash
# If this returns a path, you're in a submodule, not a worktree — treat as normal repo
git rev-parse --show-superproject-working-tree 2>/dev/null
```

**如果 `GIT_DIR != GIT_COMMON`（且不是 submodule）：**你已经在 linked worktree 中。跳到第 3 步（项目设置）。不要再创建另一个 worktree。

带分支状态汇报：
- 在分支上："Already in isolated workspace at `<path>` on branch `<name>`."
- Detached HEAD："Already in isolated workspace at `<path>` (detached HEAD, externally managed). Branch creation needed at finish time."

**如果 `GIT_DIR == GIT_COMMON`（或在 submodule 中）：**你在普通 repo checkout 中。

用户是否已经在你的指令里说明了 worktree 偏好？如果没有，在创建 worktree 前请求同意：

> "Would you like me to set up an isolated worktree? It protects your current branch from changes."

如果已有偏好，直接遵守，不再询问。如果用户拒绝，就在原地工作并跳到第 3 步。

## 第 1 步：创建隔离工作区

**你有两种机制。按顺序尝试。**

### 1a. 原生 Worktree 工具（首选）

用户已经要求隔离工作区（第 0 步同意）。你是否已经有创建 worktree 的方式？它可能是名为 `EnterWorktree`、`WorktreeCreate` 的工具、`/worktree` 命令，或 `--worktree` flag。如果有，使用它并跳到第 3 步。

原生工具会自动处理目录放置、分支创建和清理。当你有原生工具时使用 `git worktree add`，会制造 harness 看不到也无法管理的幽灵状态。

只有没有原生 worktree 工具可用时，才继续到第 1b 步。

### 1b. Git Worktree Fallback

**只有第 1a 步不适用时才使用**，也就是没有原生 worktree 工具。用 git 手动创建 worktree。

#### 目录选择

按以下优先级。用户的显式偏好始终高于观察到的文件系统状态。

1. **检查你的指令中是否声明了 worktree 目录偏好。**如果用户已经指定，直接使用，不再询问。

2. **检查现有的项目本地 worktree 目录：**
   ```bash
   ls -d .worktrees 2>/dev/null     # Preferred (hidden)
   ls -d worktrees 2>/dev/null      # Alternative
   ```
   如果找到就使用。如果两者都存在，`.worktrees` 优先。

3. **检查现有的全局目录：**
   ```bash
   project=$(basename "$(git rev-parse --show-toplevel)")
   ls -d ~/.config/superpowers/worktrees/$project 2>/dev/null
   ```
   如果找到就使用（兼容 legacy 全局路径）。

4. **如果没有其他指导，**默认使用项目根目录下的 `.worktrees/`。

#### 安全验证（仅项目本地目录）

**创建 worktree 前必须验证目录已被 ignore：**

```bash
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

**如果没有被 ignore：**添加到 .gitignore，提交该变更，然后继续。

**为什么关键：**防止意外把 worktree 内容提交到 repository。

全局目录（`~/.config/superpowers/worktrees/`）不需要验证。

#### 创建 Worktree

```bash
project=$(basename "$(git rev-parse --show-toplevel)")

# Determine path based on chosen location
# For project-local: path="$LOCATION/$BRANCH_NAME"
# For global: path="~/.config/superpowers/worktrees/$project/$BRANCH_NAME"

git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

**Sandbox fallback：**如果 `git worktree add` 因 permission error（sandbox denial）失败，告诉用户 sandbox 阻止了 worktree 创建，你会改在当前目录工作。然后在原地运行 setup 和 baseline tests。

## 第 3 步：项目设置

自动检测并运行合适的 setup：

```bash
# Node.js
if [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

## 第 4 步：验证干净基线

运行测试，确保工作区一开始是干净的：

```bash
# Use project-appropriate command
npm test / cargo test / pytest / go test ./...
```

**如果测试失败：**汇报失败并询问是继续还是调查。

**如果测试通过：**汇报已就绪。

### 汇报

```
Worktree ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## 快速参考

| 情况 | 动作 |
|-----------|--------|
| 已在 linked worktree 中 | 跳过创建（第 0 步） |
| 在 submodule 中 | 视为普通 repo（第 0 步 guard） |
| 原生 worktree 工具可用 | 使用它（第 1a 步） |
| 无原生工具 | Git worktree fallback（第 1b 步） |
| `.worktrees/` 存在 | 使用它（验证已 ignore） |
| `worktrees/` 存在 | 使用它（验证已 ignore） |
| 两者都存在 | 使用 `.worktrees/` |
| 两者都不存在 | 检查指令文件，然后默认 `.worktrees/` |
| 全局路径存在 | 使用它（向后兼容） |
| 目录未 ignore | 添加到 .gitignore + commit |
| 创建时权限错误 | Sandbox fallback，原地工作 |
| baseline 测试失败 | 汇报失败 + 询问 |
| 没有 package.json/Cargo.toml | 跳过依赖安装 |

## 常见错误

### 与 harness 对抗

- **问题：**平台已经提供隔离时仍使用 `git worktree add`
- **修复：**第 0 步检测现有隔离。第 1a 步交给原生工具。

### 跳过检测

- **问题：**在已有 worktree 内创建嵌套 worktree
- **修复：**创建任何东西前始终运行第 0 步

### 跳过 ignore 验证

- **问题：**Worktree 内容被 track，污染 git status
- **修复：**创建项目本地 worktree 前始终使用 `git check-ignore`

### 假设目录位置

- **问题：**制造不一致，违反项目约定
- **修复：**遵循优先级：existing > global legacy > instruction file > default

### 带着失败测试继续

- **问题：**无法区分新 bug 和已有问题
- **修复：**汇报失败，获得明确许可后再继续

## 红旗

**绝不要：**
- 第 0 步检测到已有隔离时还创建 worktree
- 有原生 worktree 工具（例如 `EnterWorktree`）时使用 `git worktree add`。这是第一大错误，有就用它。
- 跳过第 1a 步，直接进入第 1b 的 git 命令
- 未验证 ignore 就创建 worktree（项目本地）
- 跳过 baseline 测试验证
- 未询问就带着失败测试继续

**始终：**
- 先运行第 0 步检测
- 优先使用原生工具，而不是 git fallback
- 遵循目录优先级：existing > global legacy > instruction file > default
- 对项目本地目录验证已 ignore
- 自动检测并运行项目 setup
- 验证干净测试基线
