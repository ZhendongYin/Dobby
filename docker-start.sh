#!/bin/bash
# Docker 启动脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Dobby Docker 部署脚本${NC}"
echo ""

# 生成 Secret Key Base 的函数
generate_secret_key() {
    # 尝试使用 mix phx.gen.secret（如果可用）
    if command -v mix >/dev/null 2>&1; then
        mix phx.gen.secret 2>/dev/null && return
    fi
    
    # 如果 mix 不可用，使用 openssl 生成（类似 mix 的实现）
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 64 | tr -d '\n' | tr -d '=' | cut -c1-64
        return
    fi
    
    # 最后使用 /dev/urandom
    head -c 32 /dev/urandom | base64 | tr -d '\n' | tr -d '=' | cut -c1-64
}

# 初始化环境变量文件
init_env_file() {
    local secret_key=$(generate_secret_key)
    # 生成只包含字母和数字的密码（URL 安全，避免特殊字符问题）
    local db_password=$(openssl rand -hex 32 | tr -d '\n' | cut -c1-32 2>/dev/null || echo "postgres")
    
    echo -e "${BLUE}📝 创建 .env 文件...${NC}"
    
    cat > .env << EOF
# Database Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${db_password}
POSTGRES_DB=dobby_prod
POSTGRES_PORT=5432

# Redis Configuration
REDIS_URL=redis://redis:6379
REDIS_PORT=6379

# Server Configuration
PORT=4000
PHX_HOST=localhost
PHX_SERVER=true

# Secret Key (自动生成)
SECRET_KEY_BASE=${secret_key}

# Database Pool
POOL_SIZE=10

# AWS Configuration (for production)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
S3_BUCKET=
CLOUDFRONT_URL=

# SES Configuration
AWS_SES_REGION=us-east-1
FROM_EMAIL=noreply@yourdomain.com
SUPPORT_EMAIL=support@yourdomain.com
EOF
    
    echo -e "${GREEN}✅ .env 文件已创建${NC}"
    echo -e "${YELLOW}⚠️  请检查并修改 .env 文件中的配置，特别是：${NC}"
    echo -e "   - POSTGRES_PASSWORD (已自动生成: ${db_password})"
    echo -e "   - SECRET_KEY_BASE (已自动生成)"
    echo -e "   - AWS 相关配置（如果使用生产环境）"
    echo ""
}

# 更新环境变量值
update_env_value() {
    local key=$1
    local value=$2
    local comment=$3
    
    if grep -q "^${key}=" .env 2>/dev/null; then
        # 检查是否需要更新（如果值是空的或者是占位符）
        local current_value=$(grep "^${key}=" .env | cut -d'=' -f2-)
        if [ -z "$current_value" ] || echo "$current_value" | grep -q "your-.*-here\|^$"; then
            # macOS 和 Linux 兼容的 sed 命令
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|^${key}=.*|${key}=${value}|" .env
            else
                sed -i "s|^${key}=.*|${key}=${value}|" .env
            fi
            echo -e "${GREEN}✅ ${key} 已更新${NC}"
            return 0
        fi
        return 1
    else
        # 如果不存在，追加到文件末尾
        echo "" >> .env
        if [ -n "$comment" ]; then
            echo "# ${comment}" >> .env
        fi
        echo "${key}=${value}" >> .env
        echo -e "${GREEN}✅ ${key} 已添加${NC}"
        return 0
    fi
}

