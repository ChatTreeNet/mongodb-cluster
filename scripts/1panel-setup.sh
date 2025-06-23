#!/bin/bash
# 1Panel 集成设置脚本
# 用于配置MongoDB集群与1Panel的集成

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
CURRENT_DIR=$(pwd)
ONEPANEL_APPS_DIR="/opt/1panel/apps"
ONEPANEL_BACKUP_DIR="/opt/1panel/backup/mongodb"
ONEPANEL_SCRIPTS_DIR="/opt/1panel/scripts"
PROJECT_NAME="mongodb-cluster"

# 日志函数
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}$1${NC}"
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}❌ ERROR: $1${NC}"
}

log_warning() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}⚠️  WARNING: $1${NC}"
}

log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${BLUE}ℹ️  INFO: $1${NC}"
}

# 检查是否以root权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请以root权限运行此脚本"
        exit 1
    fi
}

# 检查1Panel是否已安装
check_1panel() {
    log_info "检查1Panel安装状态..."
    
    if ! command -v 1pctl >/dev/null 2>&1; then
        log_error "1Panel未安装，请先安装1Panel"
        echo ""
        echo "安装命令："
        echo "curl -sSL https://resource.1panel.cn/quick_start.sh | bash"
        exit 1
    fi
    
    if ! systemctl is-active --quiet 1panel; then
        log_error "1Panel服务未运行"
        echo "启动命令: systemctl start 1panel"
        exit 1
    fi
    
    log "1Panel运行正常 ✅"
}

