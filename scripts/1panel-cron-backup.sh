#!/bin/bash

# MongoDB 备份脚本 - 1Panel 计划任务专用版本
# 此脚本专门设计用于1Panel的计划任务功能

# 设置基本变量
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"

# 日志配置
LOG_DIR="$PROJECT_DIR/logs"
CRON_LOG_FILE="$LOG_DIR/cron-backup.log"
mkdir -p "$LOG_DIR"

# 日志函数
log_cron() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [1PANEL-CRON] $1" | tee -a "$CRON_LOG_FILE"
}

# 检查环境
check_environment() {
    log_cron "开始检查执行环境..."
    
    # 检查项目目录
    if [ ! -d "$PROJECT_DIR" ]; then
        log_cron "错误: 项目目录不存在: $PROJECT_DIR"
        exit 1
    fi
    
    # 检查环境配置文件
    if [ ! -f "$ENV_FILE" ]; then
        log_cron "错误: 环境配置文件不存在: $ENV_FILE"
        exit 1
    fi
    
    # 检查备份脚本
    if [ ! -f "$BACKUP_SCRIPT" ]; then
        log_cron "错误: 备份脚本不存在: $BACKUP_SCRIPT"
        exit 1
    fi
    
    # 检查Docker服务
    if ! docker ps >/dev/null 2>&1; then
        log_cron "错误: Docker 服务不可用"
        exit 1
    fi
    
    # 检查MongoDB容器
    if ! docker ps --filter "name=mongo-primary" --format "table {{.Names}}" | grep -q "mongo-primary"; then
        log_cron "错误: MongoDB 主节点容器未运行"
        exit 1
    fi
    
    log_cron "环境检查通过"
}

# 加载环境变量
load_environment() {
    log_cron "加载环境配置..."
    
    # 加载 .env 文件
    if [ -f "$ENV_FILE" ]; then
        # 导出所有环境变量，忽略注释和空行
        set -a
        source "$ENV_FILE"
        set +a
        log_cron "环境变量加载完成"
    else
        log_cron "警告: 未找到 .env 文件，使用默认配置"
    fi
}

# 检查备份配置
check_backup_config() {
    log_cron "检查备份配置..."
    
    # 检查基本配置
    if [ -z "$MONGO_ROOT_PASSWORD" ]; then
        log_cron "警告: MONGO_ROOT_PASSWORD 未配置"
    fi
    
    # 显示备份配置摘要
    log_cron "备份配置摘要:"
    log_cron "  - 本地备份: 启用"
    log_cron "  - 压缩备份: ${BACKUP_COMPRESS:-true}"
    log_cron "  - 保留天数: ${BACKUP_RETENTION_DAYS:-30}"
    log_cron "  - 1Panel集成: ${ONEPANEL_BACKUP_ENABLED:-false}"
    log_cron "  - 存储桶备份: ${ENABLE_BUCKET_BACKUP:-false}"
    
    if [ "${ENABLE_BUCKET_BACKUP:-false}" = "true" ]; then
        log_cron "  - 存储桶类型: ${BUCKET_TYPE:-s3}"
        log_cron "  - 存储桶名称: ${BUCKET_NAME:-未配置}"
    fi
}

# 执行备份
execute_backup() {
    log_cron "开始执行备份任务..."
    
    # 切换到项目目录
    cd "$PROJECT_DIR"
    
    # 执行备份脚本
    if bash "$BACKUP_SCRIPT" >> "$CRON_LOG_FILE" 2>&1; then
        log_cron "备份任务执行成功"
        
        # 记录备份成功到1Panel日志
        echo "$(date '+%Y-%m-%d %H:%M:%S') - MongoDB备份成功" >> /opt/1panel/data/logs/cron.log 2>/dev/null || true
        
        return 0
    else
        log_cron "备份任务执行失败"
        
        # 记录备份失败到1Panel日志
        echo "$(date '+%Y-%m-%d %H:%M:%S') - MongoDB备份失败" >> /opt/1panel/data/logs/cron.log 2>/dev/null || true
        
        return 1
    fi
}

