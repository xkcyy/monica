# 外部集成

## 集成清单

| 系统 | 类型 | 用途 | 认证模型 | 关键性 | 证据 |
|------|------|------|---------|--------|------|
| PostgreSQL | 数据库 | 持久化存储 | 连接字符串 | 高 | `server/pkg/db/` |
| Redis | 缓存/消息队列 | 多节点广播、运行时状态缓存 | URL | 中 | `server/cmd/server/main.go` |
| Google OAuth | 身份提供商 | 用户登录 | OAuth 2.0 | 高 | `server/internal/auth/`, `GOOGLE_CLIENT_ID` |
| Resend | 邮件服务 | 发送验证邮件 | API密钥 | 中 | `server/internal/service/email.go` |
| SMTP | 邮件服务 | 自托管邮件发送 | 用户名/密码 | 低 | `server/internal/service/email.go` |
| AWS S3 | 对象存储 | 文件上传和附件 | IAM凭证/环境变量 | 中 | `server/internal/storage/` |
| Local Storage | 文件存储 | 开发环境文件存储 | 本地路径 | 中 | `server/internal/storage/` |
| GitHub | 外部API | GitHub App集成、PR关联 | GitHub App | 中 | `server/internal/handler/github.go` |
| CloudFront | CDN | 媒体文件访问 | AWS签名 | 低 | `server/internal/auth/cloudfront.go` |
| Posthog | 产品分析 | 使用追踪 | API密钥 | 低 | `server/internal/analytics/posthog.go` |
| Claude Code | Agent CLI | Agent运行时 | 无（本地执行） | 高 | `server/pkg/agent/` |
| Codex | Agent CLI | Agent运行时 | 无（本地执行） | 高 | `server/pkg/agent/` |
| GitHub Copilot CLI | Agent CLI | Agent运行时 | 无（本地执行） | 高 | `server/pkg/agent/` |

## 数据存储

### PostgreSQL

| 方面 | 详情 | 证据 |
|------|------|------|
| 角色 | 主数据存储 | `server/pkg/db/` |
| 访问层 | sqlc生成类型化查询 | `server/pkg/db/generated/` |
| 连接池 | pgxpool | `server/cmd/server/main.go` |
| 迁移 | golang-migrate | `server/migrations/` |
| 扩展 | pgcrypto, pg_bigm, pg_cron (可选) | 迁移文件 |
| 主要表 | workspaces, users, issues, agents, tasks, comments, projects, skills, squads | `001_init.up.sql` |

### Redis

| 方面 | 详情 | 证据 |
|------|------|------|
| 角色 | 可选：多节点实时广播、运行时状态缓存 | `server/cmd/server/main.go` |
| 访问层 | go-redis/v9 | `server/cmd/server/main.go` |
| 使用场景 | 实时消息中继、runtime liveness cache、PAT cache、empty claim cache | `server/internal/realtime/`, `server/internal/handler/runtime_liveness_store.go` |
| 单节点模式 | 可选，无Redis时使用内存hub | `server/cmd/server/main.go` |
| 关键风险 | Redis故障导致实时功能降级 | `server/internal/realtime/` |

## 凭证和密钥处理

### 凭证来源

