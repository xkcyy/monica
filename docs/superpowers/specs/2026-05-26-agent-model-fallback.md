# Agent 模型降级策略设计文档

## 概述

为 Agent 添加模型降级功能，当使用主模型执行任务失败时，自动按顺序尝试配置的降级模型，提高任务执行成功率。

## 目标

1. 支持为 Agent 配置降级模型列表
2. 当任务执行失败时自动按顺序尝试降级模型
3. 记录降级过程和使用的模型
4. 保持与现有架构兼容

## 背景与上下文

### 现有架构

1. **Agent 表**：存储 Agent 配置，包括 `model` 字段（当前使用的模型）
2. **AgentTaskQueue 表**：存储待执行任务，通过 `agent_id` 关联到 Agent
3. **Daemon 流程**：
   - Claim 任务时获取完整的 Task 对象，包含 Agent 配置
   - 使用 `agent.New(provider, config)` 创建 Backend
   - 调用 `backend.Execute(ctx, prompt, opts)` 执行任务
   - 等待结果并上报

4. **agent 包**：提供统一的 Backend 接口，支持多个 provider（codex, claude, copilot 等）

## 设计

### 1. 数据库设计

在 `agent` 表中添加 `fallback_models` JSONB 字段，用于存储降级模型列表。

```sql
ALTER TABLE agent ADD COLUMN fallback_models JSONB DEFAULT '[]'::jsonb;
```

字段类型：JSONB 数组，存储模型 ID 字符串
示例：`["gpt-5.5-mini", "gpt-5.4", "gpt-5.3-codex"]`

### 2. 类型定义

#### 后端类型（Go）

更新 `models.go` 中的 `Agent` 类型：
```go
type Agent struct {
    // ... 现有字段
    FallbackModels []byte `json:"fallback_models"` // JSONB 数组
}
```

更新 `daemon/types.go` 中的 `AgentData` 类型：
```go
type AgentData struct {
    // ... 现有字段
    FallbackModels []string `json:"fallback_models,omitempty"`
}
```

#### 前端类型（TypeScript）

更新相关类型定义以支持 `fallbackModels` 字段。

### 3. 核心降级逻辑

在 `server/pkg/agent` 包中添加一个包装器，用于处理模型降级：

