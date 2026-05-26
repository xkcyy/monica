# 代码规范

## 命名规则

### 文件命名

| 类型 | 规则 | 示例 | 证据 |
|------|------|------|------|
| Go源文件 | 小写下划线分隔 | `issue_handler.go`, `task_service.go` | `server/internal/handler/` |
| TypeScript组件 | PascalCase + .tsx | `IssueDetail.tsx`, `AgentCard.tsx` | `packages/views/` |
| TypeScript工具 | camelCase + .ts | `apiClient.ts`, `parseWithFallback.ts` | `packages/core/` |
| React hooks | camelCase，use前缀 | `useIssues.ts`, `useAgents.ts` | `packages/core/` |
| Zustand stores | camelCase | `workspaceStore.ts`, `tabStore.ts` | `packages/core/stores/` |
| SQL查询文件 | 小写下划线分隔 | `issue.sql`, `agent.sql` | `server/pkg/db/queries/` |
| 迁移文件 | `NNN_name.up.sql` | `001_init.up.sql` | `server/migrations/` |
| 测试文件 | 同名 + .test.ts(x) | `issue.test.ts`, `IssueDetail.test.tsx` | 各模块`test/`目录 |
| 配置文件 | kebab-case | `electron-builder.yml`, `turbo.json` | 项目根目录 |

### 函数和方法命名

| 语言 | 规则 | 示例 | 证据 |
|------|------|------|------|
| Go | PascalCase公开方法，小写+下划线私有方法 | `CreateIssue`, `_validateInput` | `server/internal/handler/` |
| TypeScript | camelCase | `createIssue`, `fetchAgents` | `packages/core/` |
| React Query hooks | use前缀 + PascalCase | `useIssues`, `useAgent` | `packages/core/queries/` |
| Event handlers | on前缀 + PascalCase | `onClick`, `onSubmit` | `packages/views/` |

### 类型和接口命名

| 类型 | 规则 | 示例 | 证据 |
|------|------|------|------|
| TypeScript接口 | PascalCase | `Issue`, `AgentRuntime` | `packages/core/types/` |
| TypeScript类型别名 | PascalCase | `IssueStatus`, `AgentProvider` | `packages/core/types/` |
| Go结构体 | PascalCase | `Issue`, `AgentRuntime` | `server/pkg/db/` |
| Go接口 | PascalCase，I前缀罕见 | `Handler`, `Service` | `server/internal/` |
| 常量 | PascalCase或全大写下划线 | `StatusOpen`, `MAX_RETRY` | 两者都有使用 |

### 环境变量命名

| 规则 | 示例 | 证据 |
|------|------|------|
| 全大写下划线分隔 | `DATABASE_URL`, `FRONTEND_PORT` | `.env.example` |
| 前缀按功能分组 | `POSTGRES_*`, `SMTP_*`, `GOOGLE_*` | `.env.example` |
| 前端Public变量 | NEXT_PUBLIC_前缀 | `NEXT_PUBLIC_API_URL` | `.env.example` |

## 格式化和Lint

### Go格式化

- **格式化工具**: `gofmt` (标准库)
- **Linter**: `go vet`, `staticcheck` (via `go vet`)
- **运行**: `make test` (包含lint检查)
- **配置文件**: `server/go.mod`, 无额外配置文件

### TypeScript格式化

- **格式化工具**: ESLint (内置格式化规则)
- **Linter**: ESLint + TypeScript规则
- **配置文件**: `eslint.config.mjs` (各app目录下)
- **React规则**: eslint-plugin-react
- **i18n规则**: eslint-plugin-i18next

### 强制规则

- **TypeScript严格模式**: 已启用，保持类型显式
- **无魔法数字**: 使用命名常量
- **无隐式any**: 禁止 `any` 类型
- **Zustand store选择器**: 必须返回稳定引用，避免每次创建新对象
- **API响应解析**: 使用 `parseWithFallback` + Zod schema，禁止裸 `as` 转换
- **代码注释**: 仅用英文

### 运行命令

```bash
# 运行所有lint检查
pnpm lint

# 运行TypeScript类型检查
pnpm typecheck

# Go格式化
cd server && go fmt ./...

# Go vet检查
cd server && go vet ./...
```

## 导入和模块约定

### Go导入

```go
import (
    // 标准库
    "context"
    "fmt"

    // 外部依赖
    "github.com/go-chi/chi/v5"

    // 内部包
    "github.com/multica-ai/multica/server/internal/handler"
)
```

### TypeScript导入顺序

1. React和框架导入
2. 外部库
3. 内部别名导入（`@/`）
4. 相对导入
5. 类型导入（使用 `type` 关键字）

### 路径别名

