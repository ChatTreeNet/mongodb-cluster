#!/bin/bash
# MongoDB 自动备份脚本
# 支持1Panel集成和多种存储方式

set -e

# 从环境变量获取配置
MONGO_ROOT_USER=${MONGO_ROOT_USER:-admin}
MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD:-password}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
BACKUP_COMPRESS=${BACKUP_COMPRESS:-true}
ONEPANEL_BACKUP_ENABLED=${ONEPANEL_BACKUP_ENABLED:-false}
ONEPANEL_BACKUP_PATH=${ONEPANEL_BACKUP_PATH:-/opt/1panel/backup/mongodb}

# 存储桶备份配置
ENABLE_BUCKET_BACKUP=${ENABLE_BUCKET_BACKUP:-false}
BUCKET_TYPE=${BUCKET_TYPE:-s3}
BUCKET_NAME=${BUCKET_NAME:-mongodb-backups}
BUCKET_REGION=${BUCKET_REGION:-us-east-1}
BUCKET_ENDPOINT=${BUCKET_ENDPOINT:-}
BUCKET_ACCESS_KEY=${BUCKET_ACCESS_KEY:-}
BUCKET_SECRET_KEY=${BUCKET_SECRET_KEY:-}
BUCKET_PATH_PREFIX=${BUCKET_PATH_PREFIX:-mongodb-cluster}
BUCKET_USE_SSL=${BUCKET_USE_SSL:-true}
BUCKET_FORCE_PATH_STYLE=${BUCKET_FORCE_PATH_STYLE:-false}

# 项目根目录
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 备份配置
BACKUP_BASE_DIR="${PROJECT_ROOT}/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${DATE}"
LOG_FILE="${BACKUP_BASE_DIR}/backup.log"
SUMMARY_FILE="${BACKUP_BASE_DIR}/backup_summary.json"

# 创建备份目录
mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  INFO: $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ SUCCESS: $1" | tee -a "$LOG_FILE"
}

# 检查副本集状态
check_replica_status() {
    log_info "检查副本集状态..."
    
    # 检查哪个节点是主节点
    for host in mongo-primary mongo-secondary1 mongo-secondary2; do
        if docker exec mongo-primary mongo --host "$host:27017" --username "$MONGO_ROOT_USER" --password "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval "
            try {
                var status = rs.status();
                var isSecondary = db.isMaster().secondary;
                if (isSecondary) {
                    print('SECONDARY');
                } else {
                    print('PRIMARY_OR_OTHER');
                }
            } catch(e) {
                print('ERROR');
            }
        " 2>/dev/null | grep -q "SECONDARY"; then
            echo "$host"
            return 0
        fi
    done
    
    # 如果没有找到副本节点，使用主节点
    echo "mongo-primary"
}

# 获取数据库列表
get_databases() {
    local host=$1
    docker exec mongo-primary mongo --host "$host:27017" --username "$MONGO_ROOT_USER" --password "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval "
        db.adminCommand('listDatabases').databases.forEach(function(db) {
            if (db.name !== 'admin' && db.name !== 'local' && db.name !== 'config') {
                print(db.name);
            }
        });
    " 2>/dev/null
}

