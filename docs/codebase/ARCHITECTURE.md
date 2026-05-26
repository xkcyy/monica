# 架构

## 1) 架构风格

- 主要风格：后端是分层架构，前端是 monorepo 共享包 + 应用壳的组合。后端从 router 到 handler 到 service/db 分层；前端把共享业务逻辑、原子 UI、共享视图与 app/desktop 壳分开。
- 分类依据：`server/cmd/server/router.go` 集中挂载路由；后端代码分布在 `server/internal/handler`、`server/internal/service`、`server/pkg/db`；前端边界规则在 `CLAUDE.md` 中明确，且体现在 `packages/core`、`packages/ui`、`packages/views`、`apps/web`、`apps/desktop` 的目录上。
- 主要约束：
  - React Query 负责服务端状态；Zustand 负责客户端状态；WebSocket 事件通过失效缓存驱动刷新，而不是直接写入 store。
  - `packages/core`、`packages/ui`、`packages/views` 有明确边界。
  - runtime/daemon 执行是异步的，并通过 task、WebSocket、数据库记录与 UI 联系起来。

## 2) 系统流

```text
web/desktop/CLI -> 后端路由/中间件 -> handler -> service/sqlc DB 或外部集成 -> realtime/API 响应 -> React Query 失效/UI 更新
```

1. Web 和桌面 UI 通过 `packages/core/api/client.ts` 调用共享 API；`server/cmd/multica/` 下的 CLI 命令调用后端 API 或 daemon/runtime 逻辑。
2. `server/cmd/server/router.go` 负责认证与工作区中间件，然后把请求路由到 `server/internal/handler`。
3. handler 解析 HTTP 输入，并调用 `server/internal/service/*` 和 `server/pkg/db/generated/*` 等层。
4. 持久化状态写入 PostgreSQL，表结构定义在 `server/migrations/*.sql`，访问通过 sqlc 生成代码完成。
5. runtime 工作通过 agent task 和 daemon/runtime message 表达；daemon 路由负责 claim、update、complete、fail、usage、message 等生命周期操作。
6. `server/internal/realtime/` 里的 WebSocket 组件广播 workspace/user/task/chat 变化，供 UI 刷新缓存。

## 3) 完整功能地图

