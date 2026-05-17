---
name: finishing-a-development-branch
description: 当实现已完成、所有测试通过，并且需要决定如何集成这项工作时使用 - 通过提供结构化选项来指导 merge、PR 或清理
---

# 完成开发分支

## 概览

通过呈现清晰选项并执行所选工作流，指导开发工作的收尾。

**核心原则：**验证测试 -> 检测环境 -> 呈现选项 -> 执行选择 -> 清理。

**开始时声明：**"我正在使用 finishing-a-development-branch skill 来完成这项工作。"

## 流程

### 第 1 步：验证测试

**在呈现选项之前，确认测试通过：**

```bash
# Run project's test suite
npm test / cargo test / pytest / go test ./...
```

**如果测试失败：**
```
测试失败（<N> 个失败）。完成前必须修复：

[显示失败信息]

测试通过前不能继续 merge/PR。
```

停止。不要继续到第 2 步。

**如果测试通过：**继续第 2 步。

### 第 2 步：检测环境

**呈现选项前先确定工作区状态：**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
```

这会决定显示哪种菜单，以及清理如何执行：

| 状态 | 菜单 | 清理 |
|-------|------|---------|
| `GIT_DIR == GIT_COMMON`（普通 repo） | 标准 4 个选项 | 没有 worktree 需要清理 |
| `GIT_DIR != GIT_COMMON`，命名分支 | 标准 4 个选项 | 基于来源清理（见第 6 步） |
| `GIT_DIR != GIT_COMMON`，detached HEAD | 精简 3 个选项（无 merge） | 不清理（由外部管理） |

### 第 3 步：确定基础分支

```bash
# Try common base branches
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

或者询问："这个分支是从 main 分出来的，对吗？"

### 第 4 步：呈现选项

**普通 repo 和命名分支 worktree：必须精确呈现这 4 个选项：**

```
实现已完成。你想怎么处理？

1. 本地 merge 回 <base-branch>
2. Push 并创建 Pull Request
3. 保持分支现状（我稍后处理）
4. 丢弃这项工作

选择哪一项？
```

**Detached HEAD：必须精确呈现这 3 个选项：**

```
实现已完成。你当前在 detached HEAD（外部管理的工作区）。

1. 作为新分支 push 并创建 Pull Request
2. 保持现状（我稍后处理）
3. 丢弃这项工作

选择哪一项？
```

**不要添加解释**，保持选项简洁。

### 第 5 步：执行选择

#### 选项 1：本地 Merge

```bash
# Get main repo root for CWD safety
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

# Merge first — verify success before removing anything
git checkout <base-branch>
git pull
git merge <feature-branch>

# Verify tests on merged result
<test command>

# Only after merge succeeds: cleanup worktree (Step 6), then delete branch
```

然后：清理 worktree（第 6 步），再删除分支：

```bash
git branch -d <feature-branch>
```

#### 选项 2：Push 并创建 PR

```bash
# Push branch
git push -u origin <feature-branch>

# Create PR
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<2-3 bullets of what changed>

## Test Plan
- [ ] <verification steps>
EOF
)"
```

**不要清理 worktree**，用户需要它继续处理 PR 反馈。

#### 选项 3：保持现状

汇报："保留分支 <name>。Worktree 保留在 <path>。"

**不要清理 worktree。**

#### 选项 4：丢弃

**先确认：**
```
这会永久删除：
- 分支 <name>
- 所有提交：<commit-list>
- 位于 <path> 的 worktree

输入 'discard' 确认。
```

等待精确确认。

如果已确认：
```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
```

然后：清理 worktree（第 6 步），再强制删除分支：
```bash
git branch -D <feature-branch>
```

### 第 6 步：清理工作区

**只对选项 1 和 4 运行。**选项 2 和 3 始终保留 worktree。

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

**如果 `GIT_DIR == GIT_COMMON`：**普通 repo，没有 worktree 需要清理。完成。

**如果 worktree 路径位于 `.worktrees/`、`worktrees/` 或 `~/.config/superpowers/worktrees/` 下：**这是 Superpowers 创建的 worktree，我们负责清理。

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git worktree remove "$WORKTREE_PATH"
git worktree prune  # Self-healing: clean up any stale registrations
```

**否则：**宿主环境（harness）拥有这个工作区。不要删除它。如果平台提供退出工作区的工具，使用该工具。否则保留工作区。

## 快速参考

| 选项 | Merge | Push | 保留 Worktree | 清理分支 |
|--------|-------|------|---------------|----------------|
| 1. 本地 merge | 是 | - | - | 是 |
| 2. 创建 PR | - | 是 | 是 | - |
| 3. 保持现状 | - | - | 是 | - |
| 4. 丢弃 | - | - | - | 是（强制） |

## 常见错误

**跳过测试验证**
- **问题：**Merge 损坏代码，创建失败的 PR
- **修复：**提供选项前始终验证测试

**开放式问题**
- **问题：**"下一步我该做什么？"含糊不清
- **修复：**精确呈现 4 个结构化选项（detached HEAD 时为 3 个）

**为选项 2 清理 worktree**
- **问题：**删除用户迭代 PR 反馈所需的 worktree
- **修复：**只为选项 1 和 4 清理

**删除分支早于移除 worktree**
- **问题：**`git branch -d` 失败，因为 worktree 仍引用该分支
- **修复：**先 merge，移除 worktree，再删除分支

**在 worktree 内部运行 git worktree remove**
- **问题：**当 CWD 位于将被删除的 worktree 内时，命令会静默失败
- **修复：**运行 `git worktree remove` 前始终 `cd` 到主 repo 根目录

**清理 harness 拥有的 worktree**
- **问题：**删除 harness 创建的 worktree 会造成幽灵状态
- **修复：**只清理 `.worktrees/`、`worktrees/` 或 `~/.config/superpowers/worktrees/` 下的 worktree

**丢弃时没有确认**
- **问题：**意外删除工作
- **修复：**要求输入 "discard" 确认

## 红旗

**绝不要：**
- 在测试失败时继续
- 未验证 merge 后结果就 merge
- 未确认就删除工作
- 未经明确要求就 force-push
- 未确认 merge 成功就移除 worktree
- 清理不是你创建的 worktree（检查来源）
- 在 worktree 内部运行 `git worktree remove`

**始终：**
- 提供选项前验证测试
- 呈现菜单前检测环境
- 精确呈现 4 个选项（detached HEAD 时为 3 个）
- 为选项 4 获取输入确认
- 只为选项 1 和 4 清理 worktree
- 删除 worktree 前 `cd` 到主 repo 根目录
- 移除后运行 `git worktree prune`