# 执行备份
perform_backup() {
    local backup_host=$1
    local backup_start_time=$(date +%s)
    
    log_info "从 $backup_host 执行备份..."
    log_info "备份目录: $BACKUP_DIR"
    log_info "备份配置:"
    log_info "  - 压缩: $BACKUP_COMPRESS"
    log_info "  - 保留天数: $BACKUP_RETENTION_DAYS"
    log_info "  - 1Panel集成: $ONEPANEL_BACKUP_ENABLED"
    
    # 执行mongodump
    log_info "开始数据库转储 (docker exec $backup_host)..."

    # 在对应容器内执行 mongodump，将数据直接输出到容器中的 /backup 目录，
    # 该目录已经通过 docker-compose.yml 挂载到宿主机的 ${BACKUP_BASE_DIR}。
    if docker exec "$backup_host" mongodump \
        --host "$backup_host:27017" \
        --username "$MONGO_ROOT_USER" \
        --password "$MONGO_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --out "/backup/$DATE" \
        --gzip >> "$LOG_FILE" 2>&1; then
        
        # docker exec 成功后，备份数据已在宿主机 ${BACKUP_DIR}
        local backup_end_time=$(date +%s)
        local backup_duration=$((backup_end_time - backup_start_time))
        
        log_success "数据库转储完成，耗时: ${backup_duration}秒"
        
        # 获取备份大小
        local backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
        log_info "备份大小: $backup_size"
        
        # 获取备份的数据库列表
        local databases=$(get_databases "$backup_host")
        local db_count=$(echo "$databases" | wc -l)
        log_info "备份数据库数量: $db_count"
        
        # 创建备份摘要
        create_backup_summary "$backup_host" "$backup_duration" "$backup_size" "$db_count" "$databases"
        
        return 0
    else
        log_error "数据库转储失败"
        return 1
    fi
}

# 创建备份摘要
create_backup_summary() {
    local host=$1
    local duration=$2
    local size=$3
    local db_count=$4
    local databases=$5
    
    # 转换数据库列表为JSON数组
    local db_array=""
    for db in $databases; do
        if [ -z "$db_array" ]; then
            db_array="\"$db\""
        else
            db_array="$db_array,\"$db\""
        fi
    done
    
    cat > "${BACKUP_DIR}/backup_info.json" <<EOF
{
  "backup_id": "$DATE",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_host": "$host",
  "duration_seconds": $duration,
  "backup_size": "$size",
  "database_count": $db_count,
  "databases": [$db_array],
  "backup_path": "$BACKUP_DIR",
  "compression_enabled": $BACKUP_COMPRESS,
  "mongodb_version": "4.4"
}
EOF
    
    log_info "备份摘要已创建: ${BACKUP_DIR}/backup_info.json"
}

# 压缩备份
compress_backup() {
    if [ "$BACKUP_COMPRESS" = "true" ]; then
        log_info "压缩备份文件..."
        cd "$BACKUP_BASE_DIR"
        
        if tar -czf "${DATE}.tar.gz" "$DATE/" >> "$LOG_FILE" 2>&1; then
            local compressed_size=$(du -sh "${DATE}.tar.gz" | cut -f1)
            log_success "备份压缩完成: ${DATE}.tar.gz (${compressed_size})"
            
            # 删除未压缩的目录
            rm -rf "$DATE"
            log_info "已删除未压缩的备份目录"
            
            return 0
        else
            log_error "备份压缩失败"
            return 1
        fi
    else
        log_info "跳过压缩（压缩功能已禁用）"
        return 0
    fi
}

# 同步到1Panel
sync_to_1panel() {
    if [ "$ONEPANEL_BACKUP_ENABLED" = "true" ]; then
        log_info "同步备份到1Panel..."
        
        # 创建1Panel备份目录
        if mkdir -p "$ONEPANEL_BACKUP_PATH" 2>/dev/null; then
            
            if [ "$BACKUP_COMPRESS" = "true" ]; then
                # 复制压缩文件
                if cp "${BACKUP_BASE_DIR}/${DATE}.tar.gz" "$ONEPANEL_BACKUP_PATH/" 2>/dev/null; then
                    log_success "压缩备份已同步到1Panel: $ONEPANEL_BACKUP_PATH/${DATE}.tar.gz"
                else
                    log_error "同步压缩备份到1Panel失败"
                    return 1
                fi
            else
                # 复制目录
                if cp -r "$BACKUP_DIR" "$ONEPANEL_BACKUP_PATH/" 2>/dev/null; then
                    log_success "备份目录已同步到1Panel: $ONEPANEL_BACKUP_PATH/$DATE"
                else
                    log_error "同步备份目录到1Panel失败"
                    return 1
                fi
            fi
            
            # 创建1Panel备份索引文件
            echo "${DATE}" >> "$ONEPANEL_BACKUP_PATH/backup_index.txt"
            
        else
            log_error "无法创建1Panel备份目录: $ONEPANEL_BACKUP_PATH"
            return 1
        fi
    else
        log_info "跳过1Panel同步（1Panel集成已禁用）"
    fi
}