| 领域 | 当前能力 | 主要证据 |
|------|----------|----------|
| 认证与会话 | 邮件验证码、Google OAuth、退出登录、当前用户、onboarding 状态、JWT cookie、CloudFront 媒体 cookie | `server/internal/handler/auth.go`, `server/cmd/server/router.go`, `packages/core/api/client.ts`, `server/internal/auth/cloudfront.go` |
| 工作区生命周期 | 工作区列表/详情/创建/更新/删除、slug 级中间件、starter content、共享客户端状态中的当前工作区选择 | `server/cmd/server/router.go`, `server/internal/middleware/workspace.go`, `packages/core/api/client.ts`, `packages/core/` |
| 成员与邀请 | 工作区成员、成员详情、邀请创建/列表/接受流程、邀请页 | `server/cmd/server/router.go`, `server/migrations/041_workspace_invitation.up.sql`, `apps/web/app/invitations/`, `apps/web/app/invite/[id]/` |
| Issues | 列表、分组/搜索视图、详情、快速创建、批量更新/删除、层级/子任务、状态/优先级/负责人、标签、订阅者、附件、时间线、task 使用、rerun、reactions、PR 关联 | `server/internal/handler/issue.go`, `server/cmd/server/router.go`, `packages/core/api/client.ts`, `packages/views/issues/`, `server/migrations/001_init.up.sql`, `server/migrations/015_issue_subscriber.up.sql`, `server/migrations/029_attachment.up.sql`, `server/migrations/079_github_integration.up.sql` |
| 评论与讨论 | Issue 评论、回复/解决、评论 reactions、附件相关流程 | `server/internal/handler/comment.go`, `server/cmd/server/router.go`, `server/migrations/026_comment_reactions.up.sql`, `packages/core/api/client.ts` |
| Agents | CRUD、归档/恢复、模板、私有/工作区可见性、自定义指令、模型/自定义参数/env/MCP 配置、skill 绑定、任务/活动/运行次数、snapshot/presence | `server/cmd/server/router.go`, `server/internal/handler/agent*.go`, `server/migrations/001_init.up.sql`, `server/migrations/008_structured_skills.up.sql`, `packages/core/api/client.ts`, `packages/views/agents/` |
| Agent runtime 与 daemon | daemon 注册/注销/heartbeat/ws、workspace repos、runtime task claim/pending/update/status/start/progress/complete/fail、usage/messages、GC 检查、孤儿恢复、pin session、模型/local skill 上报 | `server/cmd/server/router.go`, `server/internal/handler/daemon.go`, `server/internal/daemon/`, `server/migrations/004_agent_runtime_loop.up.sql`, `server/cmd/multica/`, `CLI_AND_DAEMON.md` |
| 与 agent 的聊天 | chat session/message、附件、pending task 关联、读状态/任务驱动聊天流程 | `server/migrations/033_chat.up.sql`, `server/cmd/server/router.go`, `packages/core/api/client.ts`, `packages/views/chat/` |
| Projects 与资源 | 项目 CRUD/详情与 project resources | `server/migrations/034_projects.up.sql`, `server/migrations/065_project_resources.up.sql`, `server/cmd/server/router.go`, `packages/core/api/client.ts`, `packages/views/projects/` |
| Skills | 工作区 skills、skill 文件、导入流程、本地 runtime skill 结果、分配给 agent | `server/migrations/008_structured_skills.up.sql`, `server/cmd/server/router.go`, `server/internal/handler/skill*.go`, `packages/core/api/client.ts`, `packages/views/skills/` |
| Squads | Squad CRUD/详情/成员关系、issue assignee 类型 `squad`、evaluation/no-action 支持 | `server/migrations/084_squad.up.sql`, `server/cmd/server/router.go`, `packages/core/api/client.ts`, `packages/views/squads/` |
| Autopilots | Autopilot CRUD、triggers、run history、定时/手动执行、`create_issue` 与 `run_only` 动作 | `server/migrations/042_autopilot.up.sql`, `server/internal/service/autopilot.go`, `server/internal/service/autopilot_scheduler.go`, `server/cmd/multica/cmd_autopilot.go`, `packages/views/autopilots/` |
| Inbox 与通知 | Inbox items、通知偏好、已读/未读更新流程 | `server/migrations/001_init.up.sql`, `server/migrations/064_notification_preference.up.sql`, `server/cmd/server/router.go`, `packages/core/api/client.ts`, `packages/views/inbox/` |
| 用量与仪表盘 | usage 端点、task usage 汇总、dashboard 端点 | `server/migrations/073_task_usage_daily_rollup.up.sql`, `server/migrations/077_task_usage_daily_invalidation.up.sql`, `server/migrations/084_task_usage_dashboard_rollup.up.sql`, `server/cmd/server/router.go`, `packages/core/api/client.ts` |
| 标签 | Label CRUD 与 issue-label 关系 | `server/internal/handler/label.go`, `server/migrations/001_init.up.sql`, `server/cmd/server/router.go` |
| Pins | 工作区置顶项 | `server/migrations/038_pinned_items.up.sql`, `server/cmd/server/router.go`, `packages/core/api/client.ts` |
| 附件/文件 | 上传 API、本地/S3 存储后端、附件元数据与签名读 URL | `server/internal/handler/file.go`, `server/internal/storage/`, `server/migrations/029_attachment.up.sql`, `.env.example` |
| GitHub 集成 | GitHub App setup 回调、webhook 校验、installation 存储、PR 关联、PR 合并后 issue 自动推进 | `server/internal/handler/github.go`, `server/migrations/079_github_integration.up.sql`, `.env.example`, `server/cmd/server/router.go` |
| CLI | auth/config/setup/daemon/workspace/issue/project/label/agent/autopilot/runtime/repo/skill/squad/attachment/update/version 等命令面 | `server/cmd/multica/`, `CLI_INSTALL.md`, `CLI_AND_DAEMON.md` |
| Web 产品壳 | 首页、下载、关于、更新日志、登录、回调、工作区、onboarding、invite 路由 + 工作区 dashboard | `apps/web/app/`, `packages/core/paths/paths.ts` |
| 桌面壳 | Electron 工作区 dashboard、window overlay、daemon/update 桌面设置 | `apps/desktop/src/renderer/src/routes.tsx`, `apps/desktop/src/renderer/src/components/window-overlay.tsx`, `apps/desktop/package.json` |
| 文档站 | Fumadocs 文档内容站 | `apps/docs/package.json`, `apps/docs/` |

## 4) 层/模块职责

