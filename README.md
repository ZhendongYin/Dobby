# Dobby

抽奖活动管理系统 - 基于 Phoenix LiveView 构建的现代化 Web 应用。

## 快速开始

### 本地开发

```bash
# 安装依赖
mix setup

# 启动服务器
mix phx.server
```

访问 [`localhost:4000`](http://localhost:4000) 开始使用。

#### 初始化数据库

首次运行后，需要创建种子数据（默认管理员和奖品模板）：

```bash
# 本地开发
mix run priv/repo/seeds.exs

# Docker 环境
./docker-start.sh seed

# 或使用自定义管理员密码
ADMIN_PASSWORD=your_password ./docker-start.sh seed
```

默认管理员账号：
- 邮箱: `admin@dobby.com`
- 密码: `Admin123!` (或通过环境变量 `ADMIN_PASSWORD` 设置)

⚠️ **重要**: 生产环境请立即修改默认管理员密码！

### Docker 部署（推荐）

使用 Docker 一键部署，脚本会自动处理所有配置。

#### 前置要求

- Docker >= 20.10
- Docker Compose >= 2.0

#### 一键启动

```bash
./docker-start.sh start
```

脚本会自动：
- ✅ 创建 `.env` 文件（如果不存在）
- ✅ 生成 `SECRET_KEY_BASE` 和数据库密码
- ✅ 构建 Docker 镜像
- ✅ 启动所有服务（数据库、Redis、应用）
- ✅ 运行数据库迁移

#### 常用命令

| 命令 | 说明 |
|------|------|
| `./docker-start.sh start` | 构建并启动所有服务 |
| `./docker-start.sh stop` | 停止所有服务 |
| `./docker-start.sh restart` | 重启所有服务 |
| `./docker-start.sh logs` | 查看日志 |
| `./docker-start.sh logs db` | 查看数据库日志 |
| `./docker-start.sh build` | 重新构建镜像 |
| `./docker-start.sh clean` | 停止服务并删除数据卷 |
| `./docker-start.sh migrate` | 手动运行数据库迁移 |
| `./docker-start.sh seed` | 运行数据库种子数据（创建默认管理员和奖品模板） |
| `./docker-start.sh shell` | 进入应用容器 |
| `./docker-start.sh env` | 查看环境变量配置 |

#### 环境变量配置

首次运行后，脚本会创建 `.env` 文件。你可以编辑它来配置：

**必需配置：**
- `SECRET_KEY_BASE` - 已自动生成，无需修改
- `POSTGRES_PASSWORD` - 已自动生成，可自定义
- `PHX_HOST` - 应用访问地址（生产环境需要修改）

**可选配置（AWS 服务）：**
- `AWS_REGION` - AWS 区域
- `AWS_ACCESS_KEY_ID` - AWS 访问密钥
- `AWS_SECRET_ACCESS_KEY` - AWS 密钥
- `S3_BUCKET` - S3 存储桶名称
- `CLOUDFRONT_URL` - CloudFront CDN 地址
- `FROM_EMAIL` - 发件人邮箱
- `SUPPORT_EMAIL` - 支持邮箱

#### 开发环境（仅数据库和 Redis）

如果只想在本地运行数据库和 Redis：

```bash
docker-compose -f docker-compose.dev.yml up -d
```

#### 手动部署

如果你更喜欢手动控制：

```bash
# 1. 创建 .env 文件（参考上面的配置）
# 2. 构建镜像
docker-compose build

# 3. 启动服务
docker-compose up -d

# 4. 查看日志
docker-compose logs -f web
```

#### 故障排除

**查看日志：**
```bash
./docker-start.sh logs
# 或
docker-compose logs -f web
```

**重新生成 Secret Key：**
```bash
mix phx.gen.secret  # 如果已安装 Elixir
# 或
openssl rand -base64 64 | tr -d '\n' | tr -d '=' | cut -c1-64
```

**完全重置：**
```bash
./docker-start.sh clean  # 删除所有数据
./docker-start.sh start  # 重新启动
```

## 项目结构

- `lib/dobby/` - 业务逻辑层
- `lib/dobby_web/` - Web 层（LiveView、组件、路由）
- `priv/repo/migrations/` - 数据库迁移文件
- `test/` - 测试文件

## 技术栈

- **Phoenix** - Web 框架
- **LiveView** - 实时交互
- **PostgreSQL** - 数据库
- **Redis** - 缓存
- **Docker** - 容器化部署

## 了解更多

- [Phoenix 官方文档](https://hexdocs.pm/phoenix)
- [Phoenix LiveView 指南](https://hexdocs.pm/phoenix_live_view)
- [部署指南](https://hexdocs.pm/phoenix/deployment.html)