```go
const maxFallbackAttempts = 5 // 最多尝试 5 个模型（主模型 + 4 个降级）

// fallbackBackend wraps a Backend with model fallback logic
type fallbackBackend struct {
    base          Backend
    primaryModel  string
    fallbackModels []string
    logger        *slog.Logger
}

// WithModelFallback wraps a Backend with model fallback capability
func WithModelFallback(
    backend Backend,
    primaryModel string,
    fallbackModels []string,
    logger *slog.Logger,
) Backend {
    // 限制降级模型数量
    limitedFallbackModels := fallbackModels
    if len(limitedFallbackModels) > maxFallbackAttempts-1 {
        limitedFallbackModels = limitedFallbackModels[:maxFallbackAttempts-1]
        logger.Warn("fallback models truncated",
            "requested", len(fallbackModels),
            "limited", len(limitedFallbackModels),
        )
    }

    return &fallbackBackend{
        base:           backend,
        primaryModel:   primaryModel,
        fallbackModels: limitedFallbackModels,
        logger:         logger,
    }
}

// Execute implements Backend
func (fb *fallbackBackend) Execute(ctx context.Context, prompt string, opts ExecOptions) (*Session, error) {
    // 构建模型尝试列表：主模型 + 降级模型（已限制数量）
    models := make([]string, 0, 1+len(fb.fallbackModels))
    models = append(models, fb.primaryModel)
    models = append(models, fb.fallbackModels...)

    // 从第一个模型开始尝试
    return fb.tryModels(ctx, prompt, opts, models)
}

// tryModels 按顺序尝试模型列表
func (fb *fallbackBackend) tryModels(
    ctx context.Context,
    prompt string,
    opts ExecOptions,
    models []string,
) (*Session, error) {
    if len(models) == 0 {
        return nil, fmt.Errorf("no models to try")
    }

    currentModel := models[0]
    remainingModels := models[1:]

    // 创建新的 ExecOptions，使用当前模型
    currentOpts := opts
    currentOpts.Model = currentModel
    if len(remainingModels) < len(fb.fallbackModels) {
        // 已经是降级尝试，禁用 resume
        currentOpts.ResumeSessionID = ""
        fb.logger.Info("trying fallback model",
            "model", currentModel,
            "remaining_fallbacks", len(remainingModels),
        )
    }

    // 执行当前模型
    session, err := fb.base.Execute(ctx, prompt, currentOpts)
    
    if err != nil {
        // 直接执行失败，尝试下一个模型
        fb.logger.Warn("model execution failed immediately",
            "model", currentModel,
            "error", err,
        )
        
        if len(remainingModels) > 0 {
            return fb.tryModels(ctx, prompt, opts, remainingModels)
        }
        return nil, fmt.Errorf("model %q failed: %w", currentModel, err)
    }

    // 包装 Session，监听结果以决定是否需要继续降级
    return fb.wrapSession(ctx, session, currentModel, remainingModels, prompt, opts), nil
}

// wrapSession wraps a Session to handle automatic fallback on failure
func (fb *fallbackBackend) wrapSession(
    ctx context.Context,
    session *Session,
    currentModel string,
    remainingModels []string,
    prompt string,
    opts ExecOptions,
) *Session {
    // 创建新的 channel
    msgCh := make(chan Message, 256)
    resCh := make(chan Result, 1)

    // 启动 goroutine 处理降级逻辑
    go func() {
        defer close(msgCh)
        defer close(resCh)

        // 转发当前 session 的消息
        for msg := range session.Messages {
            msgCh <- msg
        }

        // 等待结果
        result := <-session.Result

        // 判断是否需要降级
        if fb.needsFallback(result.Status) && len(remainingModels) > 0 {
            fb.logger.Warn("model failed, trying fallback",
                "model", currentModel,
                "status", result.Status,
                "error", result.Error,
                "remaining_fallbacks", len(remainingModels),
            )

            // 合并 usage 统计
            accumulatedUsage := make(map[string]TokenUsage)
            for m, u := range result.Usage {
                accumulatedUsage[m] = u
            }

            // 尝试降级模型
            for _, nextModel := range remainingModels {
                fb.logger.Info("trying fallback model", "model", nextModel)

                // 准备新的 options（禁用 resume）
                nextOpts := opts
                nextOpts.Model = nextModel
                nextOpts.ResumeSessionID = ""

                // 执行下一个模型
                nextSession, err := fb.base.Execute(ctx, prompt, nextOpts)
                if err != nil {
                    fb.logger.Warn("fallback model failed to start", "model", nextModel, "error", err)
                    continue
                }

                // 转发消息
                for msg := range nextSession.Messages {
                    msgCh <- msg
                }

                // 获取结果
                nextResult := <-nextSession.Result

                // 合并 usage
                for m, u := range nextResult.Usage {
                    accumulatedUsage[m] = mergeTokenUsage(accumulatedUsage[m], u)
                }

                // 如果成功，返回结果
                if !fb.needsFallback(nextResult.Status) {
                    nextResult.Usage = accumulatedUsage
                    resCh <- nextResult
                    return
                }

                fb.logger.Warn("fallback model also failed",
                    "model", nextModel,
                    "status", nextResult.Status,
                    "error", nextResult.Error,
                )
            }

            // 所有降级模型都失败，返回原始结果，但合并了 usage
            result.Usage = accumulatedUsage
        }

        resCh <- result
    }()

    return &Session{
        Messages: msgCh,
        Result:   resCh,
    }
}

// needsFallback 判断是否需要降级
func (fb *fallbackBackend) needsFallback(status string) bool {
    return status == "failed" || status == "timeout" || status == "aborted"
}

// mergeTokenUsage 合并两个 TokenUsage
func mergeTokenUsage(a, b TokenUsage) TokenUsage {
    return TokenUsage{
        InputTokens:      a.InputTokens + b.InputTokens,
        OutputTokens:     a.OutputTokens + b.OutputTokens,
        CacheReadTokens:  a.CacheReadTokens + b.CacheReadTokens,
        CacheWriteTokens: a.CacheWriteTokens + b.CacheWriteTokens,
    }
}
```

