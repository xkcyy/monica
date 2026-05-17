---
name: systematic-debugging
description: 遇到任何 bug、测试失败或异常行为时，在提出修复方案前使用
---

# 系统化调试

## 概览

随机修复会浪费时间并制造新 bug。快速补丁会掩盖底层问题。

**核心原则：**在尝试修复前，始终先找到根因。修症状就是失败。

**违反这个流程的字面要求，就是违反调试的精神。**

## 铁律

```
没有先做根因调查，就不能修复
```

如果你还没有完成第 1 阶段，就不能提出修复方案。

## 何时使用

用于任何技术问题：
- 测试失败
- 生产 bug
- 异常行为
- 性能问题
- Build 失败
- 集成问题

**尤其在以下情况使用：**
- 时间压力下（紧急情况会诱使你猜）
- "只做一个快速修复" 看起来很明显
- 你已经尝试过多个修复
- 之前的修复没有用
- 你没有完全理解问题

**不要跳过：**
- 问题看起来简单（简单 bug 也有根因）
- 你很赶（赶工保证返工）
- 经理要求现在就修好（系统化比乱试更快）

## 四个阶段

进入下一阶段前，你必须完成当前阶段。

### 第 1 阶段：根因调查

**在尝试任何修复前：**

1. **仔细阅读错误信息**
   - 不要跳过错误或警告
   - 它们通常包含精确解法
   - 完整阅读 stack traces
   - 记录行号、文件路径、错误码

2. **稳定复现**
   - 你能可靠触发它吗？
   - 精确步骤是什么？
   - 每次都会发生吗？
   - 如果不可复现 -> 收集更多数据，不要猜

3. **检查最近变更**
   - 哪些变更可能导致这个问题？
   - Git diff、recent commits
   - 新依赖、配置变更
   - 环境差异

4. **在多组件系统中收集证据**

   **当系统有多个组件时（CI -> build -> signing，API -> service -> database）：**

   **提出修复前，添加诊断 instrumentation：**
   ```
   对每个组件边界：
     - 记录进入组件的数据
     - 记录离开组件的数据
     - 验证环境/配置是否正确传播
     - 检查每一层的状态

   运行一次以收集证据，显示哪里断了
   然后分析证据，识别失败组件
   然后调查该特定组件
   ```

   **示例（多层系统）：**
   ```bash
   # Layer 1: Workflow
   echo "=== Secrets available in workflow: ==="
   echo "IDENTITY: ${IDENTITY:+SET}${IDENTITY:-UNSET}"

   # Layer 2: Build script
   echo "=== Env vars in build script: ==="
   env | grep IDENTITY || echo "IDENTITY not in environment"

   # Layer 3: Signing script
   echo "=== Keychain state: ==="
   security list-keychains
   security find-identity -v

   # Layer 4: Actual signing
   codesign --sign "$IDENTITY" --verbose=4 "$APP"
   ```

   **这会揭示：**哪一层失败（secrets -> workflow ✓，workflow -> build ✗）

5. **追踪数据流**

   **当错误深处于 call stack 中时：**

   阅读本目录下的 `root-cause-tracing.md`，获取完整的反向追踪技术。

   **快速版：**
   - 坏值从哪里来？
   - 是谁用坏值调用了这里？
   - 持续向上追踪，直到找到源头
   - 在源头修复，而不是在症状处修复

### 第 2 阶段：模式分析

**修复前先找到模式：**

1. **寻找可工作的示例**
   - 在同一代码库中找到相似且可工作的代码
   - 与坏掉的部分相似的可工作内容是什么？

2. **对照参考实现**
   - 如果在实现某种模式，完整阅读参考实现
   - 不要略读，要读每一行
   - 完全理解模式后再应用

3. **识别差异**
   - 可工作版本和坏掉版本有什么不同？
   - 列出每个差异，无论多小
   - 不要假设"那个不重要"

4. **理解依赖**
   - 它需要哪些其他组件？
   - 需要哪些设置、配置、环境？
   - 它假设了什么？

### 第 3 阶段：假设与测试

**科学方法：**

1. **形成单一假设**
   - 清楚陈述："我认为 X 是根因，因为 Y"
   - 写下来
   - 要具体，不要含糊

2. **最小化测试**
   - 做尽可能小的改动来测试假设
   - 一次只改一个变量
   - 不要一次修多个东西

3. **继续前验证**
   - 有效吗？是 -> 第 4 阶段
   - 无效？形成新假设
   - 不要在上面叠加更多修复

4. **当你不知道时**
   - 说 "I don't understand X"
   - 不要假装知道
   - 请求帮助
   - 做更多研究

### 第 4 阶段：实现

**修复根因，不修症状：**