# 检查存储桶工具
check_bucket_tools() {
    case "$BUCKET_TYPE" in
        "s3")
            if ! command -v aws &> /dev/null; then
                log_error "AWS CLI 未安装，无法使用S3存储桶备份"
                return 1
            fi
            ;;
        "oss")
            if ! command -v ossutil &> /dev/null; then
                log_error "阿里云 ossutil 未安装，无法使用OSS存储桶备份"
                return 1
            fi
            ;;
        "cos")
            if ! command -v coscli &> /dev/null; then
                log_error "腾讯云 coscli 未安装，无法使用COS存储桶备份"
                return 1
            fi
            ;;
        "minio")
            if ! command -v mc &> /dev/null; then
                log_error "MinIO Client 未安装，无法使用MinIO存储桶备份"
                return 1
            fi
            ;;
        *)
            log_error "不支持的存储桶类型: $BUCKET_TYPE"
            return 1
            ;;
    esac
    return 0
}

# 上传到存储桶
upload_to_bucket() {
    if [ "$ENABLE_BUCKET_BACKUP" = "true" ]; then
        log_info "上传备份到存储桶 ($BUCKET_TYPE)..."
        
        # 检查工具
        if ! check_bucket_tools; then
            return 1
        fi
        
        local backup_file
        local remote_path
        
        if [ "$BACKUP_COMPRESS" = "true" ]; then
            backup_file="${BACKUP_BASE_DIR}/${DATE}.tar.gz"
            remote_path="${BUCKET_PATH_PREFIX}/${DATE}.tar.gz"
        else
            # 对于未压缩的备份，先创建临时压缩文件
            log_info "为存储桶上传创建临时压缩文件..."
            backup_file="${BACKUP_BASE_DIR}/${DATE}_bucket.tar.gz"
            cd "$BACKUP_BASE_DIR"
            tar -czf "${DATE}_bucket.tar.gz" "$DATE/" >> "$LOG_FILE" 2>&1
            remote_path="${BUCKET_PATH_PREFIX}/${DATE}.tar.gz"
        fi
        
        # 根据存储桶类型执行上传
        case "$BUCKET_TYPE" in
            "s3")
                upload_to_s3 "$backup_file" "$remote_path"
                ;;
            "oss")
                upload_to_oss "$backup_file" "$remote_path"
                ;;
            "cos")
                upload_to_cos "$backup_file" "$remote_path"
                ;;
            "minio")
                upload_to_minio "$backup_file" "$remote_path"
                ;;
        esac
        
        local upload_result=$?
        
        # 清理临时文件
        if [ "$BACKUP_COMPRESS" != "true" ] && [ -f "${BACKUP_BASE_DIR}/${DATE}_bucket.tar.gz" ]; then
            rm -f "${BACKUP_BASE_DIR}/${DATE}_bucket.tar.gz"
        fi
        
        return $upload_result
    else
        log_info "跳过存储桶备份（存储桶备份已禁用）"
        return 0
    fi
}

# S3上传
upload_to_s3() {
    local local_file=$1
    local remote_path=$2
    
    log_info "上传到 AWS S3: s3://$BUCKET_NAME/$remote_path"
    
    # 设置AWS配置
    export AWS_ACCESS_KEY_ID="$BUCKET_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$BUCKET_SECRET_KEY"
    export AWS_DEFAULT_REGION="$BUCKET_REGION"
    
    # 构建aws命令
    local aws_cmd="aws s3 cp \"$local_file\" \"s3://$BUCKET_NAME/$remote_path\""
    
    if [ -n "$BUCKET_ENDPOINT" ]; then
        aws_cmd="$aws_cmd --endpoint-url \"$BUCKET_ENDPOINT\""
    fi
    
    if eval "$aws_cmd" >> "$LOG_FILE" 2>&1; then
        log_success "S3上传成功: s3://$BUCKET_NAME/$remote_path"
        return 0
    else
        log_error "S3上传失败"
        return 1
    fi
}

