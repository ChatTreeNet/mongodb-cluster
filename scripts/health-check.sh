#!/bin/bash
# MongoDB 健康检查和监控脚本
# 检查副本集状态、性能指标和系统资源

set -e

# 从环境变量获取配置
MONGO_ROOT_USER=${MONGO_ROOT_USER:-admin}
MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD:-password}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-300}

# 日志配置
LOG_DIR="/logs"
HEALTH_LOG="${LOG_DIR}/health.log"
ALERT_LOG="${LOG_DIR}/alerts.log"
METRICS_LOG="${LOG_DIR}/metrics.log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$HEALTH_LOG"
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}❌ ERROR: $1${NC}" | tee -a "$HEALTH_LOG" "$ALERT_LOG"
}

log_warning() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}⚠️  WARNING: $1${NC}" | tee -a "$HEALTH_LOG" "$ALERT_LOG"
}

log_success() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}✅ SUCCESS: $1${NC}" | tee -a "$HEALTH_LOG"
}

log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${BLUE}ℹ️  INFO: $1${NC}" | tee -a "$HEALTH_LOG"
}

# 记录指标数据
log_metric() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$METRICS_LOG"
}

# 检查单个MongoDB节点
check_mongo_node() {
    local host=$1
    local port=$2
    local name=$3
    local errors=0
    
    log_info "检查 $name ($host:$port)"
    
    # 基础连通性检查
    if timeout 10 docker exec mongo-primary mongo --host "$host:$port" --username "$MONGO_ROOT_USER" --password "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        log_success "$name 连接正常"
        
        # 获取详细状态信息
        local node_info=$(docker exec mongo-primary mongo --host "$host:$port" --username "$MONGO_ROOT_USER" --password "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval "
            var status = db.adminCommand('serverStatus');
            var replStatus;
            try {
                replStatus = rs.status();
            } catch(e) {
                replStatus = {myState: 'UNKNOWN', members: []};
            }
            
            var connections = status.connections || {current: 0, available: 1000};
            var memory = status.mem || {resident: 0, virtual: 0};
            var network = status.network || {bytesIn: 0, bytesOut: 0};
            var opcounters = status.opcounters || {query: 0, insert: 0, update: 0, delete: 0};
            
            // 计算连接使用率
            var connectionUsage = Math.round((connections.current / connections.available) * 100);
            
            // 副本集状态
            var replicaState = 'UNKNOWN';
            var replicaStateText = 'Unknown';
            if (replStatus.myState !== undefined) {
                replicaState = replStatus.myState;
                switch(replicaState) {
                    case 1: replicaStateText = 'PRIMARY'; break;
                    case 2: replicaStateText = 'SECONDARY'; break;
                    case 7: replicaStateText = 'ARBITER'; break;
                    default: replicaStateText = 'OTHER(' + replicaState + ')'; break;
                }
            }
            
            print('STATUS_OK');
            print('CONNECTIONS:' + connections.current + '/' + connections.available + '(' + connectionUsage + '%)');
            print('MEMORY:' + Math.round(memory.resident) + 'MB');
            print('REPLICA_STATE:' + replicaState + ':' + replicaStateText);
            print('OPS_QUERY:' + opcounters.query);
            print('OPS_INSERT:' + opcounters.insert);
            print('OPS_UPDATE:' + opcounters.update);
            print('OPS_DELETE:' + opcounters.delete);
            print('NETWORK_IN:' + Math.round(network.bytesIn / 1024 / 1024) + 'MB');
            print('NETWORK_OUT:' + Math.round(network.bytesOut / 1024 / 1024) + 'MB');
        " 2>/dev/null)
        
        if echo "$node_info" | grep -q "STATUS_OK"; then
            # 解析状态信息
            local connections=$(echo "$node_info" | grep "CONNECTIONS:" | cut -d: -f2)
            local memory=$(echo "$node_info" | grep "MEMORY:" | cut -d: -f2)
            local replica_state=$(echo "$node_info" | grep "REPLICA_STATE:" | cut -d: -f2)
            local ops_query=$(echo "$node_info" | grep "OPS_QUERY:" | cut -d: -f2)
            local ops_insert=$(echo "$node_info" | grep "OPS_INSERT:" | cut -d: -f2)
            local network_in=$(echo "$node_info" | grep "NETWORK_IN:" | cut -d: -f2)
            
            log_info "  📊 $name 状态详情:"
            log_info "    - 连接数: $connections"
            log_info "    - 内存使用: $memory"
            log_info "    - 副本集状态: $replica_state"
            log_info "    - 查询操作: $ops_query"
            log_info "    - 插入操作: $ops_insert"
            log_info "    - 网络入流量: $network_in"
            
            # 记录指标到metrics.log
            log_metric "$name,connections,$connections"
            log_metric "$name,memory,$memory"
            log_metric "$name,replica_state,$replica_state"
            log_metric "$name,ops_query,$ops_query"
            log_metric "$name,ops_insert,$ops_insert"
            
            # 检查告警条件
            check_node_alerts "$name" "$connections" "$memory" "$replica_state"
            
        else
            log_error "$name 状态信息获取失败"
            ((errors++))
        fi
        
    else
        log_error "$name 连接失败！"
        ((errors++))
    fi
    
    return $errors
}

# 检查节点告警条件
check_node_alerts() {
    local name=$1
    local connections=$2
    local memory=$3
    local replica_state=$4
    
    # 检查连接数告警
    local connection_usage=$(echo "$connections" | grep -o '[0-9]*%)' | tr -d '%)')
    if [ -n "$connection_usage" ] && [ "$connection_usage" -gt 80 ]; then
        log_warning "$name 连接使用率过高: ${connection_usage}%"
    fi
    
    # 检查内存使用告警
    local memory_mb=$(echo "$memory" | tr -d 'MB')
    if [ -n "$memory_mb" ] && [ "$memory_mb" -gt 1000 ]; then
        log_warning "$name 内存使用较高: ${memory_mb}MB"
    fi
    
    # 检查副本集状态
    local state_num=$(echo "$replica_state" | cut -d: -f1)
    local state_text=$(echo "$replica_state" | cut -d: -f2)
    
    if [ "$state_num" != "1" ] && [ "$state_num" != "2" ]; then
        log_warning "$name 副本集状态异常: $state_text"
    fi
}

# 检查副本集整体状态
check_replica_set_status() {
    log_info "检查副本集整体状态"
    
    local replica_info=$(docker exec mongo-primary mongo --username "$MONGO_ROOT_USER" --password "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval "
        try {
            var status = rs.status();
            var config = rs.conf();
            
            print('REPLICA_SET_OK');
            print('SET_NAME:' + status.set);
            print('TOTAL_MEMBERS:' + status.members.length);
            
            var primary = status.members.find(m => m.state === 1);
            if (primary) {
                print('PRIMARY:' + primary.name);
            } else {
                print('PRIMARY:NONE');
            }
            
            var healthy = status.members.filter(m => m.health === 1).length;
            print('HEALTHY_MEMBERS:' + healthy);
            
            var secondaries = status.members.filter(m => m.state === 2).length;
            print('SECONDARIES:' + secondaries);
            
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
            print('REPLICA_SET_ERROR:' + e.message);
        }
    " 2>/dev/null)
    
    if echo "$replica_info" | grep -q "REPLICA_SET_OK"; then
        local set_name=$(echo "$replica_info" | grep "SET_NAME:" | cut -d: -f2)
        local total_members=$(echo "$replica_info" | grep "TOTAL_MEMBERS:" | cut -d: -f2)
        local primary=$(echo "$replica_info" | grep "PRIMARY:" | cut -d: -f2)
        local healthy_members=$(echo "$replica_info" | grep "HEALTHY_MEMBERS:" | cut -d: -f2)
        local secondaries=$(echo "$replica_info" | grep "SECONDARIES:" | cut -d: -f2)
        local max_lag=$(echo "$replica_info" | grep "MAX_LAG_SECONDS:" | cut -d: -f2)
        
        log_success "副本集状态检查完成"
        log_info "  📊 副本集概览:"
        log_info "    - 集群名称: $set_name"
        log_info "    - 总节点数: $total_members"
        log_info "    - 主节点: $primary"
        log_info "    - 健康节点: $healthy_members/$total_members"
        log_info "    - 副本节点: $secondaries"
        log_info "    - 最大同步延迟: ${max_lag}秒"
        
        # 记录指标
        log_metric "replica_set,total_members,$total_members"
        log_metric "replica_set,healthy_members,$healthy_members"
        log_metric "replica_set,secondaries,$secondaries"
        log_metric "replica_set,max_lag_seconds,$max_lag"
        
        # 检查告警
        if [ "$healthy_members" -lt "$total_members" ]; then
            log_warning "检测到不健康的节点: $healthy_members/$total_members"
        fi
        
        if [ "$primary" = "NONE" ]; then
            log_error "副本集没有主节点！"
            return 1
        fi
        
        if [ -n "$max_lag" ] && [ "$max_lag" -gt 10 ]; then
            log_warning "副本同步延迟较高: ${max_lag}秒"
        fi
        
        return 0
    else
        local error_msg=$(echo "$replica_info" | grep "REPLICA_SET_ERROR:" | cut -d: -f2)
        log_error "副本集状态检查失败: $error_msg"
        return 1
    fi
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源使用情况"
    
    # 检查磁盘空间
    log_info "  💾 磁盘使用情况:"
    local disk_info=$(df -h /backup 2>/dev/null || df -h / 2>/dev/null)
    echo "$disk_info" | tail -n +2 | while read line; do
        local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local mount=$(echo "$line" | awk '{print $6}')
        log_info "    - $mount: $line"
        
        if [ "$usage" -gt 85 ]; then
            log_warning "磁盘空间不足: $mount 使用率 ${usage}%"
        fi
    done
    
    # 检查内存使用
    if command -v free >/dev/null 2>&1; then
        log_info "  🧠 内存使用情况:"
        local memory_info=$(free -h | grep -E "Mem|Swap")
        echo "$memory_info" | while read line; do
            log_info "    - $line"
        done
        
        # 检查内存使用率
        local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
        if [ "$mem_usage" -gt 90 ]; then
            log_warning "内存使用率过高: ${mem_usage}%"
        fi
    fi
    
    # 检查Docker容器状态
    if command -v docker >/dev/null 2>&1; then
        log_info "  🐳 Docker容器状态:"
        local containers="mongo-primary mongo-secondary1 mongo-secondary2"
        for container in $containers; do
            if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container"; then
                local status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | awk '{print $2" "$3}')
                log_info "    - $container: $status"
            else
                log_error "容器 $container 未运行"
            fi
        done
    fi
}

# 检查最近备份
check_recent_backups() {
    log_info "检查最近的备份"
    
    local backup_dir="/backup"
    if [ -d "$backup_dir" ]; then
        # 查找最新的备份文件
        local latest_backup=$(find "$backup_dir" -name "*.tar.gz" -o -name "20*" -type d | sort | tail -1)
        
        if [ -n "$latest_backup" ]; then
            local backup_age_hours
            if [ -f "$latest_backup" ]; then
                backup_age_hours=$((($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600))
            else
                backup_age_hours=$((($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600))
            fi
            
            log_info "  📦 最新备份: $(basename "$latest_backup") (${backup_age_hours}小时前)"
            
            if [ "$backup_age_hours" -gt 25 ]; then
                log_warning "备份文件过期: 超过25小时未更新"
            else
                log_success "备份状态正常"
            fi
            
            # 记录备份指标
            log_metric "backup,age_hours,$backup_age_hours"
            
        else
            log_error "未找到备份文件"
        fi
    else
        log_warning "备份目录不存在: $backup_dir"
    fi
}

# 生成健康检查报告
generate_health_report() {
    local report_file="${LOG_DIR}/health_report_$(date +%Y%m%d).json"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # 统计最近的错误和警告
    local recent_errors=$(grep -c "ERROR" "$HEALTH_LOG" 2>/dev/null || echo 0)
    local recent_warnings=$(grep -c "WARNING" "$HEALTH_LOG" 2>/dev/null || echo 0)
    
    cat > "$report_file" <<EOF
{
  "timestamp": "$timestamp",
  "health_check_interval": $HEALTH_CHECK_INTERVAL,
  "recent_errors": $recent_errors,
  "recent_warnings": $recent_warnings,
  "log_files": {
    "health_log": "$HEALTH_LOG",
    "alert_log": "$ALERT_LOG",
    "metrics_log": "$METRICS_LOG"
  },
  "mongodb_version": "4.4",
  "replica_set_name": "rs0"
}
EOF
    
    log_info "健康检查报告已生成: $report_file"
}

# 清理旧日志文件
cleanup_old_logs() {
    # 保留7天的日志
    find "$LOG_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    find "$LOG_DIR" -name "health_report_*.json" -mtime +7 -delete 2>/dev/null || true
}

# 主健康检查函数
main_health_check() {
    local overall_status=0
    
    log "🚀 开始 MongoDB 健康检查"
    log "检查时间: $(date)"
    
    # 检查各个MongoDB节点
    check_mongo_node "mongo-primary" "27017" "主节点" || ((overall_status++))
    check_mongo_node "mongo-secondary1" "27017" "副本节点1" || ((overall_status++))
    check_mongo_node "mongo-secondary2" "27017" "副本节点2" || ((overall_status++))
    
    # 检查副本集整体状态
    check_replica_set_status || ((overall_status++))
    
    # 检查系统资源
    check_system_resources
    
    # 检查备份状态
    check_recent_backups
    
    # 生成报告
    generate_health_report
    
    # 清理旧日志
    cleanup_old_logs
    
    if [ $overall_status -eq 0 ]; then
        log_success "健康检查完成 - 所有检查通过"
    else
        log_error "健康检查完成 - 发现 $overall_status 个问题"
    fi
    
    log "----------------------------------------"
    
    return $overall_status
}

# 如果直接运行脚本，执行健康检查
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main_health_check
fi 