| 别名 | 指向 | 证据 |
|------|------|------|
| `@/` | `packages/core/src/` | `packages/tsconfig/` |
| `@ui/` | `packages/ui/components/` | `apps/*/tsconfig.json` |
| `@views/` | `packages/views/` | `apps/*/tsconfig.json` |

### 公开导出策略

- **Barrel文件**: 每个模块的 `index.ts` 导出公共API
- **显式导出**: 避免默认导出，推荐命名导出
- **禁止导出内部实现**: 仅导出公共接口

### 包边界规则

- `packages/core/` - 零react-dom、零localStorage、零process.env
- `packages/ui/` - 零`@multica/core`导入
- `packages/views/` - 零`next/*`、零`react-router-dom`
- 跨平台使用 `NavigationAdapter`

## 错误和日志约定

### 错误策略

| 层 | 策略 | 证据 |
|----|------|------|
| Handler层 | HTTP状态码 + 结构化错误响应 | `server/internal/handler/` |
| Service层 | 领域错误类型，返回error | `server/internal/service/` |
| DB层 | sqlc生成的错误，向上传播 | `server/pkg/db/generated/` |
| Frontend | 解析API错误响应，显示用户消息 | `packages/core/api/` |

### 日志规范

- **后端**: `log/slog` (结构化日志)
- **必需字段**: `level`, `msg`, `error`（如有）
- **上下文**: 请求ID、工作区ID、用户ID等
- **敏感数据**: 禁止记录密码、token、密钥

### Go错误处理

```go
// 使用错误包装
if err != nil {
    return fmt.Errorf("failed to create issue: %w", err)
}

// 使用slog记录
slog.Error("operation failed",
    "operation", "create_issue",
    "error", err,
    "workspace_id", workspaceID,
)
```

### 前端错误处理

- **API错误**: 使用 `parseWithFallback` + Zod schema降级
- **组件错误**: ErrorBoundary捕获
- **异步错误**: try-catch + 用户友好的错误消息

## 测试规范

### 测试文件位置

| 测试内容 | 测试位置 | 原因 |
|---------|---------|------|
| 共享业务逻辑 (stores, queries) | `packages/core/*.test.ts` | 无DOM，纯逻辑 |
| 共享UI组件 (pages, forms, modals) | `packages/views/*.test.tsx` | jsdom，无框架mock |
| 平台特定接线 (cookies, redirects) | `apps/web/*.test.tsx` | 需要框架特定mock |
| E2E用户流程 | `e2e/*.spec.ts` | 真实浏览器，真实后端 |
| Go单元测试 | `*_test.go` | 标准Go测试 |

### 测试文件命名

- TypeScript: `{module}.test.ts` 或 `{Module}.test.tsx`
- Go: `{package}_test.go`
- E2E: `{feature}.spec.ts`

### Mock策略

```typescript
// Zustand store mock示例
import { vi } from 'vitest';

const mockStore = vi.fn();
Object.assign(mockStore, { getState: () => mockStoreState });
```

- **Mock `@multica/core`**: 使用 `vi.hoisted()` + `Object.assign`
- **Mock API调用**: 使用 `vi.mock('@multica/core/api')`
- **禁止Mock**: 禁止在 `packages/views/` 测试中Mock `next/*` 或 `react-router-dom`

### 覆盖率期望

- **TypeScript**: 关键逻辑应有测试覆盖，共享包优先
- **Go**: 关键路径应有测试，数据库测试创建自己的fixture
- **E2E**: 核心用户流程应有端到端测试

### 测试运行

```bash
# 运行所有测试
make check

# 仅TypeScript测试
pnpm test

# 仅Go测试
make test

# E2E测试（需要后端和前端运行）
pnpm exec playwright test

# 单个包测试
pnpm --filter @multica/core exec vitest run runtimes/version.test.ts
```

## API兼容性规则

### 后端变更

- 添加新字段: 向后兼容
- 删除/重命名字段: 标记废弃，逐步移除
- 枚举值变更: 添加default分支处理未知值

### 前端防御

- 使用 `parseWithFallback` 解析所有API响应
- 禁止裸 `as` 转换API响应体
- 可选链和默认值: `field?.property ?? defaultValue`
- Switch语句必须有default分支

### API契约测试

- 变更或添加端点时，在同一PR添加schema
- 编写测试验证格式错误响应
- 使用 `parseWithFallback` + Zod schema

## 证据

- `CLAUDE.md` - 完整编码规则
- `eslint.config.mjs` - ESLint配置
- `packages/core/api/schema.ts` - API响应解析
- `packages/core/api/client.ts` - API客户端
- `packages/views/*.test.tsx` - 测试示例
- `server/internal/handler/` - 错误处理示例
- `Makefile` - 验证命令