# 阿里云OSS上传
upload_to_oss() {
    local local_file=$1
    local remote_path=$2
    
    log_info "上传到阿里云 OSS: oss://$BUCKET_NAME/$remote_path"
    
    # 配置ossutil
    local config_file="/tmp/ossutil_config_$$"
    cat > "$config_file" <<EOF
[Credentials]
language=CH
accessKeyID=$BUCKET_ACCESS_KEY
accessKeySecret=$BUCKET_SECRET_KEY
endpoint=https://$BUCKET_REGION.aliyuncs.com
EOF
    
    if ossutil cp "$local_file" "oss://$BUCKET_NAME/$remote_path" -c "$config_file" >> "$LOG_FILE" 2>&1; then
        log_success "OSS上传成功: oss://$BUCKET_NAME/$remote_path"
        rm -f "$config_file"
        return 0
    else
        log_error "OSS上传失败"
        rm -f "$config_file"
        return 1
    fi
}

# 腾讯云COS上传
upload_to_cos() {
    local local_file=$1
    local remote_path=$2
    
    log_info "上传到腾讯云 COS: cos://$BUCKET_NAME/$remote_path"
    
    # 配置coscli
    local config_file="/tmp/coscli_config_$$"
    cat > "$config_file" <<EOF
cos:
  base:
    secretid: $BUCKET_ACCESS_KEY
    secretkey: $BUCKET_SECRET_KEY
    sessiontoken: ""
    protocol: https
    region: $BUCKET_REGION
EOF
    
    if coscli cp "$local_file" "cos://$BUCKET_NAME/$remote_path" -c "$config_file" >> "$LOG_FILE" 2>&1; then
        log_success "COS上传成功: cos://$BUCKET_NAME/$remote_path"
        rm -f "$config_file"
        return 0
    else
        log_error "COS上传失败"
        rm -f "$config_file"
        return 1
    fi
}

# MinIO上传
upload_to_minio() {
    local local_file=$1
    local remote_path=$2
    
    log_info "上传到 MinIO: $BUCKET_ENDPOINT/$BUCKET_NAME/$remote_path"
    
    # 配置MinIO客户端
    local alias="minio_$$"
    
    if mc alias set "$alias" "$BUCKET_ENDPOINT" "$BUCKET_ACCESS_KEY" "$BUCKET_SECRET_KEY" >> "$LOG_FILE" 2>&1; then
        if mc cp "$local_file" "$alias/$BUCKET_NAME/$remote_path" >> "$LOG_FILE" 2>&1; then
            log_success "MinIO上传成功: $BUCKET_ENDPOINT/$BUCKET_NAME/$remote_path"
            mc alias remove "$alias" >> "$LOG_FILE" 2>&1
            return 0
        else
            log_error "MinIO上传失败"
            mc alias remove "$alias" >> "$LOG_FILE" 2>&1
            return 1
        fi
    else
        log_error "MinIO配置失败"
        return 1
    fi
}

# 清理旧备份
cleanup_old_backups() {
    log_info "清理 ${BACKUP_RETENTION_DAYS} 天前的备份..."
    
    # 清理本地备份
    local deleted_count=0
    
    # 清理压缩文件
    for file in $(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null); do
        if rm -f "$file" 2>/dev/null; then
            log_info "已删除旧备份: $(basename "$file")"
            ((deleted_count++))
        fi
    done
    
    # 清理未压缩目录
    for dir in $(find "$BACKUP_BASE_DIR" -type d -name "20*" -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null); do
        if rm -rf "$dir" 2>/dev/null; then
            log_info "已删除旧备份目录: $(basename "$dir")"
            ((deleted_count++))
        fi
    done
    
    log_info "本地清理完成，删除了 $deleted_count 个旧备份"
    
    # 清理1Panel备份
    if [ "$ONEPANEL_BACKUP_ENABLED" = "true" ] && [ -d "$ONEPANEL_BACKUP_PATH" ]; then
        local panel_deleted=0
        
        for file in $(find "$ONEPANEL_BACKUP_PATH" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null); do
            if rm -f "$file" 2>/dev/null; then
                log_info "已删除1Panel旧备份: $(basename "$file")"
                ((panel_deleted++))
            fi
        done
        
        for dir in $(find "$ONEPANEL_BACKUP_PATH" -type d -name "20*" -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null); do
            if rm -rf "$dir" 2>/dev/null; then
                log_info "已删除1Panel旧备份目录: $(basename "$dir")"
                ((panel_deleted++))
            fi
        done
        
        log_info "1Panel清理完成，删除了 $panel_deleted 个旧备份"
    fi
}

