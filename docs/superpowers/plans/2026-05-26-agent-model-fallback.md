# Agent 模型降级策略实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Agent 添加模型降级功能，当主模型执行失败时自动尝试配置的降级模型。

**Architecture:** 在 `agent` 包中添加 `WithModelFallback` 包装器，包装现有的 Backend 接口。当任务失败时，自动按顺序尝试配置的降级模型。

**Tech Stack:** Go (backend), TypeScript (frontend), PostgreSQL (database), sqlc (database queries)

---

## 文件结构

```
server/
├── pkg/
│   ├── db/
│   │   ├── migrations/
│   │   │   └── 009_add_fallback_models.up.sql
│   │   ├── queries/
│   │   │   └── agent.sql  # 更新：添加 fallback_models 字段
│   │   └── generated/
│   │       ├── models.go  # 自动生成：包含 fallback_models 字段
│   │       └── agent.sql.go  # 自动生成
│   └── agent/
│       └── fallback.go  # 新增：降级包装器
├── internal/
│   ├── daemon/
│   │   ├── types.go  # 更新：AgentData 添加 FallbackModels
│   │   └── daemon.go  # 更新：runTask 集成降级逻辑
│   └── handler/
│       └── agent.go  # 更新：API 支持 fallback_models
└── pkg/
    └── core/
        └── types/
            └── agent.ts  # 更新：Agent 类型添加 fallbackModels

packages/
└── views/
    ├── agents/
    │   └── components/
    │       └── inspector/
    │           └── fallback-models-editor.tsx  # 新增：UI 组件
    └── locales/
        ├── zh-Hans/
        │   └── agents.json  # 更新：国际化
        └── en/
            └── agents.json  # 更新：国际化
```

---

## Task 1: 数据库迁移 - 添加 fallback_models 字段

**Files:**
- Create: `server/pkg/db/migrations/009_add_fallback_models.up.sql`
- Create: `server/pkg/db/migrations/009_add_fallback_models.down.sql`

- [ ] **Step 1: 创建迁移文件**

```sql
-- 009_add_fallback_models.up.sql
ALTER TABLE agent ADD COLUMN fallback_models JSONB DEFAULT '[]'::jsonb;
CREATE INDEX idx_agent_fallback_models ON agent USING GIN (fallback_models);
```

```sql
-- 009_add_fallback_models.down.sql
DROP INDEX IF EXISTS idx_agent_fallback_models;
ALTER TABLE agent DROP COLUMN IF EXISTS fallback_models;
```

- [ ] **Step 2: 运行迁移验证**

Run: `cd server && make migrate`
Expected: 迁移成功执行

- [ ] **Step 3: 提交迁移文件**

```bash
git add server/pkg/db/migrations/
git commit -m "db: add fallback_models column to agent table"
```

---

## Task 2: 更新 sqlc 生成的代码

**Files:**
- Modify: `server/pkg/db/queries/agent.sql`

- [ ] **Step 1: 更新 CreateAgent 查询**

```sql
-- name: CreateAgent :one
INSERT INTO agent (
    workspace_id, name, description, avatar_url, runtime_mode,
    runtime_config, runtime_id, visibility, max_concurrent_tasks, owner_id,
    instructions, custom_env, custom_args, mcp_config, model, fallback_models
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
RETURNING *;
```

- [ ] **Step 2: 更新 UpdateAgent 查询**

在现有 UpdateAgent 查询末尾添加：
```sql
    fallback_models = COALESCE(sqlc.narg('fallback_models'), fallback_models),
```