# 检查并更新环境变量
check_and_update_env() {
    # 检查 .env 文件是否存在
    if [ ! -f .env ]; then
        echo -e "${BLUE}📝 首次运行，初始化 .env 文件...${NC}"
        init_env_file
        return
    fi
    
    local updated=false
    
    # 检查 SECRET_KEY_BASE 是否存在或是否为空
    if ! grep -q "^SECRET_KEY_BASE=" .env 2>/dev/null || grep -qE "^SECRET_KEY_BASE=$\|^SECRET_KEY_BASE=your-secret-key-base-here" .env 2>/dev/null; then
        local secret_key=$(generate_secret_key)
        echo -e "${BLUE}🔑 自动生成 SECRET_KEY_BASE...${NC}"
        update_env_value "SECRET_KEY_BASE" "$secret_key" "Secret Key (自动生成)"
        updated=true
    fi
    
    # 检查并生成数据库密码（只检查是否是默认值 "postgres" 或空值）
    local current_db_pass=$(grep "^POSTGRES_PASSWORD=" .env 2>/dev/null | cut -d'=' -f2- || echo "")
    if [ -z "$current_db_pass" ] || [ "$current_db_pass" = "postgres" ]; then
        # 生成只包含字母和数字的密码（URL 安全，避免特殊字符问题）
        local db_password=$(openssl rand -hex 32 | tr -d '\n' | cut -c1-32 2>/dev/null || echo "postgres_$(openssl rand -hex 8 2>/dev/null || date +%s)")
        echo -e "${BLUE}🔑 自动生成数据库密码...${NC}"
        update_env_value "POSTGRES_PASSWORD" "$db_password" "Database Password (自动生成)"
        updated=true
    fi
    
    if [ "$updated" = true ]; then
        echo ""
    fi
}

# 初始化环境变量（仅在需要时执行，不强制在每次运行都执行）
# 只有 start、build 或 migrate 命令才需要检查和初始化
check_env_needed() {
    case "${1:-start}" in
        start|build|migrate)
            check_and_update_env
            ;;
    esac
}

# 在执行命令前检查环境变量
check_env_needed "${1:-start}"