1. **创建失败测试用例**
   - 最简单的复现
   - 尽可能用自动化测试
   - 没有测试框架时用一次性测试脚本
   - 修复前必须有
   - 使用 `superpowers:test-driven-development` skill 编写正确的失败测试

2. **实现单一修复**
   - 处理已识别的根因
   - 一次只改一个
   - 没有 "while I'm here" 改进
   - 不捆绑重构

3. **验证修复**
   - 测试现在通过了吗？
   - 是否没有破坏其他测试？
   - 问题是否真正解决？

4. **如果修复无效**
   - 停止
   - 统计：你已经尝试了多少个修复？
   - 如果 < 3：回到第 1 阶段，用新信息重新分析
   - **如果 >= 3：停止并质疑架构（见下方第 5 步）**
   - 不要在未进行架构讨论时尝试第 4 个修复

5. **如果 3 个以上修复失败：质疑架构**

   **表示架构问题的模式：**
   - 每个修复都在不同位置暴露新的共享状态/耦合/问题
   - 修复需要 "massive refactoring" 才能实现
   - 每个修复都在别处制造新症状

   **停止并质疑基本前提：**
   - 这个模式本身合理吗？
   - 我们是不是 "sticking with it through sheer inertia"？
   - 应该重构架构，而不是继续修症状吗？

   **尝试更多修复前，先和人工协作者讨论**

   这不是失败假设，而是错误架构。

## 红旗 - 停止并遵循流程

如果你发现自己在想：
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "Skip the test, I'll manually verify"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Pattern says X but I'll adapt it differently"
- "Here are the main problems: [lists fixes without investigation]"
- 在追踪数据流前提出解决方案
- **"One more fix attempt"（已经试过 2 个以上时）**
- **每个修复都在不同地方暴露新问题**

**这些都意味着：停止。回到第 1 阶段。**

**如果 3 个以上修复失败：**质疑架构（见第 4.5 阶段）

## 你的人工协作者指出你做错的信号

**注意这些重定向：**
- "Is that not happening?" - 你未经验证就假设了
- "Will it show us...?" - 你本该添加证据收集
- "Stop guessing" - 你在未理解时提出修复
- "Ultrathink this" - 质疑基本前提，而不仅是症状
- "We're stuck?"（沮丧） - 你的方法不起作用

**看到这些时：**停止。回到第 1 阶段。

## 常见合理化

| 借口 | 现实 |
|--------|---------|
| "Issue is simple, don't need process" | 简单问题也有根因。流程对简单 bug 很快。 |
| "Emergency, no time for process" | 系统化调试比猜测试错更快。 |
| "Just try this first, then investigate" | 第一个修复会奠定模式。从一开始就做对。 |
| "I'll write test after confirming fix works" | 未测试的修复站不住。测试先行能证明它。 |
| "Multiple fixes at once saves time" | 无法隔离哪个有效。会制造新 bug。 |
| "Reference too long, I'll adapt the pattern" | 局部理解必然导致 bug。完整阅读。 |
| "I see the problem, let me fix it" | 看到症状不等于理解根因。 |
| "One more fix attempt"（2 次以上失败后） | 3 次以上失败 = 架构问题。质疑模式，不要再修。 |

## 快速参考

| 阶段 | 关键活动 | 成功标准 |
|-------|---------------|------------------|
| **1. 根因** | 阅读错误、复现、检查变更、收集证据 | 理解 WHAT 和 WHY |
| **2. 模式** | 找到可工作示例并比较 | 识别差异 |
| **3. 假设** | 形成理论并最小化测试 | 假设被确认或形成新假设 |
| **4. 实现** | 创建测试、修复、验证 | Bug 解决，测试通过 |

## 当流程揭示"没有根因"时

如果系统化调查发现问题确实是环境、时序依赖或外部因素：

1. 你已经完成了流程
2. 记录你调查过什么
3. 实现合适处理（retry、timeout、error message）
4. 添加 monitoring/logging 以便未来调查

**但是：**95% 的"没有根因"情况其实是调查不完整。

## 支持技术

这些技术是系统化调试的一部分，并位于本目录：

- **`root-cause-tracing.md`** - 沿 call stack 反向追踪 bug，找到原始触发点
- **`defense-in-depth.md`** - 找到根因后，在多层添加验证
- **`condition-based-waiting.md`** - 用条件轮询替代任意 timeout

**相关 skills：**
- **superpowers:test-driven-development** - 用于创建失败测试用例（第 4 阶段，第 1 步）
- **superpowers:verification-before-completion** - 在声称成功前验证修复确实有效

## 真实世界影响

来自调试会话：
- 系统化方法：15-30 分钟修复
- 随机修复方法：2-3 小时乱试
- 首次修复成功率：95% vs 40%
- 引入新 bug：接近零 vs 很常见