完整查询：
```sql
-- name: UpdateAgent :one
UPDATE agent SET
    name = COALESCE(sqlc.narg('name'), name),
    description = COALESCE(sqlc.narg('description'), description),
    avatar_url = COALESCE(sqlc.narg('avatar_url'), avatar_url),
    runtime_config = COALESCE(sqlc.narg('runtime_config'), runtime_config),
    runtime_mode = COALESCE(sqlc.narg('runtime_mode'), runtime_mode),
    runtime_id = COALESCE(sqlc.narg('runtime_id'), runtime_id),
    visibility = COALESCE(sqlc.narg('visibility'), visibility),
    status = COALESCE(sqlc.narg('status'), status),
    max_concurrent_tasks = COALESCE(sqlc.narg('max_concurrent_tasks'), max_concurrent_tasks),
    instructions = COALESCE(sqlc.narg('instructions'), instructions),
    custom_env = COALESCE(sqlc.narg('custom_env'), custom_env),
    custom_args = COALESCE(sqlc.narg('custom_args'), custom_args),
    mcp_config = COALESCE(sqlc.narg('mcp_config'), mcp_config),
    model = COALESCE(sqlc.narg('model'), model),
    fallback_models = COALESCE(sqlc.narg('fallback_models'), fallback_models),
    updated_at = now()
WHERE id = $1
RETURNING *;
```

- [ ] **Step 3: 重新生成代码**

Run: `cd server && make generate`
Expected: models.go 和 agent.sql.go 已更新，包含 fallback_models 字段

- [ ] **Step 4: 验证生成的代码**

检查 `pkg/db/generated/models.go` 中的 Agent 结构体包含 `FallbackModels []byte` 字段

- [ ] **Step 5: 提交**

```bash
git add server/pkg/db/queries/agent.sql
git add server/pkg/db/generated/
git commit -m "db: update sqlc queries for fallback_models field"
```

---

## Task 3: 实现降级包装器

**Files:**
- Create: `server/pkg/agent/fallback.go`

- [ ] **Step 1: 创建降级包装器文件**