# 选择操作
case "${1:-start}" in
  start)
    echo -e "${GREEN}📦 构建 Docker 镜像...${NC}"
    docker-compose build
    
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ 镜像构建失败${NC}"
      exit 1
    fi
    
    echo -e "${GREEN}🚀 启动所有服务...${NC}"
    docker-compose up -d
    
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ 服务启动失败${NC}"
      exit 1
    fi
    
    echo -e "${BLUE}⏳ 等待数据库就绪...${NC}"
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
      if docker-compose exec -T db pg_isready -U ${POSTGRES_USER:-postgres} > /dev/null 2>&1; then
        echo -e "${GREEN}✅ 数据库已就绪${NC}"
        break
      fi
      attempt=$((attempt + 1))
      echo -n "."
      sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
      echo -e "${RED}❌ 数据库启动超时${NC}"
      exit 1
    fi
    
    echo ""
    echo -e "${BLUE}⏳ 等待应用容器就绪...${NC}"
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
      if docker-compose ps web | grep -q "Up"; then
        echo -e "${GREEN}✅ 应用容器已启动${NC}"
        break
      fi
      attempt=$((attempt + 1))
      echo -n "."
      sleep 2
    done
    
    echo ""
    echo -e "${BLUE}⏳ 等待应用启动（迁移会自动运行）...${NC}"
    sleep 10
    
    # 等待应用完全启动后再运行种子数据
    echo ""
    echo -e "${GREEN}🌱 运行数据库种子数据...${NC}"
    echo -e "${YELLOW}提示: 可以通过环境变量 ADMIN_PASSWORD 设置管理员密码${NC}"
    echo -e "${BLUE}   等待应用就绪...${NC}"
    max_attempts=20
    attempt=0
    app_ready=false
    
    while [ $attempt -lt $max_attempts ]; do
      if docker-compose exec -T web ./bin/dobby eval "Application.ensure_all_started(:dobby)" > /dev/null 2>&1; then
        app_ready=true
        break
      fi
      attempt=$((attempt + 1))
      sleep 3
    done
    
    if [ "$app_ready" = true ]; then
      echo -e "${GREEN}   ✅ 应用已就绪${NC}"
      echo ""
      
      if [ -n "$ADMIN_PASSWORD" ]; then
        docker-compose exec -T -e ADMIN_PASSWORD="$ADMIN_PASSWORD" web ./bin/dobby eval "Dobby.Release.seed()" 2>&1 || echo -e "${YELLOW}   ⚠️  种子数据可能已存在${NC}"
      else
        docker-compose exec -T web ./bin/dobby eval "Dobby.Release.seed()" 2>&1 || echo -e "${YELLOW}   ⚠️  种子数据可能已存在${NC}"
      fi
    else
      echo ""
      echo -e "${YELLOW}⚠️  应用启动较慢，种子数据将在后台运行${NC}"
      echo -e "${YELLOW}   可以稍后手动运行: ./docker-start.sh seed${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ 部署完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}📋 服务状态：${NC}"
    docker-compose ps
    echo ""
    echo -e "${BLUE}🌐 访问地址：${NC}"
    echo -e "   Web 应用: ${GREEN}http://localhost:${PORT:-4000}${NC}"
    echo ""
    echo -e "${BLUE}👤 管理员账号：${NC}"
    echo -e "   邮箱: ${GREEN}admin@dobby.com${NC}"
    echo -e "   密码: ${GREEN}Admin123!${NC}"
    echo -e "   ${YELLOW}⚠️  请在生产环境中修改默认密码！${NC}"
    echo ""
    echo -e "${BLUE}📋 常用命令：${NC}"
    echo -e "   查看日志: ${GREEN}./docker-start.sh logs${NC}"
    echo -e "   停止服务: ${GREEN}./docker-start.sh stop${NC}"
    echo -e "   运行种子数据: ${GREEN}./docker-start.sh seed${NC}"
    echo ""
    echo -e "${BLUE}📋 查看实时日志：${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出日志查看${NC}"
    echo ""
    docker-compose logs -f web
    ;;
    
  stop)
    echo -e "${YELLOW}⏹️  停止服务...${NC}"
    docker-compose down
    ;;
    
  restart)
    echo -e "${YELLOW}🔄 重启服务...${NC}"
    docker-compose restart
    ;;
    
  logs)
    echo -e "${GREEN}📋 查看日志...${NC}"
    docker-compose logs -f "${2:-web}"
    ;;
    
  build)
    echo -e "${GREEN}📦 构建 Docker 镜像...${NC}"
    docker-compose build --no-cache
    ;;
    
  clean)
    echo -e "${RED}🗑️  清理所有容器和数据卷...${NC}"
    read -p "这将删除所有数据！确认继续? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      docker-compose down -v
      echo -e "${GREEN}✅ 清理完成${NC}"
    else
      echo "已取消"
    fi
    ;;
    
  migrate)
    echo -e "${GREEN}🔄 运行数据库迁移...${NC}"
    docker-compose exec web ./bin/dobby eval "Dobby.Release.migrate()"
    ;;
    
  seed)
    echo -e "${GREEN}🌱 运行数据库种子数据...${NC}"
    echo -e "${YELLOW}提示: 可以通过环境变量 ADMIN_PASSWORD 设置管理员密码${NC}"
    if [ -n "$ADMIN_PASSWORD" ]; then
      docker-compose exec -e ADMIN_PASSWORD="$ADMIN_PASSWORD" web ./bin/dobby eval "Dobby.Release.seed()"
    else
      docker-compose exec web ./bin/dobby eval "Dobby.Release.seed()"
    fi
    ;;
    
  shell)
    echo -e "${GREEN}🐚 进入容器...${NC}"
    docker-compose exec web sh
    ;;
    
  env)
    echo -e "${GREEN}📋 当前环境变量配置：${NC}"
    if [ -f .env ]; then
        # 显示环境变量，但隐藏敏感信息
        grep -v "^#" .env | grep -v "^$" | sed 's/\(SECRET_KEY_BASE\|POSTGRES_PASSWORD\|AWS_SECRET_ACCESS_KEY\)=.*/\1=***隐藏***/'
    else
        echo -e "${YELLOW}未找到 .env 文件${NC}"
    fi
    ;;
    
  *)
    echo "用法: $0 {start|stop|restart|logs|build|clean|migrate|seed|shell|env}"
    echo ""
    echo "命令:"
    echo "  start    - 一键部署：构建镜像、启动服务、运行迁移和种子数据 (默认)"
    echo "  stop     - 停止所有服务"
    echo "  restart  - 重启所有服务"
    echo "  logs     - 查看日志 (可以指定服务名，如: logs db)"
    echo "  build    - 重新构建镜像"
    echo "  clean    - 停止服务并删除数据卷"
    echo "  migrate  - 运行数据库迁移"
    echo "  seed     - 运行数据库种子数据（创建默认管理员和奖品模板）"
    echo "  shell    - 进入应用容器"
    echo "  env      - 显示当前环境变量配置（敏感信息已隐藏）"
    exit 1
    ;;
esac