### 4. 触发降级的条件

当以下情况发生时触发降级：
1. `Execute()` 直接返回错误
2. `Result.Status` 为 `"failed"`、`"timeout"` 或 `"aborted"`

### 5. Daemon 集成

在 `server/internal/daemon/daemon.go` 的 `runTask` 函数中：
1. 创建 Backend 后，使用 `WithModelFallback` 包装
2. 传入 `task.Agent.Model` 作为主模型
3. 传入 `task.Agent.FallbackModels` 作为降级模型列表

### 6. API 和 Handler 变更

更新 Agent 的 CRUD API，支持读取和设置 `fallback_models` 字段：
- `CreateAgent`：支持设置 `fallback_models`
- `UpdateAgent`：支持更新 `fallback_models`
- `GetAgent`/`ListAgents`：返回 `fallback_models`

### 7. sqlc 查询更新

在 `server/pkg/db/queries/agent.sql` 中更新查询：
```sql
-- name: CreateAgent :one
INSERT INTO agent (
    -- ... 现有字段
    fallback_models
) VALUES (
    -- ... 现有参数
    sqlc.arg(fallback_models)::jsonb
) RETURNING *;

-- name: UpdateAgent :one
UPDATE agent SET
    -- ... 现有字段
    fallback_models = COALESCE(sqlc.narg(fallback_models), fallback_models),
    updated_at = now()
WHERE id = $1
RETURNING *;
```

## 使用示例

### Agent 配置示例

```json
{
  "id": "agent-uuid",
  "name": "My Agent",
  "model": "gpt-5.5",
  "fallback_models": ["gpt-5.5-mini", "gpt-5.4", "gpt-5.3-codex"]
}
```

### 执行流程

1. 任务开始，使用主模型 `gpt-5.5`
2. 如果失败，尝试 `gpt-5.5-mini`
3. 如果再失败，尝试 `gpt-5.4`
4. 如果再失败，尝试 `gpt-5.3-codex`
5. 所有模型都失败，返回错误

## 注意事项

1. **Session Resume**：降级尝试时不使用 `ResumeSessionID`，避免跨模型的会话状态污染
2. **Usage 统计**：需要合并所有尝试的模型的 Usage 数据
3. **日志记录**：记录降级过程，方便调试
4. **UI 配置**：后续需要添加 UI 来配置降级模型列表

## 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 降级增加任务执行时间 | 记录每次降级的耗时，监控整体执行时间 |
| 配置错误导致无限降级 | 限制最大降级次数，最多 5 个模型（主模型 + 4 个降级） |
| 不同模型的 prompt 兼容性不同 | 保持降级模型是同一 provider 的不同版本，减少兼容性问题 |
| Session Resume 导致跨模型状态污染 | 降级尝试时禁用 `ResumeSessionID` |
| Usage 统计不准确 | 合并所有尝试模型的 Usage 数据 |

## 实施计划

1. 数据库迁移：添加 `fallback_models` 字段
2. 更新类型定义：Go 和 TypeScript
3. 实现降级包装器：`WithModelFallback`
4. 更新 sqlc 查询：支持新字段
5. 更新 Daemon：集成降级逻辑
6. 更新 API：支持配置降级模型
7. 测试：编写单元测试和集成测试

## UI 配置设计

### 概述

在 Agent 详情页的 Inspector 组件中添加降级模型配置功能，参考现有的 ModelPicker 设计，提供添加、删除和排序降级模型的能力。

### 界面布局

在 Inspector 的 "属性"（Properties）区域中，在 "模型"（Model）行下方添加 "降级模型"（Fallback Models）行：