```go
package agent

import (
	"context"
	"fmt"
	"log/slog"
)

const maxFallbackAttempts = 5 // 最多尝试 5 个模型（主模型 + 4 个降级）

type fallbackBackend struct {
	base           Backend
	primaryModel   string
	fallbackModels []string
	logger         *slog.Logger
}

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
		if logger != nil {
			logger.Warn("fallback models truncated",
				"requested", len(fallbackModels),
				"limited", len(limitedFallbackModels),
			)
		}
	}

	return &fallbackBackend{
		base:           backend,
		primaryModel:   primaryModel,
		fallbackModels: limitedFallbackModels,
		logger:         logger,
	}
}

func (fb *fallbackBackend) Execute(ctx context.Context, prompt string, opts ExecOptions) (*Session, error) {
	// 构建模型尝试列表：主模型 + 降级模型
	models := make([]string, 0, 1+len(fb.fallbackModels))
	models = append(models, fb.primaryModel)
	models = append(models, fb.fallbackModels...)

	return fb.tryModels(ctx, prompt, opts, models)
}

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

	// 如果是降级尝试，禁用 resume
	if len(remainingModels) < len(fb.fallbackModels) {
		currentOpts.ResumeSessionID = ""
		if fb.logger != nil {
			fb.logger.Info("trying fallback model",
				"model", currentModel,
				"remaining_fallbacks", len(remainingModels),
			)
		}
	}

	// 执行当前模型
	session, err := fb.base.Execute(ctx, prompt, currentOpts)
	if err != nil {
		if fb.logger != nil {
			fb.logger.Warn("model execution failed immediately",
				"model", currentModel,
				"error", err,
			)
		}

		if len(remainingModels) > 0 {
			return fb.tryModels(ctx, prompt, opts, remainingModels)
		}
		return nil, fmt.Errorf("model %q failed: %w", currentModel, err)
	}

	// 包装 Session，监听结果
	return fb.wrapSession(ctx, session, currentModel, remainingModels, prompt, opts), nil
}

func (fb *fallbackBackend) wrapSession(
	ctx context.Context,
	session *Session,
	currentModel string,
	remainingModels []string,
	prompt string,
	opts ExecOptions,
) *Session {
	msgCh := make(chan Message, 256)
	resCh := make(chan Result, 1)

	go func() {
		defer close(msgCh)
		defer close(resCh)

		// 转发消息
		for msg := range session.Messages {
			msgCh <- msg
		}

		// 等待结果
		result := <-session.Result

		// 判断是否需要降级
		if fb.needsFallback(result.Status) && len(remainingModels) > 0 {
			if fb.logger != nil {
				fb.logger.Warn("model failed, trying fallback",
					"model", currentModel,
					"status", result.Status,
					"error", result.Error,
					"remaining_fallbacks", len(remainingModels),
				)
			}

			// 合并 usage
			accumulatedUsage := make(map[string]TokenUsage)
			for m, u := range result.Usage {
				accumulatedUsage[m] = u
			}

			// 尝试降级模型
			for _, nextModel := range remainingModels {
				if fb.logger != nil {
					fb.logger.Info("trying fallback model", "model", nextModel)
				}

				// 准备新的 options
				nextOpts := opts
				nextOpts.Model = nextModel
				nextOpts.ResumeSessionID = ""

				// 执行下一个模型
				nextSession, err := fb.base.Execute(ctx, prompt, nextOpts)
				if err != nil {
					if fb.logger != nil {
						fb.logger.Warn("fallback model failed to start", "model", nextModel, "error", err)
					}
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

				if fb.logger != nil {
					fb.logger.Warn("fallback model also failed",
						"model", nextModel,
						"status", nextResult.Status,
						"error", nextResult.Error,
					)
				}
			}

			// 所有降级模型都失败，返回原始结果
			result.Usage = accumulatedUsage
		}

		resCh <- result
	}()

	return &Session{
		Messages: msgCh,
		Result:   resCh,
	}
}

func (fb *fallbackBackend) needsFallback(status string) bool {
	return status == "failed" || status == "timeout" || status == "aborted"
}

func mergeTokenUsage(a, b TokenUsage) TokenUsage {
	return TokenUsage{
		InputTokens:      a.InputTokens + b.InputTokens,
		OutputTokens:     a.OutputTokens + b.OutputTokens,
		CacheReadTokens:  a.CacheReadTokens + b.CacheReadTokens,
		CacheWriteTokens: a.CacheWriteTokens + b.CacheWriteTokens,
	}
}
```

- [ ] **Step 2: 验证代码编译**

Run: `cd server && go build ./pkg/agent/`
Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add server/pkg/agent/fallback.go
git commit -m "feat(agent): add model fallback wrapper"
```

---

## Task 4: 更新 Daemon 类型

**Files:**
- Modify: `server/internal/daemon/types.go`

- [ ] **Step 1: 更新 AgentData 结构体**

在 `AgentData` 结构体中添加 `FallbackModels` 字段：

```go
type AgentData struct {
	ID             string            `json:"id"`
	Name           string            `json:"name"`
	Instructions   string            `json:"instructions"`
	Skills         []SkillData       `json:"skills"`
	CustomEnv      map[string]string `json:"custom_env,omitempty"`
	CustomArgs     []string          `json:"custom_args,omitempty"`
	McpConfig      json.RawMessage   `json:"mcp_config,omitempty"`
	Model          string            `json:"model,omitempty"`
	FallbackModels []string          `json:"fallback_models,omitempty"` // 新增
}
```

- [ ] **Step 2: 验证代码编译**

Run: `cd server && go build ./internal/daemon/`
Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add server/internal/daemon/types.go
git commit -m "feat(daemon): add FallbackModels to AgentData"
```

---

## Task 5: 更新 Daemon 集成降级逻辑

**Files:**
- Modify: `server/internal/daemon/daemon.go` (在 runTask 函数中)

- [ ] **Step 1: 找到 runTask 函数并添加降级包装**

找到创建 Backend 的位置，通常在 `runTask` 函数中：

