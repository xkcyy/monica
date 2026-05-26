# 代码库结构

## 顶层目录结构

| 路径 | 用途 | 证据 |
|------|------|------|
| `server/` | Go后端应用 | `server/go.mod` |
| `apps/` | 前端应用（web/desktop/docs） | `package.json` workspaces |
| `packages/` | 共享包（core/ui/views/tsconfig） | `pnpm-workspace.yaml` |
| `docs/` | 项目文档 | - |
| `docker/` | Docker配置文件 | `docker-compose.yml` |
| `.agents/` | AI agent技能配置 | `.agents/skills/` |
| `scripts/` | 工具脚本 | `scripts/` |

### 后端结构 (`server/`)

| 路径 | 用途 | 证据 |
|------|------|------|
| `cmd/server/` | 服务器入口点 | `server/cmd/server/main.go` |
| `cmd/multica/` | CLI命令实现 | `server/cmd/multica/` |
| `internal/handler/` | HTTP请求处理层 | `server/internal/handler/` |
| `internal/service/` | 业务逻辑层 | `server/internal/service/` |
| `internal/middleware/` | 中间件（认证/工作区） | `server/internal/middleware/` |
| `internal/realtime/` | WebSocket实时通信 | `server/internal/realtime/` |
| `internal/daemonws/` | Daemon WebSocket | `server/internal/daemonws/` |
| `internal/auth/` | 认证逻辑 | `server/internal/auth/` |
| `internal/events/` | 事件总线 | `server/internal/events/` |
| `internal/analytics/` | 分析集成 | `server/internal/analytics/` |
| `internal/storage/` | 文件存储抽象 | `server/internal/storage/` |
| `pkg/agent/` | Agent runtime适配器 | `server/pkg/agent/` |
| `pkg/db/generated/` | sqlc生成的代码 | `server/pkg/db/generated/` |
| `pkg/db/queries/` | SQL查询定义 | `server/pkg/db/queries/` |
| `migrations/` | 数据库迁移文件 | `server/migrations/` |

### 前端应用结构 (`apps/`)

| 路径 | 用途 | 证据 |
|------|------|------|
| `apps/web/` | Next.js Web应用 | `apps/web/package.json` |
| `apps/web/app/` | Next.js App Router页面 | `apps/web/app/` |
| `apps/web/features/` | Web特性模块 | `apps/web/features/` |
| `apps/web/platform/` | Web平台特定代码 | `apps/web/platform/` |
| `apps/web/components/` | Web共享组件 | `apps/web/components/` |
| `apps/desktop/` | Electron桌面应用 | `apps/desktop/package.json` |
| `apps/desktop/src/main/` | Electron主进程 | `apps/desktop/src/main/` |
| `apps/desktop/src/preload/` | Electron预加载脚本 | `apps/desktop/src/preload/` |
| `apps/desktop/src/renderer/` | Electron渲染进程 | `apps/desktop/src/renderer/` |
| `apps/desktop/src/shared/` | 跨进程共享代码 | `apps/desktop/src/shared/` |
| `apps/docs/` | Fumadocs文档站 | `apps/docs/package.json` |
| `apps/docs/content/` | 文档内容 | `apps/docs/content/` |

### 共享包结构 (`packages/`)

| 路径 | 用途 | 证据 |
|------|------|------|
| `packages/core/` | 无头业务逻辑 | `packages/core/package.json` |
| `packages/core/api/` | API客户端 | `packages/core/api/client.ts` |
| `packages/core/platform/` | 平台桥接 | `packages/core/platform/` |
| `packages/core/stores/` | Zustand状态存储 | `packages/core/stores/` |
| `packages/core/queries/` | React Query hooks | `packages/core/queries/` |
| `packages/ui/` | 原子UI组件 | `packages/ui/package.json` |
| `packages/ui/components/` | UI组件 | `packages/ui/components/` |
| `packages/ui/styles/` | 共享样式 | `packages/ui/styles/` |
| `packages/views/` | 共享业务视图 | `packages/views/package.json` |
| `packages/views/issues/` | Issue视图 | `packages/views/issues/` |
| `packages/views/agents/` | Agent视图 | `packages/views/agents/` |
| `packages/views/chat/` | 聊天视图 | `packages/views/chat/` |
| `packages/views/layout/` | 布局组件 | `packages/views/layout/` |
| `packages/tsconfig/` | TypeScript配置 | `packages/tsconfig/` |

## 入口点

### 后端入口