# 验证备份完整性
verify_backup() {
    log_info "验证备份完整性..."
    
    local backup_path
    if [ "$BACKUP_COMPRESS" = "true" ]; then
        backup_path="${BACKUP_BASE_DIR}/${DATE}.tar.gz"
        
        # 验证tar文件
        if tar -tzf "$backup_path" >/dev/null 2>&1; then
            log_success "压缩备份文件完整性验证通过"
        else
            log_error "压缩备份文件损坏"
            return 1
        fi
    else
        backup_path="$BACKUP_DIR"
        
        # 检查关键文件
        if [ -f "$backup_path/backup_info.json" ]; then
            log_success "备份目录完整性验证通过"
        else
            log_error "备份目录缺少关键文件"
            return 1
        fi
    fi
    
    return 0
}

# 发送通知（如果配置了）
send_notification() {
    local status=$1
    local message=$2
    
    # 这里可以集成邮件、Webhook等通知方式
    log_info "备份通知: $status - $message"
    
    # 示例：发送到Webhook
    # if [ -n "$WEBHOOK_URL" ]; then
    #     curl -X POST "$WEBHOOK_URL" \
    #          -H "Content-Type: application/json" \
    #          -d "{\"text\":\"MongoDB备份 $status: $message\"}" \
    #          2>/dev/null || true
    # fi
}

# 主函数
main() {
    local script_start_time=$(date +%s)
    
    log "🚀 开始 MongoDB 备份流程"
    log "备份ID: $DATE"
    
    # 检查副本集状态并选择备份源（只取最后一行返回值）
    local backup_host
    backup_host=$(check_replica_status | tail -n 1 | tr -d '\r\n')
    log_info "选择备份源: $backup_host"
    
    # 执行备份
    if ! perform_backup "$backup_host"; then
        send_notification "失败" "数据库转储失败"
        exit 1
    fi
    
    # 压缩备份
    if ! compress_backup; then
        send_notification "失败" "备份压缩失败"
        exit 1
    fi
    
    # 验证备份
    if ! verify_backup; then
        send_notification "失败" "备份验证失败"
        exit 1
    fi
    
    # 同步到1Panel
    sync_to_1panel
    
    # 上传到存储桶
    if ! upload_to_bucket; then
        log_error "存储桶上传失败，但备份流程继续"
    fi
    
    # 清理旧备份
    cleanup_old_backups
    
    local script_end_time=$(date +%s)
    local total_duration=$((script_end_time - script_start_time))
    
    log_success "备份流程完成，总耗时: ${total_duration}秒"
    
    # 更新备份摘要文件
    if [ -f "$SUMMARY_FILE" ]; then
        # 添加到历史记录
        echo "{\"backup_id\":\"$DATE\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"success\",\"duration\":$total_duration}" >> "$SUMMARY_FILE"
    else
        echo "{\"backup_id\":\"$DATE\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"success\",\"duration\":$total_duration}" > "$SUMMARY_FILE"
    fi
    
    send_notification "成功" "备份完成，耗时${total_duration}秒"
    
    log "🎉 备份流程成功完成"
}

# 错误处理
trap 'log_error "备份脚本异常退出"; send_notification "失败" "脚本异常退出"; exit 1' ERR

# 执行主函数
main "$@" 