```go
// 在创建 Backend 后，使用 WithModelFallback 包装
backend := agent.New(provider, config)

// 如果配置了降级模型，包装 backend
if len(task.Agent.FallbackModels) > 0 {
    backend = agent.WithModelFallback(
        backend,
        task.Agent.Model,
        task.Agent.FallbackModels,
        logger,
    )
}
```

- [ ] **Step 2: 验证代码编译**

Run: `cd server && go build ./internal/daemon/`
Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add server/internal/daemon/daemon.go
git commit -m "feat(daemon): integrate model fallback in task execution"
```

---

## Task 6: 更新 API Handler 支持 fallback_models

**Files:**
- Modify: `server/internal/handler/agent.go`

- [ ] **Step 1: 找到 CreateAgent 和 UpdateAgent 的处理逻辑**

在创建和更新 Agent 时，确保支持 `fallback_models` 字段的读写

- [ ] **Step 2: 验证 API 集成**

Run: `cd server && go build ./internal/handler/`
Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add server/internal/handler/agent.go
git commit -m "feat(handler): support fallback_models in agent CRUD"
```

---

## Task 7: 更新前端类型定义

**Files:**
- Modify: `packages/core/types/agent.ts`

- [ ] **Step 1: 在 Agent 接口中添加 fallbackModels**

```typescript
export interface Agent {
  // ... 现有字段
  fallback_models?: string[];  // 新增
}
```

- [ ] **Step 2: 在 UpdateAgentRequest 中添加 fallback_models**

```typescript
export interface UpdateAgentRequest {
  // ... 现有字段
  fallback_models?: string[];  // 新增
}
```

- [ ] **Step 3: 提交**

```bash
git add packages/core/types/agent.ts
git commit -m "feat(types): add fallback_models to Agent type"
```

---

## Task 8: 创建 FallbackModelsEditor 组件

**Files:**
- Create: `packages/views/agents/components/inspector/fallback-models-editor.tsx`

- [ ] **Step 1: 创建组件文件**