# 创建1Panel项目目录
setup_1panel_project() {
    log_info "设置1Panel项目目录..."
    
    # 创建项目目录
    local project_dir="${ONEPANEL_APPS_DIR}/${PROJECT_NAME}"
    mkdir -p "$project_dir"
    
    # 复制项目文件
    log_info "复制项目文件到1Panel目录..."
    cp -r "$CURRENT_DIR"/* "$project_dir/"
    
    # 设置正确的权限
    chown -R 1panel:1panel "$project_dir"
    chmod -R 755 "$project_dir"
    
    log "项目目录创建完成: $project_dir ✅"
    
    # 输出1Panel导入指令
    echo ""
    log "📋 请在1Panel面板中执行以下操作："
    echo "1. 登录1Panel面板 (默认端口: 10086)"
    echo "2. 容器 → 编排 → 创建编排"
    echo "3. 项目名称: ${PROJECT_NAME}"
    echo "4. 工作目录: ${project_dir}"
    echo "5. 编排文件: docker-compose.yml"
}

# 创建备份目录和权限
setup_backup_directory() {
    log_info "设置1Panel备份目录..."
    
    # 创建备份目录
    mkdir -p "$ONEPANEL_BACKUP_DIR"
    chown -R 1panel:1panel "$ONEPANEL_BACKUP_DIR"
    chmod 755 "$ONEPANEL_BACKUP_DIR"
    
    # 创建备份日志目录
    mkdir -p "$ONEPANEL_BACKUP_DIR/logs"
    
    log "备份目录创建完成: $ONEPANEL_BACKUP_DIR ✅"
}

# 创建1Panel脚本
create_1panel_scripts() {
    log_info "创建1Panel集成脚本..."
    
    # 创建脚本目录
    mkdir -p "$ONEPANEL_SCRIPTS_DIR"
    
    # 创建MongoDB备份脚本
    cat > "$ONEPANEL_SCRIPTS_DIR/mongodb-backup.sh" << 'EOF'
#!/bin/bash
# 1Panel MongoDB备份脚本

# 配置变量
PROJECT_DIR="/opt/1panel/apps/mongodb-cluster"
BACKUP_DIR="/opt/1panel/backup/mongodb"
LOG_FILE="$BACKUP_DIR/logs/1panel-backup.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 开始1Panel MongoDB备份任务"

# 确保备份目录存在
mkdir -p "$BACKUP_DIR/logs"

# 执行容器内备份
cd "$PROJECT_DIR"
if docker-compose exec -T mongo-backup /scripts/backup.sh; then
    log "✅ 容器内备份完成"
else
    log "❌ 容器内备份失败"
    exit 1
fi

# 同步到1Panel备份目录
if [ -d "$PROJECT_DIR/backups" ]; then
    # 查找最新的备份文件
    LATEST_BACKUP=$(find "$PROJECT_DIR/backups" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [ -n "$LATEST_BACKUP" ]; then
        # 复制到1Panel备份目录
        cp "$LATEST_BACKUP" "$BACKUP_DIR/"
        BACKUP_NAME=$(basename "$LATEST_BACKUP")
        log "✅ 备份文件已同步到1Panel: $BACKUP_NAME"
        
        # 记录备份信息
        echo "$(date '+%Y-%m-%d %H:%M:%S') $BACKUP_NAME" >> "$BACKUP_DIR/backup_history.log"
        
        # 清理超过30天的1Panel备份
        find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete 2>/dev/null || true
        log "🧹 已清理30天前的旧备份"
        
    else
        log "⚠️ 未找到最新备份文件"
    fi
else
    log "❌ 备份目录不存在: $PROJECT_DIR/backups"
    exit 1
fi

log "🎉 1Panel MongoDB备份任务完成"
EOF

    # 创建MongoDB监控脚本
    cat > "$ONEPANEL_SCRIPTS_DIR/mongodb-monitor.sh" << 'EOF'
#!/bin/bash
# 1Panel MongoDB监控脚本

PROJECT_DIR="/opt/1panel/apps/mongodb-cluster"
LOG_FILE="/opt/1panel/backup/mongodb/logs/monitor.log"

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 切换到项目目录
cd "$PROJECT_DIR" || exit 1

# 获取环境变量
source .env

# 获取副本集状态
echo "=== MongoDB 集群监控 $(date) ===" | tee -a "$LOG_FILE"

REPLICA_STATUS=$(docker-compose exec -T mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval "
try {
    var status = rs.status();
    var primary = status.members.find(m => m.state === 1);
    var secondaries = status.members.filter(m => m.state === 2).length;
    var healthy = status.members.filter(m => m.health === 1).length;
    
    print('PRIMARY:' + (primary ? primary.name : 'NONE'));
    print('SECONDARIES:' + secondaries);
    print('HEALTHY_NODES:' + healthy + '/' + status.members.length);
    
    // 检查同步延迟
    var maxLag = 0;
    status.members.forEach(function(member) {
        if (member.state === 2 && member.optimeDate && primary && primary.optimeDate) {
            var lag = (primary.optimeDate - member.optimeDate) / 1000;
            if (lag > maxLag) maxLag = lag;
        }
    });
    print('MAX_LAG_SECONDS:' + Math.round(maxLag));
    
} catch(e) {
    print('ERROR:' + e.message);
}
" 2>/dev/null)

echo "$REPLICA_STATUS" | tee -a "$LOG_FILE"

# 获取连接数和性能指标
PERFORMANCE=$(docker-compose exec -T mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval "
var status = db.serverStatus();
print('CONNECTIONS:' + status.connections.current + '/' + status.connections.available);
print('MEMORY_MB:' + Math.round(status.mem.resident));
print('OPERATIONS_PER_SEC:' + (status.opcounters.query + status.opcounters.insert + status.opcounters.update + status.opcounters.delete));
" 2>/dev/null)

echo "$PERFORMANCE" | tee -a "$LOG_FILE"

# 检查备份状态
LATEST_BACKUP=$(find backups/ -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1)
if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_TIME=$(echo "$LATEST_BACKUP" | cut -d' ' -f1)
    BACKUP_FILE=$(echo "$LATEST_BACKUP" | cut -d' ' -f2-)
    AGE_HOURS=$(( ($(date +%s) - ${BACKUP_TIME%.*}) / 3600 ))
    echo "LATEST_BACKUP:$(basename "$BACKUP_FILE") (${AGE_HOURS}h ago)" | tee -a "$LOG_FILE"
else
    echo "LATEST_BACKUP:NONE" | tee -a "$LOG_FILE"
fi

echo "=== 监控完成 ===" | tee -a "$LOG_FILE"
EOF

    # 设置脚本权限
    chmod +x "$ONEPANEL_SCRIPTS_DIR/mongodb-backup.sh"
    chmod +x "$ONEPANEL_SCRIPTS_DIR/mongodb-monitor.sh"
    chown 1panel:1panel "$ONEPANEL_SCRIPTS_DIR"/*.sh
    
    log "1Panel脚本创建完成 ✅"
}

# 显示1Panel配置指南
show_1panel_guide() {
    echo ""
    log "📋 1Panel配置指南"
    echo ""
    echo "${YELLOW}=== 步骤1: 导入项目到1Panel ===${NC}"
    echo "1. 访问1Panel面板: https://your-server-ip:10086"
    echo "2. 容器 → 编排 → 创建编排"
    echo "3. 配置信息："
    echo "   - 项目名称: ${PROJECT_NAME}"
    echo "   - 工作目录: ${ONEPANEL_APPS_DIR}/${PROJECT_NAME}"
    echo "   - 编排文件: docker-compose.yml"
    echo ""
    echo "${YELLOW}=== 步骤2: 配置自动备份 ===${NC}"
    echo "1. 系统设置 → 计划任务 → 添加"
    echo "2. 配置信息："
    echo "   - 任务名称: MongoDB自动备份"
    echo "   - 任务类型: Shell脚本"
    echo "   - 执行周期: 自定义 (0 9 * * *)"
    echo "   - 执行脚本: ${ONEPANEL_SCRIPTS_DIR}/mongodb-backup.sh"
    echo ""
    echo "${YELLOW}=== 步骤3: 配置监控任务 ===${NC}"
    echo "1. 系统设置 → 计划任务 → 添加"
    echo "2. 配置信息："
    echo "   - 任务名称: MongoDB状态监控"
    echo "   - 任务类型: Shell脚本"
    echo "   - 执行周期: 每5分钟"
    echo "   - 执行脚本: ${ONEPANEL_SCRIPTS_DIR}/mongodb-monitor.sh"
    echo ""
    echo "${YELLOW}=== 步骤4: 配置备份存储 ===${NC}"
    echo "1. 系统设置 → 备份账号 → 添加"
    echo "2. 选择存储类型（本地存储或云存储）"
    echo "3. 配置备份路径: ${ONEPANEL_BACKUP_DIR}"
    echo ""
    echo "${GREEN}✅ 1Panel集成配置完成！${NC}"
    echo ""
    echo "${BLUE}📂 相关文件路径：${NC}"
    echo "- 项目目录: ${ONEPANEL_APPS_DIR}/${PROJECT_NAME}"
    echo "- 备份目录: ${ONEPANEL_BACKUP_DIR}"
    echo "- 脚本目录: ${ONEPANEL_SCRIPTS_DIR}"
    echo "- 备份脚本: ${ONEPANEL_SCRIPTS_DIR}/mongodb-backup.sh"
    echo "- 监控脚本: ${ONEPANEL_SCRIPTS_DIR}/mongodb-monitor.sh"
}

# 验证配置
verify_setup() {
    log_info "验证1Panel集成配置..."
    
    local errors=0
    
    # 检查项目目录
    if [ ! -d "${ONEPANEL_APPS_DIR}/${PROJECT_NAME}" ]; then
        log_error "项目目录不存在"
        ((errors++))
    fi
    
    # 检查备份目录
    if [ ! -d "$ONEPANEL_BACKUP_DIR" ]; then
        log_error "备份目录不存在"
        ((errors++))
    fi
    
    # 检查脚本文件
    if [ ! -f "${ONEPANEL_SCRIPTS_DIR}/mongodb-backup.sh" ]; then
        log_error "备份脚本不存在"
        ((errors++))
    fi
    
    if [ ! -f "${ONEPANEL_SCRIPTS_DIR}/mongodb-monitor.sh" ]; then
        log_error "监控脚本不存在"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        log "所有配置验证通过 ✅"
    else
        log_error "发现 $errors 个配置问题"
        exit 1
    fi
}

# 测试备份功能
test_backup() {
    log_info "测试备份功能..."
    
    if [ -f "${ONEPANEL_SCRIPTS_DIR}/mongodb-backup.sh" ]; then
        log_info "执行测试备份..."
        if bash "${ONEPANEL_SCRIPTS_DIR}/mongodb-backup.sh"; then
            log "备份测试成功 ✅"
        else
            log_warning "备份测试失败，请检查MongoDB容器状态"
        fi
    else
        log_warning "备份脚本不存在，跳过测试"
    fi
}

# 主函数
main() {
    echo ""
    log "🚀 开始配置MongoDB集群与1Panel集成"
    echo ""
    
    # 检查前置条件
    check_root
    check_1panel
    
    # 执行配置
    setup_1panel_project
    setup_backup_directory
    create_1panel_scripts
    
    # 验证配置
    verify_setup
    
    # 显示配置指南
    show_1panel_guide
    
    # 询问是否测试备份
    echo ""
    read -p "是否立即测试备份功能？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_backup
    fi
    
    echo ""
    log "🎉 1Panel集成配置完成！请按照上述指南在1Panel面板中完成最终配置。"
}

# 显示帮助信息
show_help() {
    echo "1Panel集成设置脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示帮助信息"
    echo "  -t, --test     仅测试备份功能"
    echo "  -v, --verify   仅验证配置"
    echo ""
    echo "示例:"
    echo "  $0              # 完整配置"
    echo "  $0 --test       # 测试备份"
    echo "  $0 --verify     # 验证配置"
}

# 解析命令行参数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -t|--test)
        check_root
        check_1panel
        test_backup
        exit 0
        ;;
    -v|--verify)
        check_root
        verify_setup
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "未知选项: $1"
        show_help
        exit 1
        ;;
esac 