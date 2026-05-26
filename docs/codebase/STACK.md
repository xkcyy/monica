# 技术栈

## 核心技术摘要

| 领域 | 技术 | 证据 |
|------|------|------|
| 后端语言 | Go 1.26+ | `server/go.mod` |
| 前端语言 | TypeScript 5.9+ / React 19.2 | `packages/*/package.json` |
| 包管理器 | pnpm 10.28+ | `package.json` `"packageManager"` |
| 构建系统 | Turborepo 2.5+ | `turbo.json` |
| 后端框架 | Chi router + sqlc + gorilla/websocket | `server/cmd/server/router.go` |
| 前端框架 | Next.js 16 (App Router) + Electron | `apps/web/package.json`, `apps/desktop/package.json` |
| 数据库 | PostgreSQL 17 + pgvector | `.env.example`, `docker-compose.yml` |
| 缓存/消息队列 | Redis | `server/cmd/server/main.go` |
| 容器化 | Docker + Docker Compose | `docker-compose.yml`, `Dockerfile` |

## 生产框架和依赖

### 后端核心依赖

| 依赖 | 版本 | 作用 | 证据 |
|------|------|------|------|
| github.com/go-chi/chi/v5 | ^5.0.0 | HTTP路由框架 | `server/go.mod` |
| github.com/sqlc-dev/sqlc | latest | 类型化SQL代码生成 | `server/sqlc.yaml` |
| github.com/gorilla/websocket | ^1.5.0 | WebSocket实时通信 | `server/go.mod` |
| github.com/jackc/pgx/v5 | ^5.5.0 | PostgreSQL驱动和连接池 | `server/go.mod` |
| github.com/redis/go-redis/v9 | ^9.0.0 | Redis客户端（可选） | `server/cmd/server/main.go` |
| github.com/golang-jwt/jwt/v5 | ^5.0.0 | JWT认证 | `server/internal/auth/` |

### 前端核心依赖

| 依赖 | 版本 | 作用 | 证据 |
|------|------|------|------|
| next | ^16.0.0 | React框架 | `apps/web/package.json` |
| react | 19.2.3 | UI库 | `pnpm-workspace.yaml` catalog |
| @tanstack/react-query | ^5.96.0 | 服务端状态管理 | `packages/core/package.json` |
| zustand | ^5.0.0 | 客户端状态管理 | `pnpm-workspace.yaml` catalog |
| @base-ui/react | latest | shadcn组件基础 | `packages/ui/package.json` |
| tailwindcss | ^4.0.0 | 样式框架 | `packages/ui/package.json` |

### 共享依赖

| 依赖 | 版本 | 作用 | 证据 |
|------|------|------|------|
| zod | ^4.1.0 | 运行时schema验证 | `packages/core/api/schema.ts` |
| i18next | ^26.0.0 | 国际化 | `packages/views/package.json` |
| lucide-react | ^1.0.0 | 图标库 | `packages/ui/package.json` |
| posthog-js | ^1.176.0 | 产品分析 | `packages/core/` |

## 开发工具链

| 工具 | 用途 | 证据 |
|------|------|------|
| Vitest | TypeScript单元测试 | `packages/*/vitest.config.ts` |
| Playwright | E2E测试 | `package.json` devDependencies |
| ESLint | TypeScript linting | `apps/*/eslint.config.mjs` |
| sqlc | Go数据库代码生成 | `server/sqlc.yaml` |
| GoReleaser | Go多平台构建 | `.goreleaser.yml` |
| electron-builder | Electron打包 | `apps/desktop/electron-builder.yml` |
| electron-vite | Electron开发 | `apps/desktop/electron.vite.config.ts` |

## 关键命令

### 前端开发

```bash
# 安装依赖
pnpm install

# 开发模式（启动所有应用）
make dev

# 启动Web应用
pnpm dev:web

# 启动桌面应用
pnpm dev:desktop

# 类型检查
pnpm typecheck

# 运行测试
pnpm test

# 代码检查
pnpm lint

# 构建所有应用
pnpm build
```

### 后端开发

```bash
# 启动后端服务器
make server

# 启动本地daemon
make daemon

# 构建Go二进制
make build

# 运行Go测试
make test

# 数据库迁移
make migrate-up
make migrate-down

# 重新生成sqlc代码
make sqlc

# 运行CLI命令
make cli ARGS="..."
```

### 完整验证

```bash
# 运行所有检查（typecheck + 测试 + E2E）
make check
```

## 环境配置

### 配置文件

- `.env.example` - 环境变量模板
- `.env` - 主环境配置
- `.env.worktree` - Git worktree环境配置
- `docker-compose.yml` - Docker Compose配置
- `docker-compose.selfhost.yml` - 自托管Docker配置
- `docker-compose.production.yml` - 本地生产部署配置
- `turbo.json` - Turborepo任务配置
- `server/sqlc.yaml` - sqlc生成配置
- `Makefile` - Make命令入口

### 必需环境变量

#### 数据库

- `DATABASE_URL` - PostgreSQL连接字符串
- `POSTGRES_DB` - 数据库名（默认：multica）
- `POSTGRES_USER` - 数据库用户
- `POSTGRES_PASSWORD` - 数据库密码
- `POSTGRES_PORT` - PostgreSQL端口（默认：5432）

#### 服务器

- `PORT` - API服务器端口（默认：8080）
- `JWT_SECRET` - JWT签名密钥（生产必需）
- `APP_ENV` - 应用环境（production/development）

#### 前端

- `FRONTEND_PORT` - 前端端口（默认：3000）
- `FRONTEND_ORIGIN` - 前端Origin（CORS用）
- `NEXT_PUBLIC_API_URL` - API地址
- `NEXT_PUBLIC_WS_URL` - WebSocket地址

#### 认证和邮件

- `GOOGLE_CLIENT_ID` - Google OAuth客户端ID
- `GOOGLE_CLIENT_SECRET` - Google OAuth密钥
- `GOOGLE_REDIRECT_URI` - OAuth回调地址
- `RESEND_API_KEY` - Resend邮件API密钥（可选）
- `SMTP_HOST` - SMTP服务器（可选）
- `SMTP_USERNAME` - SMTP用户名（可选）
- `SMTP_PASSWORD` - SMTP密码（可选）

#### Redis（可选）

- `REDIS_URL` - Redis连接字符串（多节点部署必需）

#### 文件存储

- AWS S3相关变量（可选，本地存储为默认）

### 部署约束

- Go 1.26+ 和 Node.js 20+ 为开发环境必需
- Docker用于本地开发和生产自托管
- PostgreSQL 17（带pgvector扩展）
- Redis用于多节点部署的实时消息广播
- CI运行在Node 22和Go 1.26.1上

## 证据

- `package.json` - 前端根配置
- `pnpm-workspace.yaml` - Monorepo配置
- `turbo.json` - 构建任务配置
- `server/go.mod` - Go模块依赖
- `server/sqlc.yaml` - 数据库代码生成配置
- `Makefile` - 构建命令
- `.env.example` - 环境变量模板
- `docker-compose.yml` - Docker配置
- `CLAUDE.md` - 项目架构文档