```tsx
"use client";

import { useState } from "react";
import { Plus, X } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { runtimeModelsOptions } from "@multica/core/runtimes";
import { Button } from "@multica/ui/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@multica/ui/components/ui/popover";
import { Input } from "@multica/ui/components/ui/input";
import { PickerItem } from "../../../issues/components/pickers";
import { useT } from "../../../i18n";

interface FallbackModelsEditorProps {
  runtimeId: string | null;
  runtimeOnline: boolean;
  primaryModel: string;
  value: string[];
  canEdit?: boolean;
  onChange: (next: string[]) => Promise<void> | void;
}

export function FallbackModelsEditor({
  runtimeId,
  runtimeOnline,
  primaryModel,
  value,
  canEdit = true,
  onChange,
}: FallbackModelsEditorProps) {
  const { t } = useT("agents");
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [selectedModel, setSelectedModel] = useState<string | null>(null);

  const modelsQuery = useQuery(
    runtimeModelsOptions(runtimeOnline ? runtimeId : null),
  );

  const models = modelsQuery.data?.models ?? [];

  // 过滤掉主模型和已选择的模型
  const availableModels = models.filter(
    (m) => m.id !== primaryModel && !value.includes(m.id)
  );

  const filtered = search.trim()
    ? availableModels.filter(
        (m) =>
          m.id.toLowerCase().includes(search.toLowerCase()) ||
          m.label.toLowerCase().includes(search.toLowerCase())
      )
    : availableModels;

  const removeModel = async (modelId: string) => {
    const next = value.filter((m) => m !== modelId);
    await onChange(next);
  };

  const addModel = async () => {
    if (!selectedModel) return;
    const next = [...value, selectedModel];
    await onChange(next);
    setSelectedModel(null);
    setSearch("");
    setOpen(false);
  };

  const handleSelectModel = (modelId: string) => {
    setSelectedModel(modelId);
    setSearch(modelId);
  };

  if (!canEdit) {
    if (value.length === 0) {
      return (
        <span className="text-muted-foreground text-xs italic">
          {t(($) => $.inspector.prop_fallback_models_empty)}
        </span>
      );
    }
    return (
      <div className="flex flex-wrap gap-1">
        {value.map((model) => (
          <span
            key={model}
            className="rounded bg-muted px-1.5 py-0.5 font-mono text-[10px]"
          >
            {model}
          </span>
        ))}
      </div>
    );
  }

  return (
    <div className="flex flex-wrap items-center gap-1">
      {value.map((model) => (
        <span
          key={model}
          className="inline-flex items-center gap-0.5 rounded bg-muted px-1.5 py-0.5 font-mono text-[10px]"
        >
          {model}
          <button
            type="button"
            onClick={() => void removeModel(model)}
            className="ml-0.5 text-muted-foreground hover:text-foreground"
          >
            <X className="h-3 w-3" />
          </button>
        </span>
      ))}

      {value.length < 4 && (
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger asChild>
            <button
              type="button"
              className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] text-primary hover:bg-accent"
            >
              <Plus className="h-3 w-3" />
              {t(($) => $.fallback_models.add)}
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-72 p-0" align="start">
            <div className="p-2">
              <Input
                autoFocus
                placeholder={t(($) => $.fallback_models.add_dialog_search_placeholder)}
                value={search}
                onChange={(e) => {
                  setSearch(e.target.value);
                  setSelectedModel(e.target.value);
                }}
                className="h-8 text-xs"
              />
            </div>
            <div className="max-h-64 overflow-y-auto">
              {filtered.length === 0 ? (
                <p className="p-3 text-center text-xs text-muted-foreground">
                  {t(($) => $.fallback_models.add_dialog_empty)}
                </p>
              ) : (
                filtered.map((m) => (
                  <PickerItem
                    key={m.id}
                    selected={m.id === selectedModel}
                    onClick={() => void handleSelectModel(m.id)}
                  >
                    <div className="min-w-0 flex-1">
                      <div className="truncate font-medium">{m.label}</div>
                      {m.label !== m.id && (
                        <div className="truncate font-mono text-[10px] text-muted-foreground">
                          {m.id}
                        </div>
                      )}
                    </div>
                  </PickerItem>
                ))
              )}
            </div>
            {selectedModel && (
              <div className="border-t p-2">
                <Button
                  size="sm"
                  className="w-full"
                  onClick={() => void addModel()}
                >
                  {t(($) => $.fallback_models.add_dialog_confirm)}
                </Button>
              </div>
            )}
          </PopoverContent>
        </Popover>
      )}

      {value.length >= 4 && (
        <span className="text-[10px] text-muted-foreground">
          {t(($) => $.fallback_models.max_reached, { count: 4 })}
        </span>
      )}
    </div>
  );
}
```

- [ ] **Step 2: 验证 TypeScript 编译**

Run: `pnpm typecheck`
Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add packages/views/agents/components/inspector/fallback-models-editor.tsx
git commit -m "feat(ui): add FallbackModelsEditor component"
```

---

## Task 9: 更新 AgentDetailInspector 组件

**Files:**
- Modify: `packages/views/agents/components/agent-detail-inspector.tsx`

- [ ] **Step 1: 导入并使用 FallbackModelsEditor**

在文件顶部添加导入：
```typescript
import { FallbackModelsEditor } from "./inspector/fallback-models-editor";
```

在 Properties 区域添加新行：
```tsx
<PropRow label={t(($) => $.inspector.prop_model)} interactive={false}>
  <ModelPicker
    runtimeId={agent.runtime_id}
    runtimeOnline={!!isOnline}
    value={agent.model ?? ""}
    canEdit={canEdit}
    onChange={(m) => update({ model: m })}
  />