```
属性
─────────────────────────────────────────────
运行时          Cloud-Runtime-1 · 在线
模型            gpt-5.5
降级模型        gpt-5.5-mini  ×  gpt-5.4  ×  +添加
─────────────────────────────────────────────
可见性          工作区
并发            最多 3 个并行 task
```

### 交互设计

#### 1. 显示状态
- **无降级模型**：显示 "暂无降级模型" 和一个 "+ 添加" 按钮
- **有降级模型**：显示 chips 列表（类似 SkillAttach），每个 chip 右侧有 "×" 删除按钮，最右侧有 "+ 添加" 按钮

#### 2. 添加降级模型
点击 "+ 添加" 按钮或直接点击整行，打开 ModelPicker 弹窗（复用现有的 ModelPicker 组件）：
- 搜索和过滤模型
- 不显示已在降级列表中的模型
- 不显示当前选中的主模型
- 支持输入自定义模型 ID

#### 3. 删除降级模型
点击降级模型 chip 右侧的 "×" 按钮，移除该模型。

#### 4. 排序降级模型
- 拖拽调整顺序（可选功能）
- 或使用上下箭头按钮移动
- 顺序决定降级优先级：第一个失败 → 尝试第二个 → ...

### 组件设计

#### 新增组件

1. **`FallbackModelsEditor` 组件**
   - 位置：`packages/views/agents/components/inspector/fallback-models-editor.tsx`
   - 功能：管理降级模型列表的添加/删除/显示
   - 使用 ModelPicker 弹窗来选择模型

2. **更新 `AgentDetailInspector` 组件**
   - 在 Properties 区域添加新行
   - 导入并使用 FallbackModelsEditor

### 数据流

```
用户操作（添加/删除降级模型）
    ↓
FallbackModelsEditor 组件状态更新
    ↓
调用 onUpdate({ fallback_models: [...] })
    ↓
AgentDetailInspector 通知父组件
    ↓
API 请求更新 Agent 配置
    ↓
后端更新数据库
```

### 状态管理

- 降级模型列表存储在 Agent 的 `fallback_models` 字段
- 前端使用 React useState 管理本地编辑状态
- 使用 optimistic update 优化用户体验

### 限制

- 最多支持 4 个降级模型（与后端 maxFallbackAttempts-1 保持一致）
- 降级模型不能与主模型相同
- 降级模型不能重复

### 错误处理

- API 请求失败时显示 toast 错误提示
- 保持本地状态不变，允许用户重试

### 国际化

需要添加以下国际化 key（在 `packages/views/locales/zh-Hans/agents.json`）：

```json
{
  "inspector": {
    "prop_fallback_models": "降级模型",
    "prop_fallback_models_empty": "暂无降级模型",
    "prop_fallback_models_tooltip": "降级模型 · 主模型失败时按顺序尝试"
  },
  "fallback_models": {
    "add": "添加",
    "remove": "移除",
    "max_reached": "最多支持 {{count}} 个降级模型",
    "cannot_same_as_primary": "降级模型不能与主模型相同",
    "already_added": "该模型已在降级列表中",
    "add_dialog_title": "添加降级模型",
    "add_dialog_description": "选择一个降级模型。当主模型执行失败时，会按顺序尝试这些模型。",
    "add_dialog_search_placeholder": "搜索或输入模型 ID",
    "add_dialog_empty": "暂无可用模型",
    "add_dialog_cancel": "取消",
    "add_dialog_confirm": "添加"
  }
}
```

### 实现优先级

建议分两个阶段实现：

**阶段 1：基础功能（必须）**
- 添加 FallbackModelsEditor 组件
- 支持添加/删除降级模型
- 显示降级模型列表
- 与后端 API 集成

**阶段 2：增强功能（可选）**
- 拖拽排序
- 显示每个降级模型的详细信息（tooltip）
- 添加降级触发条件的配置 UI（未来扩展）

## 未来扩展

- 支持按错误类型配置不同的降级策略
- 支持跨 provider 降级（从 codex 降级到 claude）
- 支持动态优先级调整（根据失败率自动调整）