| 类型 | 来源 | 证据 |
|------|------|------|
| 数据库 | 环境变量 `DATABASE_URL` | `.env.example` |
| Redis | 环境变量 `REDIS_URL` | `.env.example` |
| JWT | 环境变量 `JWT_SECRET` | `.env.example`, `server/cmd/server/main.go` |
| Google OAuth | 环境变量 `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | `.env.example` |
| Resend | 环境变量 `RESEND_API_KEY` | `.env.example` |
| SMTP | 环境变量 `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD` | `.env.example` |
| AWS S3 | 环境变量 `AWS_*` | `.env.example` |
| GitHub App | 环境变量 `GITHUB_APP_SLUG`, `GITHUB_WEBHOOK_SECRET` | `.env.example` |

### 硬编码检查

- **结果**: 无硬编码凭证发现
- 所有密钥和密码通过环境变量注入
- `.env.example` 包含模板但不包含真实密钥
- `.env` 文件不在版本控制中 (`.gitignore`)

### 密钥轮换

- JWT_SECRET: 需要重启服务
- 数据库凭证: 需要重启服务
- OAuth/API密钥: 通常需要重启
- 最佳实践: 使用密钥管理服务 (KMS)

## 可靠性和失败行为

### 重试和退避

| 集成 | 重试策略 | 退避策略 | 证据 |
|------|---------|---------|------|
| PostgreSQL | pgx内置重连 | 指数退避 | `server/pkg/db/` |
| Redis | go-redis内置重连 | 指数退避 | `server/internal/realtime/` |
| 外部API | 无统一重试 | - | 各handler实现 |
| S3上传 | 无重试 | - | `server/internal/storage/` |

### 超时策略

| 连接 | 超时设置 | 证据 |
|------|---------|------|
| 数据库 | pgxpool配置 | `server/cmd/server/main.go` |
| Redis | go-redis默认 | `server/cmd/server/main.go` |
| HTTP客户端 | 各handler自定义 | `packages/core/api/client.ts` |
| WebSocket | 无硬超时 | `server/internal/realtime/` |

### 熔断和降级

| 场景 | 行为 | 证据 |
|------|------|------|
| Redis不可用 | 降级到内存hub，单节点模式 | `server/cmd/server/main.go` |
| S3不可用 | 降级到本地存储 | `server/internal/storage/` |
| 邮件服务不可用 | 验证码打印到日志（开发模式） | `server/cmd/server/main.go` |
| 外部API超时 | 返回错误，用户可见 | 各handler |

## 集成的可观测性

### 日志记录

| 集成 | 日志位置 | 日志级别 | 证据 |
|------|---------|---------|------|
| 数据库操作 | slog标准输出 | Info/Error | `server/cmd/server/main.go` |
| Redis操作 | slog标准输出 | Debug/Error | `server/internal/realtime/` |
| 认证失败 | slog标准输出 | Warn | `server/internal/auth/` |
| 外部API调用 | slog标准输出 | Info/Error | `server/internal/handler/` |
| 文件上传 | slog标准输出 | Info/Error | `server/internal/handler/file.go` |

### 指标覆盖

| 指标类型 | 覆盖 | 证据 |
|---------|------|------|
| HTTP请求 | 是 | `obsmetrics` 包 |
| 数据库查询 | 部分 | `server/internal/metrics/` |
| WebSocket连接 | 是 | `realtime` hub |
| Agent运行时 | 是 | task usage tracking |
| 自定义指标 | 是 | Prometheus格式 |

### 可见性缺口

| 缺口 | 影响 | 建议 |
|------|------|------|
| 无分布式追踪 | 调试困难 | 添加OpenTelemetry |
| 无API响应时间P50/P95 | 性能盲点 | 添加histogram指标 |
| 无前端性能监控 | 用户体验盲点 | 添加web-vitals |

## Agent CLI集成

### 支持的Agent运行时

| Agent | 类型 | 适配器 | 证据 |
|-------|------|-------|------|
| Claude Code | 官方CLI | `server/pkg/agent/claude_code.go` | `server/pkg/agent/` |
| Codex | OpenAI CLI | `server/pkg/agent/codex.go` | `server/pkg/agent/` |
| GitHub Copilot CLI | GitHub CLI | `server/pkg/agent/copilot.go` | `server/pkg/agent/` |
| OpenClaw | 开源CLI | `server/pkg/agent/openclaw.go` | `server/pkg/agent/` |
| OpenCode | 开源CLI | `server/pkg/agent/opencode.go` | `server/pkg/agent/` |
| Hermes | 开源CLI | `server/pkg/agent/hermes.go` | `server/pkg/agent/` |
| Gemini CLI | Google CLI | `server/pkg/agent/gemini.go` | `server/pkg/agent/` |
| Pi CLI | Anthropic CLI | `server/pkg/agent/pi.go` | `server/pkg/agent/` |
| Cursor Agent | Cursor内置 | `server/pkg/agent/cursor.go` | `server/pkg/agent/` |
| Kimi | 月之暗面CLI | `server/pkg/agent/kimi.go` | `server/pkg/agent/` |
| Kiro CLI | Kiro CLI | `server/pkg/agent/kiro.go` | `server/pkg/agent/` |

### Daemon架构

```
┌──────────────┐     WebSocket      ┌──────────────────┐
│ Local Daemon │ ←───────────────→ │  Backend Server  │
│  (CLI)       │                   │                  │
└──────────────┘                   └──────────────────┘
      ↑                                    ↑
      │ 执行Agent命令                       │ API/数据库
      ↓                                    ↓
┌──────────────┐                   ┌──────────────────┐
│ Claude Code  │                   │   PostgreSQL     │
│ Codex等CLI   │                   │   (持久化)       │
└──────────────┘                   └──────────────────┘
```

## 证据

- `.env.example` - 环境变量模板
- `server/cmd/server/main.go` - 服务启动和依赖注入
- `server/internal/auth/` - 认证实现
- `server/internal/storage/` - 文件存储抽象
- `server/internal/service/email.go` - 邮件服务
- `server/internal/realtime/` - WebSocket实时通信
- `server/internal/analytics/posthog.go` - 分析集成
- `server/internal/handler/github.go` - GitHub集成
- `server/pkg/agent/` - Agent运行时适配器
- `packages/core/api/client.ts` - 前端API客户端