# 发送通知（集成1Panel通知）
send_notification() {
    local status=$1
    local message=$2
    
    log_cron "发送通知: $status - $message"
    
    # 尝试使用1Panel的通知功能
    if [ -f "/opt/1panel/scripts/notify.sh" ]; then
        /opt/1panel/scripts/notify.sh "MongoDB备份" "$status" "$message" 2>/dev/null || true
    fi
    
    # 如果配置了自定义通知
    if [ -n "${ALERT_WEBHOOK:-}" ]; then
        curl -X POST "${ALERT_WEBHOOK}" \
             -H "Content-Type: application/json" \
             -d "{\"title\":\"MongoDB备份通知\",\"text\":\"$status: $message\"}" \
             2>/dev/null || true
    fi
}

# 清理日志文件
cleanup_logs() {
    # 清理超过30天的cron日志
    find "$LOG_DIR" -name "cron-backup.log.*" -mtime +30 -delete 2>/dev/null || true
    
    # 轮转当前日志文件（如果大于10MB）
    if [ -f "$CRON_LOG_FILE" ] && [ $(stat -c%s "$CRON_LOG_FILE") -gt 10485760 ]; then
        mv "$CRON_LOG_FILE" "${CRON_LOG_FILE}.$(date +%Y%m%d_%H%M%S)"
        touch "$CRON_LOG_FILE"
        log_cron "日志文件已轮转"
    fi
}

# 显示使用帮助
show_help() {
    cat << EOF
MongoDB 备份脚本 - 1Panel 计划任务版本

用法: $0 [选项]

选项:
  --help, -h       显示此帮助信息
  --check          仅检查环境和配置
  --test           测试模式（不执行实际备份）
  --force          强制执行备份（忽略环境检查）
  --status         显示备份状态信息

示例:
  $0                 # 执行正常备份
  $0 --check         # 检查环境和配置
  $0 --test          # 测试运行

此脚本专为1Panel计划任务设计，具有以下特性:
- 完整的环境检查
- 详细的日志记录
- 1Panel通知集成
- 自动日志轮转
- 错误处理和恢复
EOF
}

# 显示状态信息
show_status() {
    log_cron "=== MongoDB 备份状态 ==="
    
    # 显示容器状态
    log_cron "MongoDB 容器状态:"
    docker ps --filter "name=mongo-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | while read line; do
        log_cron "  $line"
    done
    
    # 显示最近备份
    log_cron "最近备份记录:"
    if [ -f "$PROJECT_DIR/backups/backup_summary.json" ]; then
        tail -3 "$PROJECT_DIR/backups/backup_summary.json" | while read line; do
            log_cron "  $line"
        done
    else
        log_cron "  未找到备份记录"
    fi
    
    # 显示磁盘使用情况
    log_cron "备份目录磁盘使用:"
    if [ -d "$PROJECT_DIR/backups" ]; then
        du -sh "$PROJECT_DIR/backups" | while read line; do
            log_cron "  $line"
        done
    fi
}

# 主函数
main() {
    local start_time=$(date +%s)
    
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --check)
            check_environment
            load_environment
            check_backup_config
            log_cron "环境检查完成"
            exit 0
            ;;
        --test)
            log_cron "=== 测试模式 ==="
            check_environment
            load_environment
            check_backup_config
            log_cron "测试模式完成，实际备份未执行"
            exit 0
            ;;
        --status)
            show_status
            exit 0
            ;;
        --force)
            log_cron "=== 强制模式 ==="
            ;;
        "")
            # 正常执行模式
            ;;
        *)
            log_cron "错误: 未知参数 $1"
            show_help
            exit 1
            ;;
    esac
    
    # 记录开始
    log_cron "=== 开始 1Panel 计划任务备份 ==="
    log_cron "执行时间: $(date)"
    log_cron "项目目录: $PROJECT_DIR"
    
    # 执行步骤
    if [ "${1:-}" != "--force" ]; then
        check_environment
    fi
    
    load_environment
    check_backup_config
    cleanup_logs
    
    # 执行备份
    if execute_backup; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_cron "=== 备份任务完成 ==="
        log_cron "总耗时: ${duration}秒"
        
        send_notification "成功" "MongoDB备份完成，耗时${duration}秒"
        exit 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_cron "=== 备份任务失败 ==="
        log_cron "总耗时: ${duration}秒"
        
        send_notification "失败" "MongoDB备份失败，请检查日志"
        exit 1
    fi
}

# 错误处理
trap 'log_cron "脚本异常退出"; send_notification "异常" "备份脚本异常退出"; exit 1' ERR

# 执行主函数
main "$@" 