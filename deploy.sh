#!/bin/bash

# MongoDB 集群 Git 仓库一键部署脚本
# 支持直接从git仓库克隆后快速部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 生成随机密码
generate_password() {
    local length=${1:-20}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# 创建环境配置文件
create_env_file() {
    log_info "创建环境配置文件..."
    
    if [ -f ".env" ]; then
        log_warning ".env 文件已存在，是否覆盖？[y/N]"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "跳过 .env 文件创建"
            return 0
        fi
    fi
    
    # 复制模板文件
    cp env.template .env
    
    # 生成随机密码
    local root_password=$(generate_password 24)
    local app_password=$(generate_password 20)
    local readonly_password=$(generate_password 16)
    
    # 替换密码
    sed -i "s/CHANGE_THIS_SUPER_SECURE_PASSWORD_2024/${root_password}/g" .env
    sed -i "s/CHANGE_THIS_APP_PASSWORD_2024/${app_password}/g" .env
    sed -i "s/CHANGE_THIS_READONLY_PASSWORD_2024/${readonly_password}/g" .env
    
    log_success "环境配置文件创建完成"
    log_warning "请妥善保存以下密码信息："
    echo -e "${YELLOW}管理员密码: ${root_password}${NC}"
    echo -e "${YELLOW}应用密码: ${app_password}${NC}"
    echo -e "${YELLOW}只读密码: ${readonly_password}${NC}"
}

# 创建必要目录
create_directories() {
    log_info "创建必要的目录结构..."
    
    mkdir -p data/primary data/secondary1 data/secondary2
    mkdir -p logs/primary logs/secondary1 logs/secondary2 logs/backup logs/monitor
    mkdir -p backups
    
    # 设置权限
    chmod 755 data logs backups
    chmod -R 755 data/* logs/*
    
    log_success "目录结构创建完成"
}

# 检查端口占用
check_ports() {
    log_info "检查端口占用情况..."
    
    local ports=(27017 27018 27019)
    local occupied_ports=()
    
    for port in "${ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            occupied_ports+=($port)
        fi
    done
    
    if [ ${#occupied_ports[@]} -ne 0 ]; then
        log_error "以下端口已被占用: ${occupied_ports[*]}"
        log_error "请确保端口 27017-27019 可用"
        exit 1
    fi
    
    log_success "端口检查通过"
}

# 启动服务
start_services() {
    log_info "启动 MongoDB 集群服务..."
    
    # 启动服务
    docker-compose up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    if docker-compose ps | grep -q "Up"; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败"
        docker-compose logs
        exit 1
    fi
}

# 初始化副本集
init_replica_set() {
    log_info "初始化 MongoDB 副本集..."
    
    # 等待MongoDB服务完全启动
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "尝试连接 MongoDB... (${attempt}/${max_attempts})"
        
        if docker exec mongo-primary mongo --eval "db.adminCommand('ping')" &>/dev/null; then
            log_success "MongoDB 连接成功"
            break
        fi
        
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "MongoDB 连接超时"
        exit 1
    fi
    
    # 执行副本集初始化脚本
    if [ -f "scripts/init-replica-set.sh" ]; then
        chmod +x scripts/init-replica-set.sh
        ./scripts/init-replica-set.sh
    else
        log_error "初始化脚本不存在"
        exit 1
    fi
}

# 运行健康检查
run_health_check() {
    log_info "运行健康检查..."
    
    if [ -f "scripts/health-check.sh" ]; then
        chmod +x scripts/health-check.sh
        ./scripts/health-check.sh
    else
        log_warning "健康检查脚本不存在，跳过"
    fi
}

# 显示部署信息
show_deployment_info() {
    log_success "MongoDB 集群部署完成！"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}         部署信息                        ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}主节点连接:${NC} localhost:27017"
    echo -e "${BLUE}副本节点1:${NC} localhost:27018"
    echo -e "${BLUE}副本节点2:${NC} localhost:27019"
    echo ""
    echo -e "${BLUE}管理命令:${NC}"
    echo -e "  查看服务状态: ${YELLOW}docker-compose ps${NC}"
    echo -e "  查看日志:     ${YELLOW}docker-compose logs -f${NC}"
    echo -e "  停止服务:     ${YELLOW}docker-compose down${NC}"
    echo -e "  健康检查:     ${YELLOW}./scripts/health-check.sh${NC}"
    echo ""
    echo -e "${RED}注意: 请保存好密码信息，初次连接需要使用管理员账户${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}"
    echo "======================================"
    echo "    MongoDB 集群 Git 部署脚本        "
    echo "======================================"
    echo -e "${NC}"
    
    # 检查是否在正确的目录
    if [ ! -f "docker-compose.yml" ]; then
        log_error "请在 mongodb-cluster 目录下运行此脚本"
        exit 1
    fi
    
    # 执行部署步骤
    check_dependencies
    create_env_file
    create_directories
    check_ports
    start_services
    init_replica_set
    run_health_check
    show_deployment_info
}

# 处理脚本参数
case "${1:-}" in
    --help|-h)
        echo "MongoDB 集群 Git 部署脚本"
        echo ""
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h     显示帮助信息"
        echo "  --env-only     仅创建环境配置文件"
        echo "  --no-init      不初始化副本集"
        echo ""
        exit 0
        ;;
    --env-only)
        create_env_file
        exit 0
        ;;
    --no-init)
        main
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "未知参数: $1"
        echo "使用 --help 查看帮助信息"
        exit 1
        ;;
esac 