</PropRow>
<PropRow label={t(($) => $.inspector.prop_fallback_models)} interactive={false}>
  <FallbackModelsEditor
    runtimeId={agent.runtime_id}
    runtimeOnline={!!isOnline}
    primaryModel={agent.model ?? ""}
    value={agent.fallback_models ?? []}
    canEdit={canEdit}
    onChange={(models) => update({ fallback_models: models })}
  />
</PropRow>
```

- [ ] **Step 2: 验证 TypeScript 编译**

Run: `pnpm typecheck`
Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add packages/views/agents/components/agent-detail-inspector.tsx
git commit -m "feat(ui): add fallback models row to agent inspector"
```

---

## Task 10: 添加国际化文本

**Files:**
- Modify: `packages/views/locales/zh-Hans/agents.json`
- Modify: `packages/views/locales/en/agents.json`

- [ ] **Step 1: 添加中文翻译**

在 `zh-Hans/agents.json` 中添加：

```json
{
  "inspector": {
    "prop_fallback_models": "降级模型",
    "prop_fallback_models_empty": "暂无降级模型"
  },
  "fallback_models": {
    "add": "添加",
    "max_reached": "最多支持 {{count}} 个降级模型",
    "add_dialog_title": "添加降级模型",
    "add_dialog_description": "选择一个降级模型。当主模型执行失败时，会按顺序尝试这些模型。",
    "add_dialog_search_placeholder": "搜索或输入模型 ID",
    "add_dialog_empty": "暂无可用模型",
    "add_dialog_cancel": "取消",
    "add_dialog_confirm": "添加"
  }
}
```

- [ ] **Step 2: 添加英文翻译**

在 `en/agents.json` 中添加：

```json
{
  "inspector": {
    "prop_fallback_models": "Fallback Models",
    "prop_fallback_models_empty": "No fallback models"
  },
  "fallback_models": {
    "add": "Add",
    "max_reached": "Maximum {{count}} fallback models supported",
    "add_dialog_title": "Add Fallback Model",
    "add_dialog_description": "Select a fallback model. When the primary model fails, these models will be tried in order.",
    "add_dialog_search_placeholder": "Search or enter model ID",
    "add_dialog_empty": "No available models",
    "add_dialog_cancel": "Cancel",
    "add_dialog_confirm": "Add"
  }
}
```

- [ ] **Step 3: 提交**

```bash
git add packages/views/locales/
git commit -m "i18n: add fallback models translations"
```

---

## Task 11: 端到端测试

- [ ] **Step 1: 在本地环境测试**

1. 启动开发服务器
2. 创建或编辑一个 Agent
3. 添加降级模型
4. 触发任务执行，观察降级行为

- [ ] **Step 2: 验证降级日志**

检查 daemon 日志中是否正确记录了降级尝试：
- "trying fallback model"
- "model failed, trying fallback"

- [ ] **Step 3: 提交测试代码（可选）**

如果存在相关测试文件，添加单元测试：
```bash
git add server/pkg/agent/fallback_test.go
git commit -m "test(agent): add fallback wrapper tests"
```

---

## Task 12: 部署到生产环境

- [ ] **Step 1: 创建生产迁移**

确保迁移文件已提交并在 CI/CD 中执行

- [ ] **Step 2: 部署后端**

部署包含降级逻辑的 server 代码

- [ ] **Step 3: 部署前端**

部署包含 FallbackModelsEditor 的前端代码

- [ ] **Step 4: 监控**

观察生产环境中的日志和指标：
- 检查降级触发次数
- 监控任务执行时间（降级会增加时间）

---

## 总结

完成所有任务后，系统将支持：
1. ✅ 在 Agent 配置中添加降级模型列表
2. ✅ 当主模型失败时自动尝试降级模型
3. ✅ 通过 UI 配置降级模型
4. ✅ 记录降级过程和合并 Usage 统计

**总任务数**: 12 个
**预计代码变更**:
- 新增文件: 4 个
- 修改文件: 8 个
- 数据库迁移: 1 个
