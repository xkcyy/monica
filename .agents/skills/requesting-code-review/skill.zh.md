---
name: requesting-code-review
description: 完成任务、实现主要功能，或 merge 前需要验证工作是否满足要求时使用
---

# 请求 Code Review

派发 code reviewer subagent，在问题扩散前抓住它们。Reviewer 会收到精心构造的评估上下文，绝不会继承你的会话历史。这让 reviewer 专注于工作产物，而不是你的思考过程，也保留你自己的上下文用于继续工作。

**核心原则：**尽早 review，经常 review。

## 何时请求 Review

**强制：**
- subagent-driven development 的每个任务之后
- 完成主要功能之后
- merge 到 main 前

**可选但有价值：**
- 卡住时（新视角）
- 重构前（基线检查）
- 修复复杂 bug 后

## 如何请求

**1. 获取 git SHA：**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. 派发 code reviewer subagent：**

使用 Task 工具，类型为 `general-purpose`，填写 `code-reviewer.md` 模板

**占位符：**
- `{DESCRIPTION}` - 你构建内容的简要摘要
- `{PLAN_OR_REQUIREMENTS}` - 它应该做什么
- `{BASE_SHA}` - 起始 commit
- `{HEAD_SHA}` - 结束 commit

**3. 处理反馈：**
- 立即修复 Critical 问题
- 继续前修复 Important 问题
- 记录 Minor 问题稍后处理
- 如果 reviewer 错了，用理由反驳

## 示例

```
[刚完成 Task 2：Add verification function]

You: Let me request code review before proceeding.

BASE_SHA=$(git log --oneline | grep "Task 1" | head -1 | awk '{print $1}')
HEAD_SHA=$(git rev-parse HEAD)

[派发 code reviewer subagent]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
  PLAN_OR_REQUIREMENTS: Task 2 from docs/superpowers/plans/deployment-plan.md
  BASE_SHA: a7981ec
  HEAD_SHA: 3df7661

[Subagent 返回]:
  Strengths: Clean architecture, real tests
  Issues:
    Important: Missing progress indicators
    Minor: Magic number (100) for reporting interval
  Assessment: Ready to proceed

You: [修复 progress indicators]
[继续 Task 3]
```

## 与工作流集成

**Subagent-Driven Development：**
- 每个任务后 review
- 在问题叠加前抓住它们
- 修复后再进入下一个任务

**Executing Plans：**
- 每个任务后或自然检查点 review
- 获取反馈，应用反馈，继续

**Ad-Hoc Development：**
- merge 前 review
- 卡住时 review

## 红旗

**绝不要：**
- 因为"它很简单"就跳过 review
- 忽略 Critical 问题
- 带着未修复的 Important 问题继续
- 与有效的技术反馈争辩

**如果 reviewer 错了：**
- 用技术理由反驳
- 展示证明它可工作的代码/测试
- 请求澄清

模板见：requesting-code-review/code-reviewer.md
