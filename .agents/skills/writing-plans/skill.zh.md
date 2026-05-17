---
name: writing-plans
description: 当你已有 multi-step 任务的 spec 或 requirements，并且尚未触碰代码前使用
---

# 编写计划

## 概览

编写全面的实现计划，假设执行工程师对我们的代码库完全没有上下文，而且品味可疑。记录他们需要知道的一切：每个任务要改哪些文件、代码、测试、可能需要查阅的文档、如何测试。把完整计划拆成小任务。DRY。YAGNI。TDD。频繁 commit。

假设他们是熟练开发者，但几乎不了解我们的工具集或问题域。也假设他们并不擅长测试设计。

**开始时声明：**"我正在使用 writing-plans skill 来创建实现计划。"

**上下文：**如果在隔离 worktree 中工作，该 worktree 应该在执行时通过 `superpowers:using-git-worktrees` skill 创建。

**计划保存到：**`docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- （用户对计划位置的偏好会覆盖这个默认值）

## 范围检查

如果 spec 覆盖多个独立子系统，它应该已经在 brainstorming 阶段被拆成子项目 spec。如果没有，建议拆成独立计划，每个子系统一份。每份计划都应该独立产出可运行、可测试的软件。

## 文件结构

定义任务前，先梳理会创建或修改哪些文件，以及每个文件负责什么。这一步会锁定拆分决策。

- 设计边界清晰、接口明确的单元。每个文件应该只有一个清晰职责。
- 你最擅长推理能一次放进上下文的代码；文件聚焦时，你的编辑也更可靠。优先使用小而聚焦的文件，而不是承担太多职责的大文件。
- 一起变化的文件应该放在一起。按职责拆分，而不是按技术层拆分。
- 在已有代码库中，遵循现有模式。如果代码库使用大文件，不要单方面重构；但如果你要修改的文件已经变得笨重，把拆分纳入计划是合理的。

这个结构会影响任务拆分。每个任务都应该产出自包含、独立也说得通的变更。

## 小块任务粒度

**每一步是一个动作（2-5 分钟）：**
- "Write the failing test" - 一个步骤
- "Run it to make sure it fails" - 一个步骤
- "Implement the minimal code to make the test pass" - 一个步骤
- "Run the tests and make sure they pass" - 一个步骤
- "Commit" - 一个步骤

## 计划文档头部

**每份计划都必须以这个 header 开头：**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## 任务结构

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## 不允许占位符

每一步都必须包含工程师实际需要的内容。下面都是**计划失败**，绝不要写：
- "TBD"、"TODO"、"implement later"、"fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above"（没有实际测试代码）
- "Similar to Task N"（重复代码，工程师可能乱序阅读任务）
- 只描述做什么而不展示怎么做的步骤（代码步骤必须有代码块）
- 引用任何任务中都未定义的类型、函数或方法

## 记住
- 始终给精确文件路径
- 每一步都有完整代码；如果某步修改代码，就展示代码
- 精确命令和预期输出
- DRY、YAGNI、TDD、频繁 commit

## 自我 Review

写完整计划后，用新鲜视角重新看 spec，并用它检查计划。这是你自己运行的 checklist，不是派发 subagent。

**1. Spec 覆盖率：**略读 spec 的每一节/每项要求。你能指出哪个任务实现它吗？列出任何缺口。

**2. 占位符扫描：**在计划里搜索 "No Placeholders" 节中的红旗模式。修复它们。

**3. 类型一致性：**后续任务中使用的类型、方法签名和属性名是否与前面定义的一致？Task 3 中叫 `clearLayers()`，Task 7 中叫 `clearFullLayers()`，这就是 bug。

如果发现问题，就直接修复。无需重新 review，修好继续。如果发现某个 spec 要求没有对应任务，就添加任务。

## 执行交接

保存计划后，提供执行选择：

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**如果选择 Subagent-Driven：**
- **必需子 skill：**使用 superpowers:subagent-driven-development
- 每个任务 fresh subagent + 两阶段 review

**如果选择 Inline Execution：**
- **必需子 skill：**使用 superpowers:executing-plans
- 带检查点的批量执行
