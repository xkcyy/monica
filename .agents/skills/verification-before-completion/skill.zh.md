---
name: verification-before-completion
description: 在声称工作完成、已修复或通过之前使用，也用于 commit 或创建 PR 前 - 要求运行验证命令并确认输出，任何成功声明都必须先有证据
---

# 完成前验证

## 概览

没有验证就声称工作完成是不诚实，不是高效。

**核心原则：**永远先有证据，再做声明。

**违反这条规则的字面要求，就是违反这条规则的精神。**

## 铁律

```
没有新鲜的验证证据，就不能声称完成
```

如果你没有在本轮消息中运行验证命令，就不能声称它通过。

## 闸门函数

```
在声称任何状态或表达满意之前：

1. 识别：哪个命令能证明这个声明？
2. 运行：执行完整命令（新鲜、完整）
3. 阅读：阅读完整输出，检查退出码，统计失败数
4. 验证：输出是否确认该声明？
   - 如果否：用证据说明实际状态
   - 如果是：带着证据说明声明
5. 只有这之后：才做声明

跳过任何一步 = 撒谎，不是验证
```

## 常见失败

| 声明 | 需要 | 不足以证明 |
|-------|----------|----------------|
| 测试通过 | 测试命令输出：0 个失败 | 之前的运行、"应该通过" |
| Linter 干净 | Linter 输出：0 个错误 | 局部检查、推断 |
| Build 成功 | Build 命令：exit 0 | Linter 通过、日志看起来不错 |
| Bug 已修复 | 原始症状测试：通过 | 改了代码、假设已修复 |
| 回归测试有效 | 已验证 red-green cycle | 测试通过一次 |
| Agent 已完成 | VCS diff 显示变更 | Agent 报告 "success" |
| 满足要求 | 逐行 checklist | 测试通过 |

## 红旗 - 停止

- 使用 "should"、"probably"、"seems to"
- 验证前表达满意（"Great!"、"Perfect!"、"Done!" 等）
- 准备在未验证时 commit/push/PR
- 相信 agent 的成功报告
- 依赖部分验证
- 想着 "just this once"
- 疲惫并想结束工作
- **任何暗示成功但尚未运行验证的措辞**

## 防止合理化

| 借口 | 现实 |
|--------|---------|
| "Should work now" | 运行验证 |
| "I'm confident" | 信心不是证据 |
| "Just this once" | 没有例外 |
| "Linter passed" | Linter 不是编译器 |
| "Agent said success" | 独立验证 |
| "I'm tired" | 疲惫不是借口 |
| "Partial check is enough" | 部分检查什么都证明不了 |
| "Different words so rule doesn't apply" | 精神高于字面 |

## 关键模式

**测试：**
```
✅ [运行测试命令] [看到：34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**回归测试（TDD Red-Green）：**
```
✅ 写测试 -> 运行（pass）-> 回滚修复 -> 运行（必须失败）-> 恢复 -> 运行（pass）
❌ "I've written a regression test"（没有 red-green 验证）
```

**Build：**
```
✅ [运行 build] [看到：exit 0] "Build passes"
❌ "Linter passed"（linter 不检查编译）
```

**要求：**
```
✅ 重读计划 -> 创建 checklist -> 逐项验证 -> 汇报缺口或完成
❌ "Tests pass, phase complete"
```

**Agent 委派：**
```
✅ Agent 报告成功 -> 检查 VCS diff -> 验证变更 -> 汇报实际状态
❌ 相信 agent 报告
```

## 为什么这很重要

来自 24 条失败记忆：
- 你的人工协作者说过 "I don't believe you" - 信任被破坏
- 未定义函数被发布 - 会崩溃
- 缺失要求被发布 - 功能不完整
- 错误完成声明浪费时间 -> 转向 -> 重做
- 违反："Honesty is a core value. If you lie, you'll be replaced."

## 何时应用

**在以下情况之前始终应用：**
- 任何成功/完成声明的变体
- 任何满意表达
- 任何关于工作状态的正面陈述
- Commit、创建 PR、任务完成
- 进入下一个任务
- 委派给 agents

**规则适用于：**
- 精确短语
- 改写和同义表达
- 成功暗示
- 任何暗示完成/正确性的沟通

## 底线

**验证没有捷径。**

运行命令。阅读输出。然后再声明结果。

这是不可协商的。
