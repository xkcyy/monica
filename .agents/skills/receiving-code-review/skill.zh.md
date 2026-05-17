---
name: receiving-code-review
description: 收到 code review 反馈、准备实现建议前使用，尤其是反馈不清晰或技术上可疑时 - 要求技术严谨和验证，而不是表演式认同或盲目实现
---

# 接收 Code Review

## 概览

Code review 需要技术评估，而不是情绪表演。

**核心原则：**先验证，再实现。先询问，再假设。技术正确性高于社交舒适感。

## 响应模式

```
收到 code review 反馈时：

1. 阅读：完整阅读反馈，不急着反应
2. 理解：用自己的话复述要求（或询问）
3. 验证：对照代码库现实检查
4. 评估：对这个代码库来说技术上是否成立？
5. 响应：技术性确认或有理由地反驳
6. 实现：一次处理一项，每项都测试
```

## 禁止的回应

**绝不要：**
- "You're absolutely right!"（明确违反 CLAUDE.md）
- "Great point!" / "Excellent feedback!"（表演式）
- "Let me implement that now"（尚未验证）

**改为：**
- 复述技术要求
- 提出澄清问题
- 如果错误，用技术理由反驳
- 直接开始工作（行动 > 语言）

## 处理不清楚的反馈

```
如果任何一项不清楚：
  停止 - 先不要实现任何内容
  针对不清楚的项请求澄清

原因：各项可能相关。部分理解 = 错误实现。
```

**示例：**
```
your human partner: "Fix 1-6"
你理解 1、2、3、6。不清楚 4、5。

❌ 错误：现在实现 1、2、3、6，稍后再问 4、5
✅ 正确："我理解 1、2、3、6。继续前需要澄清第 4 和第 5 项。"
```

## 按来源处理

### 来自你的人工协作者
- **可信** - 理解后实现
- **范围不清时仍要询问**
- **不要表演式认同**
- **直接行动**或给出技术性确认

### 来自外部 Reviewer
```
实现前：
  1. 检查：对这个代码库来说技术上正确吗？
  2. 检查：会破坏现有功能吗？
  3. 检查：当前实现是否有原因？
  4. 检查：是否适用于所有平台/版本？
  5. 检查：reviewer 是否理解完整上下文？

如果建议看起来错误：
  用技术理由反驳

如果无法轻易验证：
  明说："没有 [X] 我无法验证。要我 [调查/询问/继续] 吗？"

如果与人工协作者之前的决定冲突：
  停下来先和人工协作者讨论
```

**你的人工协作者规则：**"External feedback - be skeptical, but check carefully"

## 针对 "Professional" 功能的 YAGNI 检查

```
如果 reviewer 建议 "implementing properly"：
  grep 代码库查看实际使用情况

  如果未使用："这个 endpoint 没有被调用。要删除它（YAGNI）吗？"
  如果已使用：再正确实现
```

**你的人工协作者规则：**"You and reviewer both report to me. If we don't need this feature, don't add it."

## 实现顺序

```
对于多项反馈：
  1. 先澄清所有不清楚的内容
  2. 然后按以下顺序实现：
     - 阻塞问题（破坏功能、安全问题）
     - 简单修复（拼写、import）
     - 复杂修复（重构、逻辑）
  3. 每个修复单独测试
  4. 验证没有回归
```

## 何时反驳

以下情况需要反驳：
- 建议会破坏现有功能
- Reviewer 缺少完整上下文
- 违反 YAGNI（未使用的功能）
- 对当前技术栈来说技术上不正确
- 存在 legacy/兼容性原因
- 与人工协作者的架构决策冲突

**如何反驳：**
- 用技术理由，不要防御性表达
- 提出具体问题
- 引用可工作的测试/代码
- 架构问题让人工协作者参与

**如果你不方便把反驳直接说出口，用这个信号：**"Strange things are afoot at the Circle K"

## 确认正确反馈

当反馈确实正确时：
```
✅ "Fixed. [Brief description of what changed]"
✅ "Good catch - [specific issue]. Fixed in [location]."
✅ [直接修复并在代码中展示]

❌ "You're absolutely right!"
❌ "Great point!"
❌ "Thanks for catching that!"
❌ "Thanks for [anything]"
❌ 任何感谢表达
```

**为什么不说感谢：**行动说明一切。直接修复。代码本身会显示你听到了反馈。

**如果你发现自己要写 "Thanks"：**删掉它，说明修复内容。

## 优雅纠正自己的反驳

如果你反驳了但后来发现自己错了：
```
✅ "You were right - I checked [X] and it does [Y]. Implementing now."
✅ "Verified this and you're correct. My initial understanding was wrong because [reason]. Fixing."

❌ 长篇道歉
❌ 为为什么反驳辩护
❌ 过度解释
```

客观说明修正事实，然后继续。

## 常见错误

| 错误 | 修复 |
|---------|-----|
| 表演式认同 | 陈述要求或直接行动 |
| 盲目实现 | 先对照代码库验证 |
| 批量处理但不测试 | 一次一项，每项测试 |
| 假设 reviewer 一定正确 | 检查是否会破坏功能 |
| 避免反驳 | 技术正确性 > 舒适感 |
| 部分实现 | 先澄清所有项 |
| 无法验证却继续 | 说明限制，请求方向 |

## 真实示例

**表演式认同（坏）：**
```
Reviewer: "Remove legacy code"
❌ "You're absolutely right! Let me remove that..."
```

**技术验证（好）：**
```
Reviewer: "Remove legacy code"
✅ "Checking... build target is 10.15+, this API needs 13+. Need legacy for backward compat. Current impl has wrong bundle ID - fix it or drop pre-13 support?"
```

**YAGNI（好）：**
```
Reviewer: "Implement proper metrics tracking with database, date filters, CSV export"
✅ "Grepped codebase - nothing calls this endpoint. Remove it (YAGNI)? Or is there usage I'm missing?"
```

**不清楚的项（好）：**
```
your human partner: "Fix items 1-6"
你理解 1、2、3、6。不清楚 4、5。
✅ "Understand 1,2,3,6. Need clarification on 4 and 5 before implementing."
```

## GitHub Thread 回复

回复 GitHub 的 inline review comments 时，要回复在评论线程里（`gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`），不要作为顶层 PR 评论。

## 底线

**外部反馈 = 需要评估的建议，不是必须遵守的命令。**

验证。质疑。然后实现。

不要表演式认同。始终保持技术严谨。
