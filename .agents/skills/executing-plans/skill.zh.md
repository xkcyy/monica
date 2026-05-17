---
name: executing-plans
description: 当你有一份需要在独立会话中执行、并带有 review 检查点的书面实现计划时使用
---

# 执行计划

## 概览

加载计划，严格 review，执行所有任务，并在完成后汇报。

**开始时声明：**"我正在使用 executing-plans skill 来实现这份计划。"

**注意：**告诉你的人工协作者，Superpowers 在可以访问 subagent 时效果会好得多。如果运行在支持 subagent 的平台上（例如 Claude Code 或 Codex），工作质量会显著更高。如果 subagent 可用，请使用 superpowers:subagent-driven-development，而不是本 skill。

## 流程

### 第 1 步：加载并 review 计划
1. 阅读计划文件
2. 严格 review，识别计划中的问题或疑虑
3. 如果有疑虑：在开始前向人工协作者提出
4. 如果没有疑虑：创建 TodoWrite 并继续

### 第 2 步：执行任务

对每个任务：
1. 标记为 in_progress
2. 严格按每一步执行（计划中的步骤已经被拆成小块）
3. 按指定方式运行验证
4. 标记为 completed

### 第 3 步：完成开发

所有任务完成并通过验证后：
- 声明："我正在使用 finishing-a-development-branch skill 来完成这项工作。"
- **必需子 skill：**使用 superpowers:finishing-a-development-branch
- 按该 skill 执行测试验证、呈现选项并执行所选流程

## 何时停止并请求帮助

**遇到以下情况时立即停止执行：**
- 遇到阻塞点（缺少依赖、测试失败、指令不清楚）
- 计划存在导致无法开始的关键缺口
- 不理解某条指令
- 验证反复失败

**请求澄清，不要猜测。**

## 何时回到前面的步骤

**以下情况回到 Review（第 1 步）：**
- 协作者根据你的反馈更新了计划
- 基本方案需要重新思考

**不要硬闯阻塞点**，停下来询问。

## 记住
- 先严格 review 计划
- 严格按计划步骤执行
- 不要跳过验证
- 计划要求使用 skill 时必须引用
- 遇到阻塞就停止，不要猜
- 未经用户明确同意，绝不要在 main/master 分支上开始实现

## 集成

**必需工作流 skill：**
- **superpowers:using-git-worktrees** - 确保隔离工作区存在（创建一个或验证当前已有）
- **superpowers:writing-plans** - 创建本 skill 所执行的计划
- **superpowers:finishing-a-development-branch** - 所有任务完成后的开发收尾