| 层或模块 | 负责 | 不应负责 | 证据 |
|----------|------|----------|------|
| `server/cmd/server` | 进程启动、路由拓扑、中间件组合 | 业务工作流 | `server/cmd/server/main.go`, `server/cmd/server/router.go` |
| `server/internal/middleware` | 认证、工作区上下文、请求级别职责 | 领域持久化 | `server/internal/middleware/` |
| `server/internal/handler` | API 输入输出边界 | React 状态或 CLI 命令解析 | `server/internal/handler/` |
| `server/internal/service` | 业务工作流与后台调度 | HTTP 路由声明 | `server/internal/service/` |
| `server/pkg/db` | 数据库模型与查询函数 | 外部 API 副作用 | `server/pkg/db/`, `server/sqlc.yaml` |
| `server/internal/realtime` | WebSocket hub、广播/中继、连接健康 | 持久化 schema 归属 | `server/internal/realtime/` |
| `server/pkg/agent` | CLI/runtime adapter 策略 | 工作区 UI 组合 | `server/pkg/agent/` |
| `packages/core` | API client、React Query hooks、stores、path/type helpers | DOM 渲染与 app 专属平台 API | `CLAUDE.md`, `packages/core/` |
| `packages/ui` | 原子可复用 UI | 业务逻辑和 `@multica/core` 导入 | `CLAUDE.md`, `packages/ui/` |
| `packages/views` | 可复用产品视图/页面 | Next.js 或 React Router APIs | `CLAUDE.md`, `packages/views/` |
| `apps/web` | Next.js app 壳、路由文件、平台专属 API | 共享业务状态实现 | `apps/web/`, `CLAUDE.md` |
| `apps/desktop` | Electron 壳、renderer 宿主、preload/main 集成 | Web-only Next.js route handler | `apps/desktop/`, `CLAUDE.md` |

## 5) 复用模式

| 模式 | 出现位置 | 存在原因 |
|------|----------|----------|
| router -> middleware -> handler -> service/db | `server/cmd/server/router.go`, `server/internal/handler/`, `server/internal/service/`, `server/pkg/db/` | 保持 HTTP 路由、请求处理、业务工作流与持久化分离 |
| sqlc 生成数据库访问 | `server/sqlc.yaml`, `server/pkg/db/queries/`, `server/pkg/db/generated/` | 提供类型化的 Go SQL 访问层 |
| React Query + Zustand 分工 | `CLAUDE.md`, `packages/core/` | 将服务端缓存与客户端 UI 状态分开 |
| NavigationAdapter | `CLAUDE.md`, `packages/views/`, app shells | 让共享视图可同时在 Web 与 Electron 中使用 |
| runtime adapter 策略 | `server/pkg/agent/*.go` | 用不同 adapter 支持多种 agent CLI |
| WebSocket 失效/广播 | `server/internal/realtime/`, `packages/core/` | 保证多客户端 UI 围绕 workspace/user/task/chat 更新 |
| 环境变量驱动 + fallback | `.env.example`, `server/internal/storage/`, `server/internal/service/email.go`, `server/internal/analytics/posthog.go` | 使本地/自托管/云部署共用同一代码库 |

## 6) 意图与现实差异

- README/架构文本和 compose 镜像都指向 PostgreSQL + pgvector，但当前工作副本的迁移创建/使用的是 `pgcrypto`、`pg_bigm` 与可选 `pg_cron`；未发现 `CREATE EXTENSION vector`。`[ASK USER]` 请确认 vector 搜索是计划中、已移除，还是存在未扫描环境要求。
- Autopilot schema/API 支持的 trigger 类型多于当前可见的 schedule/manual 流程；未发现 `webhook` 或 `api` trigger 的入站 API/端点。`[ASK USER]` 请确认这些 trigger 类型是计划中/内部能力，还是应该作为产品功能暴露。
- `CLI_AND_DAEMON.md` 对 autopilot CLI 的描述偏旧；当前 CLI 和 UI 里已经有 `run_only`。
- `.env.example` 记录了 `ALLOWED_ORIGINS`，而 `server/cmd/server/router.go` 的 HTTP CORS 使用 `CORS_ALLOWED_ORIGINS`；realtime 也同时检查 `ALLOWED_ORIGINS`。`[ASK USER]` 请确认 HTTP 与 WebSocket 的 origin 配置命名。

## 7) 已知架构风险

- `server/cmd/server/router.go` 集中承载大量路由与中间件，改动容易波及多个领域。
- `packages/core/api/client.ts` 是共享 API 面，且出现在高 churn 文件中；请求/响应类型变更会连带影响 Web、Desktop 和 views。
- runtime/daemon/task 路径跨 CLI、daemon handler、realtime、数据库和 UI，端到端改动风险较高。
- 部分能力已经在 schema/API 类型上出现，但可见的产品入口尚未完全对齐，例如 autopilot 的 `webhook`/`api` triggers。

## 8) 证据

- `CLAUDE.md`
- `README.md`
- `README.zh-CN.md`
- `CLI_AND_DAEMON.md`
- `CLI_INSTALL.md`
- `server/cmd/server/main.go`
- `server/cmd/server/router.go`
- `server/cmd/multica/`
- `server/internal/handler/`
- `server/internal/service/`
- `server/internal/realtime/`
- `server/internal/middleware/`
- `server/pkg/agent/`
- `server/pkg/db/`
- `server/migrations/`
- `packages/core/api/client.ts`
- `packages/core/paths/paths.ts`
- `packages/views/`
- `packages/ui/`
- `apps/web/app/`
- `apps/desktop/src/renderer/src/routes.tsx`
- `apps/desktop/src/renderer/src/components/window-overlay.tsx`
- `docs/codebase/.codebase-scan.txt`