- **主服务器**: `server/cmd/server/main.go` - 启动HTTP服务器、WebSocket hub、后台任务
- **CLI工具**: `server/cmd/multica/main.go` - 多命令CLI（auth/setup/daemon/issue等）
- **服务器路由**: `server/cmd/server/router.go` - Chi路由配置，挂载所有API端点

### 前端入口

- **Web应用**: `apps/web/app/layout.tsx` - Next.js根布局
- **桌面应用**: `apps/desktop/src/main/index.ts` - Electron主进程入口
- **桌面渲染**: `apps/desktop/src/renderer/src/main.tsx` - React渲染入口
- **文档站**: `apps/docs/source.config.ts` - Fumadocs配置

### 启动流程

1. `make dev` 自动检测环境（主checkout/worktree）
2. 创建必要的环境文件（`.env`或`.env.worktree`）
3. 启动共享PostgreSQL容器
4. 运行数据库迁移
5. 并行启动后端服务器和前端开发服务器

## 模块边界

### 后端分层

| 层 | 职责 | 禁止内容 | 证据 |
|----|------|---------|------|
| `server/cmd/server` | 进程启动、路由拓扑、中间件组合 | 业务工作流 | `server/cmd/server/main.go` |
| `internal/middleware` | 认证、工作区上下文、请求级别职责 | 领域持久化 | `server/internal/middleware/` |
| `internal/handler` | API输入输出边界、请求解析 | React状态或CLI命令解析 | `server/internal/handler/` |
| `internal/service` | 业务工作流、后台调度 | HTTP路由声明 | `server/internal/service/` |
| `pkg/db` | 数据库模型与查询函数 | 外部API副作用 | `server/pkg/db/` |
| `internal/realtime` | WebSocket hub、广播/中继 | 持久化schema归属 | `server/internal/realtime/` |

### 前端分层

| 包 | 职责 | 禁止内容 | 证据 |
|----|------|---------|------|
| `packages/core` | API client、React Query hooks、stores、path helpers | DOM渲染、平台特定API | `packages/core/` |
| `packages/ui` | 原子可复用UI组件 | 业务逻辑和`@multica/core`导入 | `packages/ui/` |
| `packages/views` | 可复用产品视图/页面 | Next.js或react-router APIs | `packages/views/` |
| `apps/web` | Next.js app壳、路由文件 | 共享业务状态实现 | `apps/web/` |
| `apps/desktop` | Electron壳、渲染宿主 | Web-only Next.js APIs | `apps/desktop/` |

### 硬性规则

- **`packages/core/`** - 零react-dom、零localStorage（用StorageAdapter）、零process.env、零UI库
- **`packages/ui/`** - 零`@multica/core`导入（纯UI，无业务逻辑）
- **`packages/views/`** - 零`next/*`导入、零`react-router-dom`导入，使用NavigationAdapter
- **`apps/web/platform/`** - Next.js API唯一位置
- **`apps/desktop/src/renderer/src/platform/`** - react-router-dom导航唯一位置

## 命名和组织规则

### 文件命名

| 类型 | 规则 | 示例 |
|------|------|------|
| Go文件 | 小写下划线分隔 | `issue_handler.go`, `task_service.go` |
| TypeScript组件 | PascalCase | `IssueDetail.tsx`, `AgentCard.tsx` |
| TypeScript工具 | camelCase | `apiClient.ts`, `parseWithFallback.ts` |
| SQL文件 | 小写下划线分隔 | `issue.sql`, `agent.sql` |
| 迁移文件 | `NNN_name.up.sql` / `NNN_name.down.sql` | `001_init.up.sql` |

### 目录组织

| 组织方式 | 应用场景 |
|---------|---------|
| 按领域/功能 | `packages/views/issues/`, `server/internal/handler/` |
| 按层 | `server/internal/handler/`, `server/internal/service/` |
| 按包 | `packages/core/api/`, `packages/core/stores/` |

### 导入约定

- **TypeScript路径别名**: 使用`@/`指向`packages/core/src/`等
- **Go包导入**: `github.com/multica-ai/multica/server/internal/handler`
- **内部包**: 使用相对导入或具名导入

### API客户端使用

- 所有API调用通过`packages/core/api/client.ts`
- React Query hooks封装在`packages/core/queries/`中
- Zustand stores集中在`packages/core/stores/`中
- 跨平台使用`NavigationAdapter`处理路由

## 证据

- `package.json` - Monorepo根配置
- `pnpm-workspace.yaml` - workspace定义
- `server/cmd/server/main.go` - 后端入口
- `server/cmd/server/router.go` - 路由配置
- `packages/core/api/client.ts` - API客户端
- `CLAUDE.md` - 架构决策文档
- `CONTRIBUTING.md` - 开发工作流
